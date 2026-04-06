import 'dart:math' as math;
import 'dart:ui';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
// AUDIO SERVICE IMPORT DELETED
import '../biomechanics_engine.dart';

class LungeEvaluator extends BaseEvaluator {
  double _lowestKneeAngle = 180.0;

  @override
  void reset() {
    super.reset();
    _lowestKneeAngle = 180.0;
  }

  @override
  Map<String, dynamic> evaluate(Pose pose) {
    final landmarks = pose.landmarks;
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];

    // INJECTION: Added 'audioCue': null to handle early exits
    if (leftShoulder == null || rightShoulder == null) return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Full body not visible.", 'activeJoints': <PoseLandmarkType>{}, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0, 'audioCue': null};

    final bool isLeftVisible = leftShoulder.likelihood > rightShoulder.likelihood;
    
    final shoulder = isLeftVisible ? landmarks[PoseLandmarkType.leftShoulder] : landmarks[PoseLandmarkType.rightShoulder];
    final hip = isLeftVisible ? landmarks[PoseLandmarkType.leftHip] : landmarks[PoseLandmarkType.rightHip];
    final nose = landmarks[PoseLandmarkType.nose];
    
    final leftAnkle = landmarks[PoseLandmarkType.leftAnkle];
    final rightAnkle = landmarks[PoseLandmarkType.rightAnkle];
    final leftKnee = landmarks[PoseLandmarkType.leftKnee];
    final rightKnee = landmarks[PoseLandmarkType.rightKnee];

    final activeJoints = <PoseLandmarkType>{
      PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
      PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle,
      PoseLandmarkType.nose,
    };

    // INJECTION: Added 'audioCue': null to handle early exits
    if (shoulder == null || hip == null || leftAnkle == null || rightAnkle == null || leftKnee == null || rightKnee == null || nose == null ||
        shoulder.likelihood < 0.5 || hip.likelihood < 0.5 || leftAnkle.likelihood < 0.5 || rightAnkle.likelihood < 0.5) {
      return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Align side profile to camera.", 'activeJoints': activeJoints, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0, 'audioCue': null};
    }

    // --- 1. DYNAMIC LEG IDENTIFICATION ---
    bool facingRight = nose.x > shoulder.x;
    bool isLeftFront = facingRight ? (leftAnkle.x > rightAnkle.x) : (leftAnkle.x < rightAnkle.x);

    final frontAnkle = isLeftFront ? leftAnkle : rightAnkle;
    final backAnkle = isLeftFront ? rightAnkle : leftAnkle;
    final frontKnee = isLeftFront ? leftKnee : rightKnee;
    final backKnee = isLeftFront ? rightKnee : leftKnee;

    // --- 2. MATH & GEOMETRY ---
    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final torsoLength = math.sqrt(math.pow(shoulder.x - hip.x, 2) + math.pow(shoulder.y - hip.y, 2));
    final stepLength = (frontAnkle.x - backAnkle.x).abs(); 
    
    final frontKneeFlexion = calculateAngle(hip, frontKnee, frontAnkle);
    if (frontKneeFlexion < _lowestKneeAngle) _lowestKneeAngle = frontKneeFlexion;

    final torsoDx = shoulder.x - hip.x;
    final leanAngle = math.atan2(torsoDx.abs(), (shoulder.y - hip.y).abs()) * 180 / math.pi;
    bool leaningForward = facingRight ? torsoDx > 0 : torsoDx < 0;

    final backShinLength = math.sqrt(math.pow(backKnee.x - backAnkle.x, 2) + math.pow(backKnee.y - backAnkle.y, 2));

    double coreScore = ((25.0 - leanAngle) / 15.0).clamp(0.0, 1.0);
    double depthScore = ((frontKneeFlexion - 100.0) / 60.0).clamp(0.0, 1.0);
    double rawFormScore = math.min(coreScore, depthScore);
    smoothedFormScore = (smoothedFormScore * 0.8) + (rawFormScore * 0.2);

    int rawFormState = 1; 
    String rawFormError = "";
    Set<PoseLandmarkType> rawFaultyJoints = {};
    List<String> ttsVariations = [];
    bool triggerInstantKill = false;

    // --- 3. CLINICAL HEURISTICS ---

