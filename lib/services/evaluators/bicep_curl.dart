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

    final bool isLeftVisible = leftShoulder.likelihood > rightShoulder.likelihood;
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

    if (shoulder == null || elbow == null || wrist == null || hip == null || shoulder.likelihood < 0.5 || elbow.likelihood < 0.5) {
      return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Align side profile to camera.", 'activeJoints': activeJoints, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0};
    }

    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final torsoLength = math.sqrt(math.pow(shoulder.x - hip.x, 2) + math.pow(shoulder.y - hip.y, 2));

    final elbowAngle = calculateAngle(shoulder, elbow, wrist);
    final shoulderSwingAngle = calculateAngle(hip, shoulder, elbow);
    final horizontalSway = (shoulder.x - hip.x).abs();

    if (elbowAngle < lowestElbowAngle) lowestElbowAngle = elbowAngle;

    double rawFormScore = ((20.0 - shoulderSwingAngle) / 20.0).clamp(0.0, 1.0);
    smoothedFormScore = (smoothedFormScore * 0.8) + (rawFormScore * 0.2);

    int rawFormState = 1; 
    String rawFormError = "";
    Set<PoseLandmarkType> rawFaultyJoints = {};
    List<String> ttsVariations = [];
    bool triggerInstantKill = false; // Tracks if we should bypass the debounce

    // 3. Clinical Heuristics
    // A. Perspective Lock (Hyper-sensitive to catch partial front-facing)
    if (shoulderWidth > torsoLength * 0.40) { 
      rawFormState = -1;
      rawFaultyJoints.addAll(activeJoints);
      if (rawFormError.isEmpty) {
        rawFormError = "Face sideways.";
        ttsVariations = [
          "Turn sideways. I can't track your arm from the front.", 
          "Please face the side completely."
        ];
      }
    }
    // B. Trunk Sway 
    else if (horizontalSway > torsoLength * 0.25) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip]);
      if (rawFormError.isEmpty) {
        rawFormError = "Stop leaning back.";
        ttsVariations = ["Stop leaning back.", "Keep your torso completely still."];
      }
    }
    // C. The Elbow Pin (Instant Kill)
    else if (shoulderSwingAngle > 20.0) {
      rawFormState = -1;
      triggerInstantKill = true; // BAM. No grace period.
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow]);
      if (rawFormError.isEmpty) {
        rawFormError = "Upper arm moved.";
        ttsVariations = [
          "Keep your upper arm completely still.", 
          "Pin your elbow to your ribs.", 
          "Stop swinging your arm."
        ];
      }
    }

    processFormState(
      rawFormState: rawFormState, 
      rawFormError: rawFormError, 
      rawFaultyJoints: rawFaultyJoints, 
      ttsVariations: ttsVariations, 
      amnesiaConditionMet: elbowAngle >= 145.0,
      isInstantFault: triggerInstantKill // Feed the flag to the pipeline
    );

    // --- START THE STOPWATCH ---
    if (elbowAngle < 135.0 && repMovementStartTime == null) {
      repMovementStartTime = DateTime.now();
    }

    // --- Full Cycle Rep Logic ---
    bool goodRep = false;
    bool badRep = false;
    String repFeedback = "";

    if (isDown) {
      repFeedback = "Curl it up!";
      if (elbowAngle <= 70.0) { 
        isDown = false; 
      }
    } else {
      repFeedback = "Lower the weight fully.";
      if (elbowAngle >= 145.0) { 
        isDown = true; 
        lowestElbowAngle = 180.0;

        // CHECK THE 2.5 SECOND SPEED LIMIT
        bool isRushed = false;
        if (repMovementStartTime != null) {
          final durationMs = DateTime.now().difference(repMovementStartTime!).inMilliseconds;
          if (durationMs < 2000) isRushed = true; 
        }
        repMovementStartTime = null; 
        
        if (isRushed) {
          badRep = true;
          repFeedback = "Too fast! Control the descent.";
          AudioService.instance.speakCorrection(["Slow down.", "Control the weight on the way down."]);
        } else if (hasFormBrokenThisRep) {
          badRep = true;
          repFeedback = "Rep invalid. Watch form!";
        } else {
          goodRep = true;
          repFeedback = "Good squeeze!";
        }
      } else {
        if (elbowAngle <= 80.0 && lowestElbowAngle > 100.0) {
          AudioService.instance.speakCorrection(["Extend your arm fully at the bottom."]);
          lowestElbowAngle = 50.0; 
        }
      }
    }

    return {
      'goodRepTriggered': goodRep, 'badRepTriggered': badRep,
      'formState': publishedFormState, 'feedback': publishedFormState == -1 ? publishedFormError : repFeedback,
      'activeJoints': activeJoints, 'faultyJoints': publishedFaultyJoints, 'formScore': smoothedFormScore,
    };
  }
}