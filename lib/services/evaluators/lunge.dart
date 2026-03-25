import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../audio_service.dart';
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

    if (leftShoulder == null || rightShoulder == null) return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Full body not visible.", 'activeJoints': <PoseLandmarkType>{}, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0};

    final bool isLeftVisible = leftShoulder.likelihood > rightShoulder.likelihood;
    
    final shoulder = isLeftVisible ? landmarks[PoseLandmarkType.leftShoulder] : landmarks[PoseLandmarkType.rightShoulder];
    final hip = isLeftVisible ? landmarks[PoseLandmarkType.leftHip] : landmarks[PoseLandmarkType.rightHip];
    final knee = isLeftVisible ? landmarks[PoseLandmarkType.leftKnee] : landmarks[PoseLandmarkType.rightKnee];
    final ankle = isLeftVisible ? landmarks[PoseLandmarkType.leftAnkle] : landmarks[PoseLandmarkType.rightAnkle];
    
    // We need both ankles to calculate step length
    final leftAnkle = landmarks[PoseLandmarkType.leftAnkle];
    final rightAnkle = landmarks[PoseLandmarkType.rightAnkle];

    final activeJoints = <PoseLandmarkType>{
      PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
      PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle,
    };

    if (shoulder == null || hip == null || knee == null || ankle == null || leftAnkle == null || rightAnkle == null ||
        shoulder.likelihood < 0.5 || hip.likelihood < 0.5 || knee.likelihood < 0.5 || leftAnkle.likelihood < 0.5 || rightAnkle.likelihood < 0.5) {
      return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Align side profile to camera.", 'activeJoints': activeJoints, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0};
    }

    // 1. Math & Geometry
    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final torsoLength = math.sqrt(math.pow(shoulder.x - hip.x, 2) + math.pow(shoulder.y - hip.y, 2));
    final stepLength = (leftAnkle.x - rightAnkle.x).abs(); // Horizontal distance between feet

    final kneeFlexionAngle = calculateAngle(hip, knee, ankle);
    if (kneeFlexionAngle < _lowestKneeAngle) _lowestKneeAngle = kneeFlexionAngle;

    // Calculate Trunk Angle from Vertical (0 = upright, 90 = bent in half)
    final trunkDx = (shoulder.x - hip.x).abs();
    final trunkDy = (shoulder.y - hip.y).abs();
    final trunkAngle = math.atan2(trunkDx, trunkDy) * 180 / math.pi;

    // 2. Thermometer Smoothing
    double coreScore = ((35.0 - trunkAngle) / 15.0).clamp(0.0, 1.0);
    double depthScore = ((kneeFlexionAngle - 100.0) / 60.0).clamp(0.0, 1.0);
    double rawFormScore = math.min(coreScore, depthScore);
    smoothedFormScore = (smoothedFormScore * 0.8) + (rawFormScore * 0.2);

    int rawFormState = 1; 
    String rawFormError = "";
    Set<PoseLandmarkType> rawFaultyJoints = {};
    List<String> ttsVariations = [];
    bool triggerInstantKill = false;

    // 3. Clinical Heuristics
    
    // A. Perspective Lock
    if (shoulderWidth > torsoLength * 0.6) {
      rawFormState = -1;
      rawFaultyJoints.addAll(activeJoints);
      if (rawFormError.isEmpty) {
        rawFormError = "Face sideways.";
        ttsVariations = ["Turn sideways. I need to see your leg angles.", "Face sideways to the camera."];
      }
    }
    // B. The Shallow Step (Checked only when they are descending)
    else if (kneeFlexionAngle < 150.0 && stepLength < torsoLength * 0.60) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle, PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee]);
      if (rawFormError.isEmpty) {
        rawFormError = "Step is too short.";
        ttsVariations = [
          "Widen your stance.", 
          "Take a longer step.", 
          "Your feet are too close together."
        ];
      }
    }
    // C. Torso Collapse (Instant Kill to protect lower back)
    else if (trunkAngle > 35.0) {
      rawFormState = -1;
      triggerInstantKill = true; 
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.rightHip]);
      if (rawFormError.isEmpty) {
        rawFormError = "Chest is falling.";
        ttsVariations = [
          "Keep your chest up.", 
          "Don't fold forward.", 
          "Keep your torso vertical."
        ];
      }
    }

    processFormState(
      rawFormState: rawFormState, 
      rawFormError: rawFormError, 
      rawFaultyJoints: rawFaultyJoints, 
      ttsVariations: ttsVariations, 
      amnesiaConditionMet: kneeFlexionAngle >= 160.0, // Standing up tall = resting state
      isInstantFault: triggerInstantKill
    );

    // --- START THE STOPWATCH ---
    if (kneeFlexionAngle < 150.0 && repMovementStartTime == null) {
      repMovementStartTime = DateTime.now();
    }

    // 5. Strict Rep Logic
    bool goodRep = false;
    bool badRep = false;
    String repFeedback = "";

    if (isDown) {
      repFeedback = "Push back up!";
      if (kneeFlexionAngle >= 160.0) { 
        isDown = false; 
        
        // CHECK THE SPEED LIMIT (1.5s)
        bool isRushed = false;
        if (repMovementStartTime != null) {
          final durationMs = DateTime.now().difference(repMovementStartTime!).inMilliseconds;
          if (durationMs < 1500) isRushed = true; 
        }
        repMovementStartTime = null; 
        
        if (isRushed) {
          badRep = true;
          repFeedback = "Too fast! Control the descent.";
          AudioService.instance.speakCorrection(["Slow down your lunge.", "Don't rush."]);
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
      if (kneeFlexionAngle <= 100.0) { // 100 degrees ensures solid depth without banging the back knee
        isDown = true; 
        repFeedback = "Depth reached. Push up!";
      } else {
        repFeedback = "Drop lower...";
        
        // Half-Rep Detection
        if (kneeFlexionAngle > 150.0 && _lowestKneeAngle < 130.0) {
          AudioService.instance.speakCorrection([
            "Half rep. Drop your back knee lower.",
            "Go deeper on the lunge.",
            "Drop your hips down."
          ]);
          _lowestKneeAngle = 180.0; 
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