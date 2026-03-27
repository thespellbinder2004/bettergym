import 'dart:math' as math;
import 'dart:ui';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../audio_service.dart';
import '../biomechanics_engine.dart';

class SquatEvaluator extends BaseEvaluator {
  double _lowestKneeAngle = 180.0;   // For Side View (Lower = Deeper)
  double _highestHipRatio = 0.0;     // For Front View (Higher = Deeper)
  
  Offset? _leftAnkleAnchor;
  Offset? _rightAnkleAnchor;

  @override
  void reset() {
    super.reset();
    _lowestKneeAngle = 180.0;
    _highestHipRatio = 0.0;
    _leftAnkleAnchor = null;
    _rightAnkleAnchor = null;
  }

  @override
  Map<String, dynamic> evaluate(Pose pose) {
    final landmarks = pose.landmarks;
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];

    if (leftShoulder == null || rightShoulder == null) return _bailOut();

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
      return _bailOut(activeJoints: activeJoints);
    }

    // --- 1. PERSPECTIVE DETECTOR ---
    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final torsoLength = math.sqrt(math.pow(shoulder.x - hip.x, 2) + math.pow(shoulder.y - hip.y, 2));
    final bool isFrontFacing = shoulderWidth > torsoLength * 0.45;

    // --- 2. UNIVERSAL MATH & ANCHORS ---
    final kneeFlexionAngle = calculateAngle(hip, knee, ankle);
    final neckAngle = calculateAngle(hip, shoulder, nose); 
    
    // Squatting drops hips to knee Y-level. Ratio approaches 1.0 at parallel.
    final verticalDepthRatio = (hip.y - shoulder.y) / (knee.y - shoulder.y == 0 ? 0.001 : knee.y - shoulder.y);

    if (kneeFlexionAngle < _lowestKneeAngle) _lowestKneeAngle = kneeFlexionAngle;
    if (verticalDepthRatio > _highestHipRatio) _highestHipRatio = verticalDepthRatio;

    // Define Global Thresholds
    bool isStanding = isFrontFacing ? verticalDepthRatio <= 0.60 : kneeFlexionAngle >= 150.0;
    bool isDeepEnough = isFrontFacing ? verticalDepthRatio >= 0.85 : kneeFlexionAngle <= 95.0;

    // Anchor feet when fully standing
    if (!isDown && isStanding) {
      _leftAnkleAnchor = Offset(leftAnkle.x, leftAnkle.y);
      _rightAnkleAnchor = Offset(rightAnkle.x, rightAnkle.y);
    }

    // Foothold occlusion filtering
    bool footholdBroken = false;
    if (_leftAnkleAnchor != null && _rightAnkleAnchor != null) {
      final leftShift = math.sqrt(math.pow(leftAnkle.x - _leftAnkleAnchor!.dx, 2) + math.pow(leftAnkle.y - _leftAnkleAnchor!.dy, 2));
      final rightShift = math.sqrt(math.pow(rightAnkle.x - _rightAnkleAnchor!.dx, 2) + math.pow(rightAnkle.y - _rightAnkleAnchor!.dy, 2));
      
      if (isFrontFacing) {
        if (leftShift > torsoLength * 0.20 || rightShift > torsoLength * 0.20) footholdBroken = true;
      } else {
        final visibleShift = isLeftVisible ? leftShift : rightShift;
        if (visibleShift > torsoLength * 0.20) footholdBroken = true;
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
      rawFaultyJoints.addAll(isFrontFacing ? [PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle] : [isLeftVisible ? PoseLandmarkType.leftAnkle : PoseLandmarkType.rightAnkle]);
      if (rawFormError.isEmpty) {
        rawFormError = "Foot moved.";
        ttsVariations = ["Keep your feet planted.", "Don't step or lift your heels.", "Feet flat on the floor."];
      }
    } 
    else if (!isFrontFacing && neckAngle < 145.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.nose, PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder]);
      if (rawFormError.isEmpty) {
        rawFormError = "Gaze dropping.";
        ttsVariations = ["Keep your chest up and look forward.", "Don't stare at the floor."];
      }
    }

    // --- 4. PERSPECTIVE-SPECIFIC HEURISTICS ---
    if (isFrontFacing) {
      // CORONAL ENGINE (Front View)
      final stanceWidth = (leftAnkle.x - rightAnkle.x).abs();
      final kneeWidth = (leftKnee.x - rightKnee.x).abs();
      final midHipX = (landmarks[PoseLandmarkType.leftHip]!.x + landmarks[PoseLandmarkType.rightHip]!.x) / 2;
      final midAnkleX = (leftAnkle.x + rightAnkle.x) / 2;
      final lateralShift = (midHipX - midAnkleX).abs();

      if (kneeWidth < stanceWidth * 0.75 && verticalDepthRatio > 0.6) {
        rawFormState = -1;
        rawFaultyJoints.addAll([PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee]);
        if (rawFormError.isEmpty) {
          rawFormError = "Knees caving in.";
          ttsVariations = ["Drive your knees outward.", "Push your knees out over your toes."];
        }
      } else if (lateralShift > torsoLength * 0.15 && verticalDepthRatio > 0.6) {
        rawFormState = -1;
        rawFaultyJoints.addAll([PoseLandmarkType.leftHip, PoseLandmarkType.rightHip]);
        if (rawFormError.isEmpty) {
          rawFormError = "Body shifting.";
          ttsVariations = ["Keep your weight centered.", "Don't lean to one side."];
        }
      }
      
      double rawFormScore = ((verticalDepthRatio - 0.5) / 0.4).clamp(0.0, 1.0);
      smoothedFormScore = (smoothedFormScore * 0.8) + (rawFormScore * 0.2);

    } else {
      // SAGITTAL ENGINE (Side View)
      final trunkAngle = math.atan2((shoulder.x - hip.x).abs(), (shoulder.y - hip.y).abs()) * 180 / math.pi;
      final tibiaAngle = math.atan2((knee.x - ankle.x).abs(), (knee.y - ankle.y).abs()) * 180 / math.pi;
      final torsoCollapseDifferential = trunkAngle - tibiaAngle;

      if (torsoCollapseDifferential > 25.0) {
        rawFormState = -1;
        rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.rightHip]);
        if (rawFormError.isEmpty) {
          rawFormError = "Chest falling.";
          ttsVariations = ["Keep your chest up. Don't let your torso collapse.", "Match your back angle to your shins."];
        }
      }
      
      double depthScore = ((kneeFlexionAngle - 90.0) / 60.0).clamp(0.0, 1.0);
      smoothedFormScore = (smoothedFormScore * 0.8) + ((1.0 - depthScore) * 0.2); // Inverted for UI
    }

    processFormState(
      rawFormState: rawFormState, 
      rawFormError: rawFormError, 
      rawFaultyJoints: rawFaultyJoints, 
      ttsVariations: ttsVariations, 
      amnesiaConditionMet: isStanding,
      isInstantFault: triggerInstantKill
    );

    // --- START THE STOPWATCH ---
    if (!isStanding && repMovementStartTime == null) {
      repMovementStartTime = DateTime.now();
    }

    // --- 5. STRICT REP LOGIC ---
    bool goodRep = false;
    bool badRep = false;
    String repFeedback = "";

    if (isDown) {
      repFeedback = "Stand up!";
      if (isStanding) { 
        isDown = false; 
        
        bool isRushed = false;
        if (repMovementStartTime != null) {
          final durationMs = DateTime.now().difference(repMovementStartTime!).inMilliseconds;
          if (durationMs < 1800) isRushed = true; 
        }
        repMovementStartTime = null; 
        
        if (isRushed) {
          badRep = true;
          repFeedback = "Too fast! Control the rep.";
          AudioService.instance.speakCorrection(["Slow down the descent.", "Don't dive-bomb the squat."]);
        } else if (hasFormBrokenThisRep) {
          badRep = true;
          repFeedback = "Rep invalid. Watch form!";
        } else {
          goodRep = true;
          repFeedback = "Great squat!";
        }
        
        _lowestKneeAngle = 180.0; 
        _highestHipRatio = 0.0;
      }
    } else {
      if (isDeepEnough) { 
        isDown = true; 
        repFeedback = "Depth reached. Stand!";
      } else {
        repFeedback = "Drop lower...";
        
        // Lockout-Proof Half-Rep Detection
        if (isStanding) {
          bool attemptedSquat = isFrontFacing ? _highestHipRatio > 0.65 : _lowestKneeAngle < 135.0;
          bool missedDepth = isFrontFacing ? _highestHipRatio < 0.85 : _lowestKneeAngle > 95.0;

          if (attemptedSquat && missedDepth) {
            if (publishedFormState != -1) {
              AudioService.instance.speakCorrection([
                "Partial rep. Break parallel.",
                "Go deeper.",
                "Drop your hips to knee level."
              ]);
            }
            _lowestKneeAngle = 180.0; 
            _highestHipRatio = 0.0;
          }
        }
      }
    }

    return {
      'goodRepTriggered': goodRep, 'badRepTriggered': badRep,
      'formState': publishedFormState, 'feedback': publishedFormState == -1 ? publishedFormError : repFeedback,
      'activeJoints': activeJoints, 'faultyJoints': publishedFaultyJoints, 'formScore': smoothedFormScore,
    };
  }

  Map<String, dynamic> _bailOut({Set<PoseLandmarkType>? activeJoints}) {
    return {
      'goodRepTriggered': false, 'badRepTriggered': false, 
      'formState': 0, 'feedback': "Align body to camera.", 
      'activeJoints': activeJoints ?? <PoseLandmarkType>{}, 
      'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0
    };
  }
}