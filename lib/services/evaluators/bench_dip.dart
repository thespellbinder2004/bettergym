import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../audio_service.dart';
import '../biomechanics_engine.dart';

class BenchDipEvaluator extends BaseEvaluator {
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

    final activeJoints = <PoseLandmarkType>{
      PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist,
      PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
      PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee,
    };

    if (shoulder == null || elbow == null || wrist == null || hip == null || knee == null || shoulder.likelihood < 0.5 || hip.likelihood < 0.5) {
      return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Align side profile to camera.", 'activeJoints': activeJoints, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0};
    }

    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final torsoLength = math.sqrt(math.pow(shoulder.x - hip.x, 2) + math.pow(shoulder.y - hip.y, 2));
    final torsoDx = (shoulder.x - hip.x).abs();
    final torsoDy = (shoulder.y - hip.y).abs();
    final horizontalDrift = (hip.x - wrist.x).abs(); 

    final elbowAngle = calculateAngle(shoulder, elbow, wrist); 
    if (elbowAngle < lowestElbowAngle) lowestElbowAngle = elbowAngle;

    // Adjusted Thermometer Smoothing to match the new 100-degree depth
    double elbowScore = ((elbowAngle - 100.0) / 60.0).clamp(0.0, 1.0);
    double rawFormScore = elbowScore;
    smoothedFormScore = (smoothedFormScore * 0.8) + (rawFormScore * 0.2);

    int rawFormState = 1; 
    String rawFormError = "";
    Set<PoseLandmarkType> rawFaultyJoints = {};
    List<String> ttsVariations = [];

    if (shoulderWidth > torsoLength * 0.55) {
      rawFormState = -1;
      rawFaultyJoints.addAll(activeJoints); 
      rawFormError = "Turn sideways.";
      ttsVariations = [
        "Turn sideways.", 
        "Please face the side.",
        "Side profile needed."
      ];
    } else if (torsoDx > torsoDy) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip]);
      rawFormError = "Sit upright.";
      ttsVariations = [
        "Sit upright.", 
        "Don't lean forward.",
        "Chest up.",
        "Keep your back straight."
      ];
    } else if (horizontalDrift > torsoLength * 0.55) { // Relaxed from 0.45 to 0.55
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip]);
      rawFormError = "Hips drifting forward.";
      ttsVariations = [
        "Stay close to the bench.", 
        "Don't drift forward.", 
        "Hips back.",
        "Keep your back near the bench."
      ];
    }

    processFormState(
      rawFormState: rawFormState, rawFormError: rawFormError, 
      rawFaultyJoints: rawFaultyJoints, ttsVariations: ttsVariations, 
      amnesiaConditionMet: elbowAngle >= 145.0 // Relaxed amnesia threshold
    );

    // --- START THE STOPWATCH ---
    if (elbowAngle < 145.0 && repMovementStartTime == null) {
      repMovementStartTime = DateTime.now();
    }

    bool goodRep = false;
    bool badRep = false;
    String repFeedback = "";

    if (isDown) {
      repFeedback = "Push up!";
      // Relaxed lockout from 160.0 to 155.0
      if (elbowAngle >= 155.0) {
        isDown = false; 
        lowestElbowAngle = 180.0; 
        
        // --- CHECK THE SPEED LIMIT ---
        bool isRushed = false;
        if (repMovementStartTime != null) {
          final durationMs = DateTime.now().difference(repMovementStartTime!).inMilliseconds;
          if (durationMs < 1500) isRushed = true; 
        }
        repMovementStartTime = null; 
        
        if (isRushed) {
          badRep = true; 
          repFeedback = "Too fast! Control the rep.";
          AudioService.instance.speakCorrection([
            "Slow down.", 
            "Don't rush the rep.",
            "Control your speed."
          ]);
        } else if (hasFormBrokenThisRep) {
          badRep = true; 
          repFeedback = "Rep invalid. Watch your form!";
        } else {
          goodRep = true; 
          repFeedback = "Perfect rep!";
        }
      }
    } else {
      // Relaxed depth from 90.0 to 100.0
      if (elbowAngle <= 100.0) {
        isDown = true; 
        repFeedback = "Depth reached. Push!";
      } else {
        repFeedback = "Lower yourself.";

        // Half-rep detection adjusted for new thresholds
        if (elbowAngle >= 145.0 && lowestElbowAngle < 120.0) {
          AudioService.instance.speakCorrection([
            "Go a little lower.", 
            "Not deep enough.", 
            "Drop your hips more."
          ]);
          lowestElbowAngle = 180.0; 
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