    if (shoulderWidth > torsoLength * 0.45) {
      rawFormState = -1;
      triggerInstantKill = true;
      rawFaultyJoints.addAll(activeJoints); 
      if (rawFormError.isEmpty) {
        rawFormError = "Turn sideways.";
        ttsVariations = ["Turn sideways.", "Face the side, do not look at the camera.", "Align your body perpendicular to the camera.", "Position yourself sideways to the camera.", "Rotate your body 90 degrees.", "Side profile needed for this exercise."];
      }
    }
    else if (frontKneeFlexion < 140.0 && stepLength < torsoLength * 0.70) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle]);
      if (rawFormError.isEmpty) {
        rawFormError = "Step too short.";
        ttsVariations = ["Widen your stance.", "Take a longer step.", "Your feet are too close together.", "Increase the distance between your feet.", "Don't step too short, extend your leg further."];
      }
    }
    else if (frontKneeFlexion < 130.0 && backShinLength < torsoLength * 0.35) {
      rawFormState = -1;
      triggerInstantKill = true;
      rawFaultyJoints.addAll([PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee, PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle]);
      if (rawFormError.isEmpty) {
        rawFormError = "Back knee twisting.";
        ttsVariations = ["Point your back knee straight down.", "Don't twist your back leg outward.", "Keep your back knee in line with your foot.", "Focus on proper alignment of your back leg.", "Avoid letting your back knee flare out to the side."];
      }
    }
    else if (leaningForward && leanAngle > 25.0) {
      rawFormState = -1;
      triggerInstantKill = true; 
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.rightHip]);
      if (rawFormError.isEmpty) {
        rawFormError = "Leaning forward.";
        ttsVariations = ["Chest up.", "Don't lean forward.", "Straighten your back.", "Maintain an upright torso.", "Focus on keeping your chest lifted.", "Avoid leaning forward during the lunge."];
      }
    }
    else if (!leaningForward && leanAngle > 10.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.rightHip]);
      if (rawFormError.isEmpty) {
        rawFormError = "Leaning backward.";
        ttsVariations = ["Stop leaning back.", "Keep your torso vertical."," Don't lean backward.", "Focus on keeping your torso upright.", "Maintain a neutral spine during the lunge.", "Avoid leaning back to balance."];
      }
    }

    // INJECTION: Capture the audio cue payload from the BaseEvaluator
    List<String>? audioCuePayload = processFormState(
      rawFormState: rawFormState, 
      rawFormError: rawFormError, 
      rawFaultyJoints: rawFaultyJoints, 
      ttsVariations: ttsVariations, 
      amnesiaConditionMet: frontKneeFlexion >= 160.0, 
      isInstantFault: triggerInstantKill
    );

    // --- START THE STOPWATCH ---
    if (frontKneeFlexion < 150.0 && repMovementStartTime == null) {
      repMovementStartTime = DateTime.now();
    }

    // --- 4. STRICT REP LOGIC ---
    bool goodRep = false;
    bool badRep = false;
    String repFeedback = "";

    if (isDown) {
      repFeedback = "Push back up!";
      if (frontKneeFlexion >= 160.0) { 
        isDown = false; 
        
        bool isRushed = false;
        if (repMovementStartTime != null) {
          final durationMs = DateTime.now().difference(repMovementStartTime!).inMilliseconds;
          if (durationMs < 2000) isRushed = true; 
        }
        repMovementStartTime = null; 
        
        if (isRushed) {
          badRep = true;
          repFeedback = "Too fast! Control the descent.";
          // INJECTION: Store audio instructions for the UI
          audioCuePayload ??= ["Slow down your lunge.", "Don't rush.", "Control the movement."," Focus on a steady pace.", "Take your time with each rep.", "Maintain control throughout the lunge.", "Avoid rushing to maximize effectiveness.", "A controlled lunge is a safe lunge."];
        } else if (hasFormBrokenThisRep) {
          badRep = true;
          repFeedback = "Rep invalid. Watch form!";
        } else {
          goodRep = true;
          repFeedback = "Great lunge!";
        }
        _lowestKneeAngle = 180.0; 
      }
    } else {
      if (frontKneeFlexion <= 95.0) { 
        isDown = true; 
        repFeedback = "Depth reached. Push up!";
      } else {
        repFeedback = "Drop lower...";
        
        if (frontKneeFlexion >= 160.0 && _lowestKneeAngle <= 120.0 && _lowestKneeAngle > 95.0) {
          if (publishedFormState != -1) {
            // INJECTION: Store "Partial Rep" feedback
            audioCuePayload ??= [
              "Partial repetition. Drop your back knee lower.",
              "Go deeper on the lunge.",
              "Back knee toward the floor.",
              "Aim to get your back knee closer to the ground.",
              "Focus on achieving a deeper lunge for full reps.",
              "Don't stop too high, go deeper for full benefits.",
              "Make sure to lower yourself until your back knee is close to the floor for a complete rep."
            ];
          }
          _lowestKneeAngle = 180.0; 
        }
      }
    }

    // INJECTION: Final map return with the audio routing key
    return {
      'goodRepTriggered': goodRep, 'badRepTriggered': badRep,
      'formState': publishedFormState, 'feedback': publishedFormState == -1 ? publishedFormError : repFeedback,
      'activeJoints': activeJoints, 'faultyJoints': publishedFaultyJoints, 'formScore': smoothedFormScore,
      'audioCue': audioCuePayload, // PIPELINE COMPLETED
    };
  }
}