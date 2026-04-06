import 'dart:math' as math;
import 'dart:ui';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
// AUDIO SERVICE IMPORT DELETED
import '../biomechanics_engine.dart';

class PlankEvaluator extends BaseEvaluator {
  // Positional Anchors moved to ELBOWS instead of wrists
  Offset? _leftElbowAnchor;
  Offset? _rightElbowAnchor;

  @override
  void reset() {
    super.reset();
    _leftElbowAnchor = null;
    _rightElbowAnchor = null;
  }

  @override
  Map<String, dynamic> evaluate(Pose pose) {
    final landmarks = pose.landmarks;
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];

    // INJECTION: Added 'audioCue': null to bailout
    if (leftShoulder == null || rightShoulder == null) return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Full body not visible.", 'activeJoints': <PoseLandmarkType>{}, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0, 'audioCue': null};

    final bool isLeftVisible = leftShoulder.likelihood > rightShoulder.likelihood;
    
    final shoulder = isLeftVisible ? landmarks[PoseLandmarkType.leftShoulder] : landmarks[PoseLandmarkType.rightShoulder];
    final elbow = isLeftVisible ? landmarks[PoseLandmarkType.leftElbow] : landmarks[PoseLandmarkType.rightElbow];
    final hip = isLeftVisible ? landmarks[PoseLandmarkType.leftHip] : landmarks[PoseLandmarkType.rightHip];
    final knee = isLeftVisible ? landmarks[PoseLandmarkType.leftKnee] : landmarks[PoseLandmarkType.rightKnee];
    final ankle = isLeftVisible ? landmarks[PoseLandmarkType.leftAnkle] : landmarks[PoseLandmarkType.rightAnkle];
    final nose = landmarks[PoseLandmarkType.nose]; 

    final leftElbow = landmarks[PoseLandmarkType.leftElbow];
    final rightElbow = landmarks[PoseLandmarkType.rightElbow];

    // Wrists are explicitly removed. They will render as gray/inactive.
    final activeJoints = <PoseLandmarkType>{
      PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
      PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle,
      PoseLandmarkType.nose, 
    };

    // INJECTION: Added 'audioCue': null to bailout
    if (shoulder == null || elbow == null || hip == null || knee == null || ankle == null || nose == null || leftElbow == null || rightElbow == null ||
        shoulder.likelihood < 0.5 || hip.likelihood < 0.5 || knee.likelihood < 0.5 || nose.likelihood < 0.5) {
      return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Align side profile to camera.", 'activeJoints': activeJoints, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0, 'audioCue': null};
    }

    // 1. Math & Geometry
    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final torsoLength = math.sqrt(math.pow(shoulder.x - hip.x, 2) + math.pow(shoulder.y - hip.y, 2));

    final hipHingeAngle = calculateAngle(shoulder, hip, knee);
    final kneeFlexionAngle = calculateAngle(hip, knee, ankle);
    final shoulderFlexionAngle = calculateAngle(hip, shoulder, elbow); // Tracks upper arm alignment
    final neckSpineAngle = calculateAngle(hip, shoulder, nose); 

    // THE FIX: Flipped greater/less-than logic to correct the camera inversion
    double expectedHipY = shoulder.y + (hip.x - shoulder.x) * ((ankle.y - shoulder.y) / (ankle.x - shoulder.x == 0 ? 0.001 : ankle.x - shoulder.x));
    bool isSagging = hip.y < expectedHipY;

    // Anchor Logic: Set anchors to elbows if form is solid
    if (_leftElbowAnchor == null && _rightElbowAnchor == null && hipHingeAngle > 165.0 && kneeFlexionAngle > 160.0) {
      _leftElbowAnchor = Offset(leftElbow.x, leftElbow.y);
      _rightElbowAnchor = Offset(rightElbow.x, rightElbow.y);
    }

