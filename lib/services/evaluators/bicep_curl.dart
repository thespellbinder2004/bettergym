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

    if (leftShoulder == null || rightShoulder == null) {
      return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Full body not visible.", 'activeJoints': <PoseLandmarkType>{}, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0};
    }

    final bool isLeftVisible = leftShoulder.likelihood > rightShoulder.likelihood;
    
    // Joint mapping based on the visible side
    final shoulder = isLeftVisible ? landmarks[PoseLandmarkType.leftShoulder] : landmarks[PoseLandmarkType.rightShoulder];
    final elbow = isLeftVisible ? landmarks[PoseLandmarkType.leftElbow] : landmarks[PoseLandmarkType.rightElbow];
    final wrist = isLeftVisible ? landmarks[PoseLandmarkType.leftWrist] : landmarks[PoseLandmarkType.rightWrist];
    final hip = isLeftVisible ? landmarks[PoseLandmarkType.leftHip] : landmarks[PoseLandmarkType.rightHip];

    final activeJoints = <PoseLandmarkType>{
      PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist,
      PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
    };

    // Ensure all critical joints for a curl are visible
    if (shoulder == null || elbow == null || wrist == null || hip == null || 
        shoulder.likelihood < 0.5 || elbow.likelihood < 0.5 || wrist.likelihood < 0.5) {
      return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Align side profile to camera.", 'activeJoints': activeJoints, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0};
    }

    // 1. Math & Geometry
    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final torsoLength = math.sqrt(math.pow(shoulder.x - hip.x, 2) + math.pow(shoulder.y - hip.y, 2));

    final elbowAngle = calculateAngle(shoulder, elbow, wrist);
    final shoulderSwingAngle = calculateAngle(hip, shoulder, elbow);

    // 2. Thermometer Smoothing
    // Perfect form is 0 swing. It drains as swing approaches 35 degrees.
    double rawFormScore = ((35.0 - shoulderSwingAngle) / 20.0).clamp(0.0, 1.0);
    smoothedFormScore = (smoothedFormScore * 0.8) + (rawFormScore * 0.2);

    int rawFormState = 1; 
    String rawFormError = "";
    Set<PoseLandmarkType> rawFaultyJoints = {};
    List<String> ttsVariations = [];

    // 3. Heuristics
    // A. Perspective Lock
    if (shoulderWidth > torsoLength * 0.6) {
      rawFormState = -1;
      rawFaultyJoints.addAll(activeJoints);
      if (rawFormError.isEmpty) {
        rawFormError = "Turn sideways.";
        ttsVariations = ["Turn sideways. Front view is not supported.", "Please face sideways to the camera."];
      }
    }
    // B. Elbow Pin (Anti-Swing)
    else if (shoulderSwingAngle > 35.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftHip, PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, PoseLandmarkType.rightHip, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow]);
      if (rawFormError.isEmpty) {
        rawFormError = "Stop swinging.";
        ttsVariations = ["Keep elbows tucked! Stop swinging.", "Lock your elbows to your side.", "Don't swing the weight."];
      }
    }

    // 4. Pass to Master Pipeline
    processFormState(
      rawFormState: rawFormState, 
      rawFormError: rawFormError, 
      rawFaultyJoints: rawFaultyJoints, 
      ttsVariations: ttsVariations, 
      amnesiaConditionMet: elbowAngle >= 150.0 // Arm extended = resting state
    );

    // 5. Strict Rep Logic
    bool goodRep = false;
    bool badRep = false;
    String repFeedback = "";

    // isDown = true means the arm is fully extended (weight is at the bottom)
    if (isDown) {
      repFeedback = "Curl it up!";
      if (elbowAngle < 50.0) { // Full curl reached
        isDown = false; 
        
        if (hasFormBrokenThisRep) {
          badRep = true;
          repFeedback = "Rep invalid. Stop swinging!";
        } else {
          goodRep = true;
          repFeedback = "Good squeeze!";
        }
      }
    } else {
      if (elbowAngle > 150.0) { // Full extension reached
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
}