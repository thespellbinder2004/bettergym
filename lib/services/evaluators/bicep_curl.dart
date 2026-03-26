import 'dart:math' as math;
import 'dart:ui';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../audio_service.dart';
import '../biomechanics_engine.dart';

class BicepCurlEvaluator extends BaseEvaluator {
  double _highestElbowAngle = 0.0;

  @override
  void reset() {
    super.reset();
    _highestElbowAngle = 0.0;
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
    final ankle = isLeftVisible ? landmarks[PoseLandmarkType.leftAnkle] : landmarks[PoseLandmarkType.rightAnkle];
    final nose = landmarks[PoseLandmarkType.nose];

    final activeJoints = <PoseLandmarkType>{
      PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist,
      PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
      PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle,
      PoseLandmarkType.nose,
    };

    if (shoulder == null || elbow == null || wrist == null || hip == null || ankle == null || nose == null ||
        shoulder.likelihood < 0.5 || elbow.likelihood < 0.5 || wrist.likelihood < 0.5 || hip.likelihood < 0.5) {
      return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Align side profile to camera.", 'activeJoints': activeJoints, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0};
    }

    // --- 1. MATH & GEOMETRY ---
    bool facingRight = nose.x > shoulder.x;
    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final torsoLength = math.sqrt(math.pow(shoulder.x - hip.x, 2) + math.pow(shoulder.y - hip.y, 2));

    final elbowAngle = calculateAngle(shoulder, elbow, wrist);
    
    // Calculates the angle of the upper arm relative to the vertical line of the torso
    final upperArmAngle = calculateAngle(hip, shoulder, elbow);

    final torsoDx = shoulder.x - hip.x;
    final leanAngle = math.atan2(torsoDx.abs(), (shoulder.y - hip.y).abs()) * 180 / math.pi;
    bool leaningBackward = facingRight ? torsoDx < 0 : torsoDx > 0;

    if (elbowAngle > _highestElbowAngle) _highestElbowAngle = elbowAngle;

    double armScore = ((25.0 - upperArmAngle) / 15.0).clamp(0.0, 1.0);
    double leanScore = ((15.0 - leanAngle) / 10.0).clamp(0.0, 1.0);
    double rawFormScore = math.min(armScore, leanScore);
    smoothedFormScore = (smoothedFormScore * 0.8) + (rawFormScore * 0.2);

    int rawFormState = 1; 
    String rawFormError = "";
    Set<PoseLandmarkType> rawFaultyJoints = {};
    List<String> ttsVariations = [];
    bool triggerInstantKill = false;

    // --- 2. CLINICAL HEURISTICS ---

    // A. Strict Sideways Profile
    if (shoulderWidth > torsoLength * 0.45) {
      rawFormState = -1;
      triggerInstantKill = true;
      rawFaultyJoints.addAll(activeJoints); 
      if (rawFormError.isEmpty) {
        rawFormError = "Turn sideways.";
        ttsVariations = ["Turn sideways. Portrait mode required.", "Face the side."];
      }
    }
    // B. Upper Arm Drift (The Cheater Rep)
    else if (upperArmAngle > 25.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow, PoseLandmarkType.leftHip, PoseLandmarkType.rightHip]);
      if (rawFormError.isEmpty) {
        rawFormError = "Elbows drifting.";
        ttsVariations = ["Pin your elbows to your sides.", "Stop swinging your arms.", "Keep your upper arm still."];
      }
    }
    // C. Torso Swing (Lower Back Cheating)
    else if (leaningBackward && leanAngle > 15.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.rightHip]);
      if (rawFormError.isEmpty) {
        rawFormError = "Leaning backward.";
        ttsVariations = ["Stop swinging your back.", "Don't lean backward to cheat the weight.", "Keep your torso straight."];
      }
    }

    processFormState(
      rawFormState: rawFormState, 
      rawFormError: rawFormError, 
      rawFaultyJoints: rawFaultyJoints, 
      ttsVariations: ttsVariations, 
      amnesiaConditionMet: elbowAngle >= 150.0,
      isInstantFault: triggerInstantKill
    );

    // --- START THE STOPWATCH ---
    if (elbowAngle > 150.0 && repMovementStartTime == null) {
      repMovementStartTime = DateTime.now();
    }

    // --- 3. STRICT REP LOGIC ---
    bool goodRep = false;
    bool badRep = false;
    String repFeedback = "";

    if (isDown) { // Arms extended, waiting to curl UP
      repFeedback = "Curl it up!";
      if (elbowAngle <= 60.0) {
        isDown = false; 
        _highestElbowAngle = 0.0; 
      }
    } else { // Arms curled, waiting to extend DOWN
      repFeedback = "Lower slowly...";
      if (elbowAngle >= 150.0) {
        isDown = true; 
        
        bool isRushed = false;
        if (repMovementStartTime != null) {
          final durationMs = DateTime.now().difference(repMovementStartTime!).inMilliseconds;
          if (durationMs < 1200) isRushed = true; // Speed limit enforced
        }
        repMovementStartTime = null; 
        
        if (isRushed) {
          badRep = true;
          repFeedback = "Too fast! Control the eccentric.";
          AudioService.instance.speakCorrection(["Slow down on the way down.", "Don't drop the weight.", "Control the negative."]);
        } 
        // THE FIX: The rep is irrevocably burned if they let their elbows drift or swung their back
        else if (hasFormBrokenThisRep) {
          badRep = true;
          repFeedback = "Rep invalid. Keep elbows pinned!";
        } else {
          goodRep = true;
          repFeedback = "Perfect curl!";
        }
      } else {
        // Half rep detection: Started curling back up without reaching full extension (150 degrees)
        if (elbowAngle <= 70.0 && _highestElbowAngle >= 100.0 && _highestElbowAngle < 140.0) {
          if (publishedFormState != -1) {
            AudioService.instance.speakCorrection([
              "Partial rep. Extend your arms fully.",
              "All the way down.",
              "Full range of motion."
            ]);
          }
          _highestElbowAngle = 0.0; // Reset to prevent spam
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