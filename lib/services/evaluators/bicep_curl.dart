import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../audio_service.dart';
import '../biomechanics_engine.dart';

class BicepCurlEvaluator extends BaseEvaluator {
  @override
  Map<String, dynamic> evaluate(Pose pose) {
    final landmarks = pose.landmarks;
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];

    if (leftShoulder == null || rightShoulder == null) return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Full body not visible.", 'activeJoints': <PoseLandmarkType>{}, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0};

    // --- GRAY OUT LOWER BODY ---
    // By excluding hips, knees, and ankles from this set, the UI renders them gray.
    final activeJoints = <PoseLandmarkType>{
      PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist,
      PoseLandmarkType.nose,
    };

    final leftElbow = landmarks[PoseLandmarkType.leftElbow];
    final leftWrist = landmarks[PoseLandmarkType.leftWrist];
    final rightElbow = landmarks[PoseLandmarkType.rightElbow];
    final rightWrist = landmarks[PoseLandmarkType.rightWrist];
    final leftHip = landmarks[PoseLandmarkType.leftHip];
    final rightHip = landmarks[PoseLandmarkType.rightHip];

    if (leftElbow == null || leftWrist == null || rightElbow == null || rightWrist == null || leftHip == null || rightHip == null) {
      return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Align body to camera.", 'activeJoints': activeJoints, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0};
    }

    // 1. Dual-Perspective Detection
    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final hipWidth = (leftHip.x - rightHip.x).abs();
    
    // If the distance between shoulders is wide, they are facing the camera.
    // If the distance is narrow, they are standing sideways.
    bool isFrontFacing = shoulderWidth > 50.0; // Dynamic threshold based on pixel delta

    int rawFormState = 1; 
    String rawFormError = "";
    Set<PoseLandmarkType> rawFaultyJoints = {};
    List<String> ttsVariations = [];

    double currentRepMetric = 0.0; // Will hold either angle (side) or ratio (front)
    double targetBottom = 0.0;
    double targetTop = 0.0;
    
