import 'dart:math' as math;
import 'dart:ui';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../biomechanics_engine.dart';

class PlankEvaluator extends BaseEvaluator {
  // Positional Anchors to detect swaying and arm movement
  Offset? _leftWristAnchor;
  Offset? _rightWristAnchor;

  @override
  void reset() {
    super.reset();
    _leftWristAnchor = null;
    _rightWristAnchor = null;
  }

  @override
  Map<String, dynamic> evaluate(Pose pose) {
    final landmarks = pose.landmarks;
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];

    if (leftShoulder == null || rightShoulder == null) return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Full body not visible.", 'activeJoints': <PoseLandmarkType>{}, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0};

    final bool isLeftVisible = leftShoulder.likelihood > rightShoulder.likelihood;
    
    final shoulder = isLeftVisible ? landmarks[PoseLandmarkType.leftShoulder] : landmarks[PoseLandmarkType.rightShoulder];
    final elbow = isLeftVisible ? landmarks[PoseLandmarkType.leftElbow] : landmarks[PoseLandmarkType.rightElbow];
    final wrist = isLeftVisible ? landmarks[PoseLandmarkType.leftWrist] : landmarks[PoseLandmarkType.rightWrist];
    final hip = isLeftVisible ? landmarks[PoseLandmarkType.leftHip] : landmarks[PoseLandmarkType.rightHip];
    final knee = isLeftVisible ? landmarks[PoseLandmarkType.leftKnee] : landmarks[PoseLandmarkType.rightKnee];
    final ankle = isLeftVisible ? landmarks[PoseLandmarkType.leftAnkle] : landmarks[PoseLandmarkType.rightAnkle];
    final nose = landmarks[PoseLandmarkType.nose]; 

    // We track both wrists for the sway-anchor
    final leftWrist = landmarks[PoseLandmarkType.leftWrist];
    final rightWrist = landmarks[PoseLandmarkType.rightWrist];

    final activeJoints = <PoseLandmarkType>{
      PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist,
      PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
      PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle,
      PoseLandmarkType.nose, 
    };

    if (shoulder == null || elbow == null || wrist == null || hip == null || knee == null || ankle == null || nose == null || leftWrist == null || rightWrist == null ||
        shoulder.likelihood < 0.5 || hip.likelihood < 0.5 || knee.likelihood < 0.5 || nose.likelihood < 0.5) {
      return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Align side profile to camera.", 'activeJoints': activeJoints, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0};
    }

    // 1. Math & Geometry
    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final torsoLength = math.sqrt(math.pow(shoulder.x - hip.x, 2) + math.pow(shoulder.y - hip.y, 2));

    final hipHingeAngle = calculateAngle(shoulder, hip, knee);
    final kneeFlexionAngle = calculateAngle(hip, knee, ankle);
    final elbowFlexionAngle = calculateAngle(shoulder, elbow, wrist);
    final neckSpineAngle = calculateAngle(hip, shoulder, nose); 

    double expectedHipY = shoulder.y + (hip.x - shoulder.x) * ((ankle.y - shoulder.y) / (ankle.x - shoulder.x == 0 ? 0.001 : ankle.x - shoulder.x));
    bool isSagging = hip.y > expectedHipY;

    // Anchor Logic: Set anchors if we don't have them yet and form is currently good
    if (_leftWristAnchor == null && _rightWristAnchor == null && hipHingeAngle > 165.0 && kneeFlexionAngle > 160.0) {
      _leftWristAnchor = Offset(leftWrist.x, leftWrist.y);
      _rightWristAnchor = Offset(rightWrist.x, rightWrist.y);
    }

