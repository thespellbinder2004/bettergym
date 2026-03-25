import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../biomechanics_engine.dart';

class PlankEvaluator extends BaseEvaluator {
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
    final nose = landmarks[PoseLandmarkType.nose]; // Added the nose

    final activeJoints = <PoseLandmarkType>{
      PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist,
      PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
      PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle,
      PoseLandmarkType.nose, // Tracking the head
    };

    if (shoulder == null || elbow == null || wrist == null || hip == null || knee == null || ankle == null || nose == null ||
        shoulder.likelihood < 0.5 || hip.likelihood < 0.5 || knee.likelihood < 0.5 || nose.likelihood < 0.5) {
      return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Align side profile to camera.", 'activeJoints': activeJoints, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0};
    }

    // 1. Math & Geometry
    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final torsoLength = math.sqrt(math.pow(shoulder.x - hip.x, 2) + math.pow(shoulder.y - hip.y, 2));

    final hipHingeAngle = calculateAngle(shoulder, hip, knee);
    final kneeFlexionAngle = calculateAngle(hip, knee, ankle);
    final neckSpineAngle = calculateAngle(hip, shoulder, nose); // Tracks the head dropping

    double expectedHipY = shoulder.y + (hip.x - shoulder.x) * ((ankle.y - shoulder.y) / (ankle.x - shoulder.x == 0 ? 0.001 : ankle.x - shoulder.x));
    bool isSagging = hip.y > expectedHipY;

    // 2. Thermometer Smoothing
    double coreScore = ((hipHingeAngle - 155.0) / 20.0).clamp(0.0, 1.0);
    double kneeScore = ((kneeFlexionAngle - 155.0) / 20.0).clamp(0.0, 1.0);
    double rawFormScore = math.min(coreScore, kneeScore);
    smoothedFormScore = (smoothedFormScore * 0.8) + (rawFormScore * 0.2);

    int rawFormState = 1; 
    String rawFormError = "";
    Set<PoseLandmarkType> rawFaultyJoints = {};
    List<String> ttsVariations = [];

    // 3. Clinical Heuristics
    if (shoulderWidth > torsoLength * 0.55) {
      rawFormState = -1;
      rawFaultyJoints.addAll(activeJoints);
      if (rawFormError.isEmpty) {
        rawFormError = "Turn sideways.";
        ttsVariations = ["Turn sideways. Front view is not supported.", "Please face sideways to the camera."];
      }
    } else if (kneeFlexionAngle < 160.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle, PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle]);
      if (rawFormError.isEmpty) {
        rawFormError = "Knees bent.";
        ttsVariations = ["Knees are bent, straighten your legs.", "Keep your legs completely straight.", "Lock your knees out."];
      }
    } else if (hipHingeAngle < 165.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee]);
      if (rawFormError.isEmpty) {
        if (isSagging) {
          rawFormError = "Hips sagging.";
          ttsVariations = ["Hips are dropping. Squeeze your core.", "Keep your back straight. Don't let your hips sag.", "Tighten your core. Hips are falling."];
        } else {
          rawFormError = "Butt too high.";
          ttsVariations = ["Lower your hips. Your butt is too high.", "Bring your hips down into a straight line.", "Flatten your back. Hips are too high."];
        }
      }
    } 
    // NEW: "Tech Neck" Check
    else if (neckSpineAngle < 150.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.nose, PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.rightHip]);
      if (rawFormError.isEmpty) {
        rawFormError = "Head dropping.";
        ttsVariations = ["Don't drop your head. Look at the floor between your hands.", "Keep your neck neutral.", "Lift your head up slightly."];
      }
    }

    processFormState(
      rawFormState: rawFormState, 
      rawFormError: rawFormError, 
      rawFaultyJoints: rawFaultyJoints, 
      ttsVariations: ttsVariations, 
      amnesiaConditionMet: false // No rest during a plank!
    );

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