    // =========================================================
    // BRANCH A: FRONT-FACING LOGIC
    // =========================================================
    if (isFrontFacing) {
      // Find the active arm (the one moving the most)
      final leftArmDelta = (leftWrist.y - leftShoulder.y).abs();
      final rightArmDelta = (rightWrist.y - rightShoulder.y).abs();
      bool isLeftActive = leftArmDelta < rightArmDelta; // Smaller Y delta = arm is curled up

      final activeWrist = isLeftActive ? leftWrist : rightWrist;
      final activeShoulder = isLeftActive ? leftShoulder : rightShoulder;
      final activeElbow = isLeftActive ? leftElbow : rightElbow;

      // MATH: Y-Axis Ratio (Solves Foreshortening)
      // 1.0 = Arm completely straight. 0.0 = Wrist touching shoulder.
      final totalArmLength = _calculateDistance(activeShoulder, activeElbow) + _calculateDistance(activeElbow, activeWrist);
      currentRepMetric = (activeWrist.y - activeShoulder.y) / (totalArmLength == 0 ? 1 : totalArmLength);
      
      targetBottom = 0.85; // 85% extended
      targetTop = 0.25;    // 25% compressed

      if (currentRepMetric > lowestElbowAngle) lowestElbowAngle = currentRepMetric; // Track depth

      // HEURISTICS: Frontal Plane
      final elbowFlare = (activeElbow.x - activeShoulder.x).abs();
      final torsoSway = ((leftShoulder.x + rightShoulder.x)/2 - (leftHip.x + rightHip.x)/2).abs();

      if (elbowFlare > shoulderWidth * 0.4) {
        rawFormState = -1;
        rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow]);
        rawFormError = "Keep elbows tucked.";
        ttsVariations = ["Keep your elbows pinned to your ribs.", "Don't let your elbows flare out."];
      } else if (torsoSway > shoulderWidth * 0.3) {
        rawFormState = -1;
        rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder]);
        rawFormError = "Stop swaying.";
        ttsVariations = ["Keep your core tight. Don't sway side to side.", "Stop using your body to swing the weight."];
      }

      smoothedFormScore = (smoothedFormScore * 0.8) + (((elbowFlare < shoulderWidth * 0.2) ? 1.0 : 0.0) * 0.2);
    } 
    // =========================================================
    // BRANCH B: SIDE-PROFILE LOGIC
    // =========================================================
    else {
      final bool isLeftVisible = leftShoulder.likelihood > rightShoulder.likelihood;
      final shoulder = isLeftVisible ? leftShoulder : rightShoulder;
      final elbow = isLeftVisible ? leftElbow : rightElbow;
      final wrist = isLeftVisible ? leftWrist : rightWrist;
      final hip = isLeftVisible ? leftHip : rightHip;

      currentRepMetric = calculateAngle(shoulder, elbow, wrist);
      targetBottom = 150.0;
      targetTop = 50.0;

      if (currentRepMetric < lowestElbowAngle) lowestElbowAngle = currentRepMetric;

      final shoulderSwingAngle = calculateAngle(hip, shoulder, elbow);
      final horizontalSway = (shoulder.x - hip.x).abs();
      final torsoLength = _calculateDistance(shoulder, hip);

      // HEURISTICS: Sagittal Plane
      if (horizontalSway > torsoLength * 0.20) {
        rawFormState = -1;
        rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder]);
        rawFormError = "Stop leaning back.";
        ttsVariations = ["Stop leaning back. Keep your torso still.", "Don't use your lower back to lift."];
      } else if (shoulderSwingAngle > 25.0) {
        rawFormState = -1;
        rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow]);
        rawFormError = "Stop swinging.";
        ttsVariations = ["Keep elbows pinned.", "Stop swinging your arms forward."];
      }

      double rawFormScore = ((25.0 - shoulderSwingAngle) / 25.0).clamp(0.0, 1.0);
      smoothedFormScore = (smoothedFormScore * 0.8) + (rawFormScore * 0.2);
    }

    // --- Master Pipeline Processing ---
    processFormState(
      rawFormState: rawFormState, 
      rawFormError: rawFormError, 
      rawFaultyJoints: rawFaultyJoints, 
      ttsVariations: ttsVariations, 
      amnesiaConditionMet: isFrontFacing ? (currentRepMetric >= targetBottom) : (currentRepMetric >= targetBottom) 
    );

    // --- Strict Rep Logic ---
    bool goodRep = false;
    bool badRep = false;
    String repFeedback = "";

    // The logic flips depending on if it's an angle (high is straight) or ratio (high is straight)
    bool isExtended = isFrontFacing ? currentRepMetric >= targetBottom : currentRepMetric >= targetBottom;
    bool isCurled = isFrontFacing ? currentRepMetric <= targetTop : currentRepMetric <= targetTop;

    if (isDown) {
      repFeedback = "Curl it up!";
      if (isCurled) { 
        isDown = false; 
        lowestElbowAngle = isFrontFacing ? 0.0 : 180.0;
        
        if (hasFormBrokenThisRep) {
          badRep = true; repFeedback = "Rep invalid. Watch form!";
        } else {
          goodRep = true; repFeedback = "Good squeeze!";
        }
      }
    } else {
      if (isExtended) { 
        isDown = true; 
        repFeedback = "Fully extended. Curl!";
      } else {
        repFeedback = "Lower the weight fully.";
      }
    }

    return {
      'goodRepTriggered': goodRep, 'badRepTriggered': badRep,
      'formState': publishedFormState, 'feedback': publishedFormState == -1 ? publishedFormError : repFeedback,
      'activeJoints': activeJoints, 'faultyJoints': publishedFaultyJoints, 'formScore': smoothedFormScore,
    };
  }

  double _calculateDistance(PoseLandmark p1, PoseLandmark p2) {
    return math.sqrt(math.pow(p1.x - p2.x, 2) + math.pow(p1.y - p2.y, 2));
  }
}