    bool isSwaying = false;
    if (_leftWristAnchor != null && _rightWristAnchor != null) {
      final leftShift = math.sqrt(math.pow(leftWrist.x - _leftWristAnchor!.dx, 2) + math.pow(leftWrist.y - _leftWristAnchor!.dy, 2));
      final rightShift = math.sqrt(math.pow(rightWrist.x - _rightWristAnchor!.dx, 2) + math.pow(rightWrist.y - _rightWristAnchor!.dy, 2));
      
      // If wrists move more than 15% of torso length, they are swaying or adjusting arms
      if (leftShift > torsoLength * 0.15 || rightShift > torsoLength * 0.15) {
        isSwaying = true;
      }
    }

    // 2. Thermometer Smoothing
    double coreScore = ((hipHingeAngle - 155.0) / 20.0).clamp(0.0, 1.0);
    double kneeScore = ((kneeFlexionAngle - 155.0) / 20.0).clamp(0.0, 1.0);
    double rawFormScore = math.min(coreScore, kneeScore);
    smoothedFormScore = (smoothedFormScore * 0.8) + (rawFormScore * 0.2);

    int rawFormState = 1; 
    String rawFormError = "";
    Set<PoseLandmarkType> rawFaultyJoints = {};
    List<String> ttsVariations = [];
    bool triggerInstantKill = false;

    // 3. Clinical Heuristics
    if (shoulderWidth > torsoLength * 0.55) {
      rawFormState = -1;
      rawFaultyJoints.addAll(activeJoints);
      if (rawFormError.isEmpty) {
        rawFormError = "Turn sideways.";
        ttsVariations = ["Turn sideways.", "Please face sideways to the camera."];
      }
    } else if (isSwaying) {
      rawFormState = -1;
      triggerInstantKill = true; // Movement in a static hold is an instant break
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist]);
      if (rawFormError.isEmpty) {
        rawFormError = "Stop moving.";
        ttsVariations = ["Hold still.", "Stop swaying.", "Don't move your arms."];
      }
    } else if (elbowFlexionAngle < 160.0) {
      // Assumes standard high-plank. If you want forearm planks, this needs to be ~90 degrees.
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist]);
      if (rawFormError.isEmpty) {
        rawFormError = "Arms bending.";
        ttsVariations = ["Keep your arms straight.", "Lock your elbows.", "Don't bend your arms."];
      }
    } else if (kneeFlexionAngle < 160.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle, PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle]);
      if (rawFormError.isEmpty) {
        rawFormError = "Knees bent.";
        ttsVariations = ["Straighten your legs.", "Lock your knees out.", "Keep your legs straight."];
      }
    } else if (hipHingeAngle < 165.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee]);
      if (rawFormError.isEmpty) {
        if (isSagging) {
          rawFormError = "Hips sagging.";
          ttsVariations = ["Hips are dropping.", "Keep your back straight.", "Tighten your core."];
        } else {
          rawFormError = "Butt too high.";
          ttsVariations = ["Lower your hips.", "Bring your hips down into a straight line."];
        }
      }
    } else if (neckSpineAngle < 150.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.nose, PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder]);
      if (rawFormError.isEmpty) {
        rawFormError = "Head dropping.";
        ttsVariations = ["Look at the floor between your hands.", "Keep your neck neutral.", "Lift your head."];
      }
    }

    processFormState(
      rawFormState: rawFormState, 
      rawFormError: rawFormError, 
      rawFaultyJoints: rawFaultyJoints, 
      ttsVariations: ttsVariations, 
      amnesiaConditionMet: false, // No rest during a plank
      isInstantFault: triggerInstantKill
    );

    // If form broke, clear the anchors so they can reset their position
    if (publishedFormState == -1) {
      _leftWristAnchor = null;
      _rightWristAnchor = null;
    }

    return {
      'goodRepTriggered': false, 
      'badRepTriggered': false, 
      'formState': publishedFormState, 
      'feedback': publishedFormState == -1 ? publishedFormError : "Hold it... Core tight!",
      'activeJoints': activeJoints, 
      'faultyJoints': publishedFaultyJoints, 
      'formScore': smoothedFormScore,
    };
  }
}