    bool isSwaying = false;
    if (_leftElbowAnchor != null && _rightElbowAnchor != null) {
      final leftShift = math.sqrt(math.pow(leftElbow.x - _leftElbowAnchor!.dx, 2) + math.pow(leftElbow.y - _leftElbowAnchor!.dy, 2));
      final rightShift = math.sqrt(math.pow(rightElbow.x - _rightElbowAnchor!.dx, 2) + math.pow(rightElbow.y - _rightElbowAnchor!.dy, 2));
      
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

    // 3. Clinical Heuristics (REORDERED FOR PROPER PRIORITY)
    
    // PRIORITY 1: Perspective
    if (shoulderWidth > torsoLength * 0.55) {
      rawFormState = -1;
      rawFaultyJoints.addAll(activeJoints);
      if (rawFormError.isEmpty) {
        rawFormError = "Look away from camera.";
        ttsVariations = [
          "Turn sideways. Do not look at the camera. Focus on your form and listen for the timer.",
          "For accurate feedback, please position yourself in a side profile facing away from the camera.",
          "Please adjust your position to a side profile, looking away from the camera. This will help us provide better feedback on your form.",
          "To ensure the best feedback, please turn to a side profile and avoid looking directly at the camera. Focus on your form and listen for the timer cues.",
          "For optimal feedback, please position yourself in a side profile facing away from the camera. This will allow us to better analyze your form and provide accurate guidance."
        ];
      }
    } 
    // PRIORITY 2: Core/Hips (Shadowing fixed)
    else if (hipHingeAngle < 165.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee]);
      if (rawFormError.isEmpty) {
        if (isSagging) {
          rawFormError = "Hips sagging.";
          ttsVariations = ["Hips are dropping.", "Keep your back straight.", "Tighten your core.", "Engage your abs to lift your hips.", "Don't let your hips drop. Keep your core tight."," Your hips should be in line with your shoulders and ankles.", "Imagine a straight line from your shoulders to your ankles. Keep your hips on that line."];
        } else {
          rawFormError = "Butt too high.";
          ttsVariations = ["Lower your hips.", "Bring your hips down into a straight line.", "Your hips should be in line with your shoulders and ankles. Try to lower your hips a bit.", "Imagine a straight line from your shoulders to your ankles. Keep your hips on that line.", "Don't raise your hips too high. Keep your core engaged and bring your hips down."];
        }
      }
    } 
    // PRIORITY 3: Knees
    else if (kneeFlexionAngle < 160.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle, PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle]);
      if (rawFormError.isEmpty) {
        rawFormError = "Knees bent.";
        ttsVariations = ["Straighten your legs.", "Lock your knees out.", "Keep your legs straight.", "Engage your leg muscles and straighten your knees.", "Your legs should be straight. Try to lock out your knees."," Imagine trying to push the floor away with your feet. This can help you straighten your legs."];
      }
    } 
    // PRIORITY 4: Upper Arm Alignment (Replaces straight-arm rule)
    else if (shoulderFlexionAngle < 65.0 || shoulderFlexionAngle > 115.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftHip, PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, PoseLandmarkType.rightHip, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow]);
      if (rawFormError.isEmpty) {
        rawFormError = "Elbows misaligned.";
        ttsVariations = ["Stack your elbows directly under your shoulders.", "Adjust your arms.", "Elbows straight down."," Keep your upper arms perpendicular to the floor.", "Your elbows should be directly under your shoulders. Try adjusting your arm position."];
      }
    } 
    // PRIORITY 5: Swaying (Elbow Anchors)
    else if (isSwaying) {
      rawFormState = -1;
      triggerInstantKill = true; 
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow]);
      if (rawFormError.isEmpty) {
        rawFormError = "Stop moving.";
        ttsVariations = ["Hold still.", "Stop swaying.", "Lock your body in place.", "Stay steady and avoid unnecessary movement.", "Your body should be still. Try to hold your position without swaying."];
      }
    } 
    // PRIORITY 6: Neck (Relaxed from 150 to 135)
    else if (neckSpineAngle < 135.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.nose, PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder]);
      if (rawFormError.isEmpty) {
        rawFormError = "Head dropping.";
        ttsVariations = ["Don't let your head hang.", "Lift your head slightly.", "Keep your neck in line with your spine.", "Maintain a neutral neck position.", "Avoid letting your head drop forward.", "Imagine holding an apple under your chin to keep your neck aligned."];
      }
    }

    // INJECTION: Capture the audio cue payload
    List<String>? audioCuePayload = processFormState(
      rawFormState: rawFormState, 
      rawFormError: rawFormError, 
      rawFaultyJoints: rawFaultyJoints, 
      ttsVariations: ttsVariations, 
      amnesiaConditionMet: false, // No rest during a plank
      isInstantFault: triggerInstantKill
    );

    // If form broke, clear the elbow anchors so they can adjust
    if (publishedFormState == -1) {
      _leftElbowAnchor = null;
      _rightElbowAnchor = null;
    }

    // INJECTION: Final pipeline completion
    return {
      'goodRepTriggered': false, 
      'badRepTriggered': false, 
      'formState': publishedFormState, 
      'feedback': publishedFormState == -1 ? publishedFormError : "Hold it... Core tight!",
      'activeJoints': activeJoints, 
      'faultyJoints': publishedFaultyJoints, 
      'formScore': smoothedFormScore,
      'audioCue': audioCuePayload, // PIPELINE COMPLETED
    };
  }
}