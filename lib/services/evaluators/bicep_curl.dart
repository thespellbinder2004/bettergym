import 'dart:math' as math;
import 'dart:ui';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
// AUDIO SERVICE IMPORT DELETED - Logic engines must remain hardware-agnostic
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

    // INJECTION: Added 'audioCue': null to handle early exits safely
    if (leftShoulder == null || rightShoulder == null) return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Full body not visible.", 'activeJoints': <PoseLandmarkType>{}, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0, 'audioCue': null};

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

    // INJECTION: Added 'audioCue': null
    if (shoulder == null || elbow == null || wrist == null || hip == null || ankle == null || nose == null ||
        shoulder.likelihood < 0.5 || elbow.likelihood < 0.5 || wrist.likelihood < 0.5 || hip.likelihood < 0.5) {
      return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Align side profile to camera.", 'activeJoints': activeJoints, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0, 'audioCue': null};
    }

    // --- 1. MATH & GEOMETRY ---
    bool facingRight = nose.x > shoulder.x;
    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final torsoLength = math.sqrt(math.pow(shoulder.x - hip.x, 2) + math.pow(shoulder.y - hip.y, 2));

    final elbowAngle = calculateAngle(shoulder, elbow, wrist);
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

    if (shoulderWidth > torsoLength * 0.45) {
      rawFormState = -1;
      triggerInstantKill = true;
      rawFaultyJoints.addAll(activeJoints); 
      if (rawFormError.isEmpty) {
        rawFormError = "Turn sideways.";
        ttsVariations = ["Turn sideways. Portrait mode required.", "Face the side.", "Align your body perpendicular to the camera.", "Position yourself sideways to the camera.", "Rotate your body 90 degrees.", "Side profile needed for this exercise."];
      }
    }
    else if (upperArmAngle > 25.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow, PoseLandmarkType.leftHip, PoseLandmarkType.rightHip]);
      if (rawFormError.isEmpty) {
        rawFormError = "Elbows drifting.";
        ttsVariations = ["Pin your elbows to your sides.", "Stop swinging your arms.", "Keep your upper arm still.", "Focus on moving only your forearms.", "Don't let your elbows flare out.", "Keep your elbows tucked in."];
      }
    }
    else if (leaningBackward && leanAngle > 15.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.rightHip]);
      if (rawFormError.isEmpty) {
        rawFormError = "Leaning backward.";
        ttsVariations = ["Stop swinging your back.", "Don't lean backward to cheat the weight.", "Keep your torso straight.", "Focus on using your arms, not your back.", "Maintain an upright posture.", "Avoid leaning back during the curl."];
      }
    }

    // INJECTION: Capture the audio cue payload from the BaseEvaluator
    List<String>? audioCuePayload = processFormState(
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

    if (isDown) { 
      repFeedback = "Curl it up!";
      if (elbowAngle <= 60.0) {
        isDown = false; 
        _highestElbowAngle = 0.0; 
      }
    } else { 
      repFeedback = "Lower slowly...";
      if (elbowAngle >= 150.0) {
        isDown = true; 
        
        bool isRushed = false;
        if (repMovementStartTime != null) {
          final durationMs = DateTime.now().difference(repMovementStartTime!).inMilliseconds;
          if (durationMs < 2000) isRushed = true; 
        }
        repMovementStartTime = null; 
        
        if (isRushed) {
          badRep = true;
          repFeedback = "Too fast! Control the eccentric.";
          // INJECTION: Store audio instructions for the UI to handle
          audioCuePayload ??= ["Slow down on the way down.", "Don't drop the weight.", "Control the negative.", "Take 2-3 seconds to lower the weight.", "Focus on a slow descent.", "Maintain control as you lower the dumbbell.", "Avoid rushing the lowering phase for better gains.", "Eccentric control is key for muscle growth."];
        } 
        else if (hasFormBrokenThisRep) {
          badRep = true;
          repFeedback = "Rep invalid. Keep elbows pinned!";
        } else {
          goodRep = true;
          repFeedback = "Perfect curl!";
        }
      } else {
        if (elbowAngle <= 70.0 && _highestElbowAngle >= 100.0 && _highestElbowAngle < 140.0) {
          if (publishedFormState != -1) {
            // INJECTION: Store "Partial Rep" feedback
            audioCuePayload ??= [
              "Partial rep. Extend your arms fully.",
              "All the way down.",
              "Full range of motion.",
              "Don't stop halfway, go all the way down.",
              "Make sure to fully extend your arms at the bottom.",
              "Lower the weight until your arms are straight for a complete rep.",
              "Focus on achieving a full stretch at the bottom of the curl.",
              "Partial reps won't maximize your gains. Go all the way down."
            ];
          }
          _highestElbowAngle = 0.0; 
        }
      }
    }

    // INJECTION: Final map return with audio routing key
    return {
      'goodRepTriggered': goodRep, 'badRepTriggered': badRep,
      'formState': publishedFormState, 'feedback': publishedFormState == -1 ? publishedFormError : repFeedback,
      'activeJoints': activeJoints, 'faultyJoints': publishedFaultyJoints, 'formScore': smoothedFormScore,
      'audioCue': audioCuePayload,
    };
  }
}