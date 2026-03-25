import 'dart:math' as math;
import 'dart:ui';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../audio_service.dart';
import '../biomechanics_engine.dart';

class SquatEvaluator extends BaseEvaluator {
  double _lowestKneeAngle = 180.0;
  double _lowestHipRatio = 1.0; 
  
  // Foothold Anchors
  Offset? _leftAnkleAnchor;
  Offset? _rightAnkleAnchor;

  @override
  void reset() {
    super.reset();
    _lowestKneeAngle = 180.0;
    _lowestHipRatio = 1.0;
    _leftAnkleAnchor = null;
    _rightAnkleAnchor = null;
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
    
    final leftAnkle = landmarks[PoseLandmarkType.leftAnkle];
    final rightAnkle = landmarks[PoseLandmarkType.rightAnkle];
    final leftKnee = landmarks[PoseLandmarkType.leftKnee];
    final rightKnee = landmarks[PoseLandmarkType.rightKnee];
    final nose = landmarks[PoseLandmarkType.nose];

    final activeJoints = <PoseLandmarkType>{
      PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
      PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle,
      PoseLandmarkType.nose,
    };

    if (shoulder == null || hip == null || knee == null || ankle == null || leftAnkle == null || rightAnkle == null || leftKnee == null || rightKnee == null || nose == null ||
        shoulder.likelihood < 0.5 || hip.likelihood < 0.5 || knee.likelihood < 0.5) {
      return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Align body to camera.", 'activeJoints': activeJoints, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0};
    }

    // --- 1. PERSPECTIVE DETECTOR ---
    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final torsoLength = math.sqrt(math.pow(shoulder.x - hip.x, 2) + math.pow(shoulder.y - hip.y, 2));
    final bool isFrontFacing = shoulderWidth > torsoLength * 0.45;

    // --- 2. UNIVERSAL MATH & ANCHORS ---
    final kneeFlexionAngle = calculateAngle(hip, knee, ankle);
    final neckAngle = calculateAngle(hip, shoulder, nose); // Tracks neck extension/tucking
    
    // Y-Axis depth ratio for front-facing squats (0.0 = hips are at knee level)
    final verticalDepthRatio = (hip.y - shoulder.y) / (knee.y - shoulder.y == 0 ? 0.001 : knee.y - shoulder.y);

    if (kneeFlexionAngle < _lowestKneeAngle) _lowestKneeAngle = kneeFlexionAngle;
    if (verticalDepthRatio < _lowestHipRatio) _lowestHipRatio = verticalDepthRatio;

    // Anchor the feet when standing
    if (!isDown && (isFrontFacing ? verticalDepthRatio > 0.8 : kneeFlexionAngle > 160.0)) {
      _leftAnkleAnchor = Offset(leftAnkle.x, leftAnkle.y);
      _rightAnkleAnchor = Offset(rightAnkle.x, rightAnkle.y);
    }

    // Check Foothold Jitter/Lift
    bool footholdBroken = false;
    if (_leftAnkleAnchor != null && _rightAnkleAnchor != null) {
      final leftShift = math.sqrt(math.pow(leftAnkle.x - _leftAnkleAnchor!.dx, 2) + math.pow(leftAnkle.y - _leftAnkleAnchor!.dy, 2));
      final rightShift = math.sqrt(math.pow(rightAnkle.x - _rightAnkleAnchor!.dx, 2) + math.pow(rightAnkle.y - _rightAnkleAnchor!.dy, 2));
      // If either foot moves more than 15% of torso length (filters out camera noise but catches steps/lifts)
      if (leftShift > torsoLength * 0.15 || rightShift > torsoLength * 0.15) {
        footholdBroken = true;
      }
    }

    int rawFormState = 1; 
    String rawFormError = "";
    Set<PoseLandmarkType> rawFaultyJoints = {};
    List<String> ttsVariations = [];
    bool triggerInstantKill = false;

    // --- 3. UNIVERSAL HEURISTICS ---
    if (footholdBroken) {
      rawFormState = -1;
      triggerInstantKill = true; 
      rawFaultyJoints.addAll([PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle]);
      if (rawFormError.isEmpty) {
        rawFormError = "Foot moved.";
        ttsVariations = ["Keep your feet planted.", "Don't lift your heels or step.", "Feet flat on the floor."];
      }
    } else if (neckAngle < 150.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.nose, PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder]);
      if (rawFormError.isEmpty) {
        rawFormError = "Gaze dropping.";
        ttsVariations = ["Keep your gaze forward.", "Don't tuck your chin.", "Look straight ahead."];
      }
    }

    // --- 4. PERSPECTIVE-SPECIFIC HEURISTICS ---
    if (isFrontFacing) {
      // CORONAL ENGINE (Front)
      final stanceWidth = (leftAnkle.x - rightAnkle.x).abs();
      final kneeWidth = (leftKnee.x - rightKnee.x).abs();
      final midHipX = (landmarks[PoseLandmarkType.leftHip]!.x + landmarks[PoseLandmarkType.rightHip]!.x) / 2;
      final midAnkleX = (leftAnkle.x + rightAnkle.x) / 2;
      final lateralShift = (midHipX - midAnkleX).abs();

      if (kneeWidth < stanceWidth * 0.75) {
        rawFormState = -1;
        rawFaultyJoints.addAll([PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee]);
        if (rawFormError.isEmpty) {
          rawFormError = "Knees caving in.";
          ttsVariations = ["Push your knees out.", "Don't let your knees collapse inward."];
        }
      } else if (lateralShift > torsoLength * 0.15) {
        rawFormState = -1;
        rawFaultyJoints.addAll([PoseLandmarkType.leftHip, PoseLandmarkType.rightHip]);
        if (rawFormError.isEmpty) {
          rawFormError = "Body shifting.";
          ttsVariations = ["Keep your weight centered.", "Don't shift to one side."];
        }
      }
      
      double rawFormScore = ((verticalDepthRatio - 0.5) / 0.5).clamp(0.0, 1.0);
      smoothedFormScore = (smoothedFormScore * 0.8) + (rawFormScore * 0.2);

    } else {
      // SAGITTAL ENGINE (Side)
      final trunkAngle = math.atan2((shoulder.x - hip.x).abs(), (shoulder.y - hip.y).abs()) * 180 / math.pi;
      final tibiaAngle = math.atan2((knee.x - ankle.x).abs(), (knee.y - ankle.y).abs()) * 180 / math.pi;
      final torsoCollapseDifferential = trunkAngle - tibiaAngle;

      if (torsoCollapseDifferential > 20.0) {
        rawFormState = -1;
        rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.rightHip]);
        if (rawFormError.isEmpty) {
          rawFormError = "Chest falling.";
          ttsVariations = ["Chest up. Don't round your back.", "Keep your torso parallel to your shins."];
        }
      }
      
      double depthScore = ((kneeFlexionAngle - 90.0) / 60.0).clamp(0.0, 1.0);
      smoothedFormScore = (smoothedFormScore * 0.8) + (depthScore * 0.2);
    }

    processFormState(
      rawFormState: rawFormState, 
      rawFormError: rawFormError, 
      rawFaultyJoints: rawFaultyJoints, 
      ttsVariations: ttsVariations, 
      amnesiaConditionMet: isFrontFacing ? verticalDepthRatio >= 0.8 : kneeFlexionAngle >= 160.0,
      isInstantFault: triggerInstantKill
    );

    // --- START THE STOPWATCH ---
    if ((isFrontFacing ? verticalDepthRatio < 0.75 : kneeFlexionAngle < 150.0) && repMovementStartTime == null) {
      repMovementStartTime = DateTime.now();
    }

    // --- STRICT REP LOGIC ---
    bool goodRep = false;
    bool badRep = false;
    String repFeedback = "";

    bool isDeepEnough = isFrontFacing ? verticalDepthRatio <= 0.5 : kneeFlexionAngle <= 90.0;
    bool isStanding = isFrontFacing ? verticalDepthRatio >= 0.8 : kneeFlexionAngle >= 160.0;

    if (isDown) {
      repFeedback = "Stand up!";
      if (isStanding) { 
        isDown = false; 
        
        bool isRushed = false;
        if (repMovementStartTime != null) {
          final durationMs = DateTime.now().difference(repMovementStartTime!).inMilliseconds;
          if (durationMs < 2000) isRushed = true; // Strict 2-second TUT
        }
        repMovementStartTime = null; 
        
        if (isRushed) {
          badRep = true;
          repFeedback = "Too fast! Control the rep.";
          AudioService.instance.speakCorrection(["Slow down the descent.", "Don't rush. Time under tension."]);
        } else if (hasFormBrokenThisRep) {
          badRep = true;
          repFeedback = "Rep invalid. Watch form!";
        } else {
          goodRep = true;
          repFeedback = "Great depth!";
        }
        _lowestKneeAngle = 180.0; 
        _lowestHipRatio = 1.0;
      }
    } else {
      if (isDeepEnough) { 
        isDown = true; 
        repFeedback = "Depth reached. Stand!";
      } else {
        repFeedback = "Drop lower...";
        
        // Half-Rep Detection
        if (isStanding && (isFrontFacing ? _lowestHipRatio > 0.6 : _lowestKneeAngle > 110.0)) {
          AudioService.instance.speakCorrection([
            "Half rep. Break parallel.",
            "Go deeper.",
            "Drop your hips lower."
          ]);
          _lowestKneeAngle = 180.0; 
          _lowestHipRatio = 1.0;
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