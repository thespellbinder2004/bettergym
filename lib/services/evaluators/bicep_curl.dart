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

    // Relaxed scoring threshold for swing
    double rawFormScore = ((30.0 - shoulderSwingAngle) / 30.0).clamp(0.0, 1.0);
    smoothedFormScore = (smoothedFormScore * 0.8) + (rawFormScore * 0.2);

    int rawFormState = 1; 
    String rawFormError = "";
    Set<PoseLandmarkType> rawFaultyJoints = {};
    List<String> ttsVariations = [];

    // 3. Clinical Heuristics
    // A. Perspective Lock 
    if (shoulderWidth > torsoLength * 0.6) {
      rawFormState = -1;
      rawFaultyJoints.addAll(activeJoints);
      if (rawFormError.isEmpty) {
        rawFormError = "Face sideways.";
        ttsVariations = [
          "Face sideways. The camera cannot track your elbow angle from the front.", 
          "Turn to the side. I need to see your arm bend."
        ];
      }
    }
    // B. Trunk Sway (Relaxed to 25% of torso length to allow natural bracing)
    else if (horizontalSway > torsoLength * 0.25) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip]);
      if (rawFormError.isEmpty) {
        rawFormError = "Stop leaning back.";
        ttsVariations = ["Stop leaning back. Keep your torso still.", "Don't use your back to lift the weight."];
      }
    }
    // C. Elbow Pin (Relaxed to 30 degrees to allow natural biomechanical shift)
    else if (shoulderSwingAngle > 30.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftHip, PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, PoseLandmarkType.rightHip, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow]);
      if (rawFormError.isEmpty) {
        rawFormError = "Stop swinging.";
        ttsVariations = ["Keep elbows pinned to your ribs.", "Lock your elbows. Stop swinging forward."];
      }
    }

    processFormState(
      rawFormState: rawFormState, 
      rawFormError: rawFormError, 
      rawFaultyJoints: rawFaultyJoints, 
      ttsVariations: ttsVariations, 
      amnesiaConditionMet: elbowAngle >= 145.0 
    );

    // --- START THE STOPWATCH ---
    if (elbowAngle < 135.0 && repMovementStartTime == null) {
      repMovementStartTime = DateTime.now();
    }

    // --- Full Cycle Rep Logic ---
    bool goodRep = false;
    bool badRep = false;
    String repFeedback = "";

    // For Curls: isDown = true means arm is fully extended. isDown = false means curled up.
    if (isDown) {
      repFeedback = "Curl it up!";
      // Adjusted from 50.0 to 70.0 to account for bicep mass and dumbbell occlusion
      if (elbowAngle <= 70.0) { 
        isDown = false; // Top of the rep reached
      }
    } else {
      repFeedback = "Lower the weight fully.";
      // Adjusted from 150.0 to 145.0 to account for camera perspective on full extension
      if (elbowAngle >= 145.0) { 
        isDown = true; // Rep Cycle Complete
        lowestElbowAngle = 180.0;

        // --- CHECK THE 2.5 SECOND SPEED LIMIT ---
        bool isRushed = false;
        if (repMovementStartTime != null) {
          final durationMs = DateTime.now().difference(repMovementStartTime!).inMilliseconds;
          if (durationMs < 2500) isRushed = true; // Bumped to 2.5 seconds
        }
        repMovementStartTime = null; 
        
        if (isRushed) {
          badRep = true;
          repFeedback = "Too fast! Control the descent.";
          AudioService.instance.speakCorrection(["Slow down.", "Control the weight on the way down.", "Too fast. Time under tension."]);
        } else if (hasFormBrokenThisRep) {
          badRep = true;
          repFeedback = "Rep invalid. Watch form!";
        } else {
          goodRep = true;
          repFeedback = "Good squeeze!";
        }
      } else {
        // Half-Rep Detection (if they don't go all the way down before curling back up)
        if (elbowAngle <= 80.0 && lowestElbowAngle > 100.0) {
          AudioService.instance.speakCorrection(["Extend your arms fully at the bottom.", "Full range of motion."]);
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