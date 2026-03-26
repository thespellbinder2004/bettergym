import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../audio_service.dart';
import '../biomechanics_engine.dart';

class SquatEvaluator extends BaseEvaluator {
  double _lowestKneeAngle = 180.0;
  double _highestHipRatio = 0.0; 

  @override
  void reset() {
    super.reset();
    _lowestKneeAngle = 180.0;
    _highestHipRatio = 0.0;
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

    final activeJoints = <PoseLandmarkType>{
      PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
      PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle,
    };

    if (shoulder == null || hip == null || knee == null || ankle == null || leftAnkle == null || rightAnkle == null || leftKnee == null || rightKnee == null ||
        shoulder.likelihood < 0.5 || hip.likelihood < 0.5 || knee.likelihood < 0.5) {
      return _bailOut(activeJoints: activeJoints);
    }

    // --- 1. PERSPECTIVE DETECTOR ---
    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final torsoLength = math.sqrt(math.pow(shoulder.x - hip.x, 2) + math.pow(shoulder.y - hip.y, 2));
    final bool isFrontFacing = shoulderWidth > torsoLength * 0.45;

    // --- 2. DEPTH METRICS ---
    final kneeFlexionAngle = calculateAngle(hip, knee, ankle);
    
    // In screen coordinates, Y increases downward. 
    // Standing: Hips are roughly halfway between shoulders and knees (Ratio ~ 0.5)
    // Squatting: Hips drop down to knee level (Ratio approaches 1.0)
    final verticalDepthRatio = (hip.y - shoulder.y) / (knee.y - shoulder.y == 0 ? 0.001 : knee.y - shoulder.y);

    if (kneeFlexionAngle < _lowestKneeAngle) _lowestKneeAngle = kneeFlexionAngle;
    if (verticalDepthRatio > _highestHipRatio) _highestHipRatio = verticalDepthRatio;

    int rawFormState = 1; 
    String rawFormError = "";
    Set<PoseLandmarkType> rawFaultyJoints = {};
    List<String> ttsVariations = [];

    // --- 3. PERSPECTIVE-SPECIFIC HEURISTICS ---
    if (isFrontFacing) {
      // FRONT VIEW: Only care about knees caving in (Valgus)
      final stanceWidth = (leftAnkle.x - rightAnkle.x).abs();
      final kneeWidth = (leftKnee.x - rightKnee.x).abs();

      // If knee width drops below 70% of stance width, flag it
      if (kneeWidth < stanceWidth * 0.70 && verticalDepthRatio > 0.6) {
        rawFormState = -1;
        rawFaultyJoints.addAll([PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee]);
        if (rawFormError.isEmpty) {
          rawFormError = "Knees caving in.";
          ttsVariations = ["Push your knees out.", "Drive your knees outward."];
        }
      }
      
      double rawFormScore = ((verticalDepthRatio - 0.5) / 0.4).clamp(0.0, 1.0);
      smoothedFormScore = (smoothedFormScore * 0.8) + (rawFormScore * 0.2);

    } else {
      // SIDE VIEW: Ignore minor torso lean. Just calculate depth.
      double depthScore = ((kneeFlexionAngle - 90.0) / 60.0).clamp(0.0, 1.0);
      // Invert score so 1.0 is standing, 0.0 is deep
      double rawFormScore = 1.0 - depthScore; 
      smoothedFormScore = (smoothedFormScore * 0.8) + (rawFormScore * 0.2);
    }

    processFormState(
      rawFormState: rawFormState, 
      rawFormError: rawFormError, 
      rawFaultyJoints: rawFaultyJoints, 
      ttsVariations: ttsVariations, 
      amnesiaConditionMet: isFrontFacing ? verticalDepthRatio <= 0.6 : kneeFlexionAngle >= 150.0,
      isInstantFault: false
    );

    // --- START THE STOPWATCH ---
    if ((isFrontFacing ? verticalDepthRatio > 0.65 : kneeFlexionAngle < 140.0) && repMovementStartTime == null) {
      repMovementStartTime = DateTime.now();
    }

    // --- 4. STRICT, CORRECTED REP LOGIC ---
    bool goodRep = false;
    bool badRep = false;
    String repFeedback = "";

    // The mathematically corrected thresholds
    bool isDeepEnough = isFrontFacing ? verticalDepthRatio >= 0.85 : kneeFlexionAngle <= 100.0;
    bool isStanding = isFrontFacing ? verticalDepthRatio <= 0.60 : kneeFlexionAngle >= 150.0;

    if (isDown) { // Currently in the hole, waiting to stand UP
      repFeedback = "Stand up!";
      if (isStanding) { 
        isDown = false; 
        
        bool isRushed = false;
        if (repMovementStartTime != null) {
          final durationMs = DateTime.now().difference(repMovementStartTime!).inMilliseconds;
          if (durationMs < 1500) isRushed = true; 
        }
        repMovementStartTime = null; 
        
        if (isRushed) {
          badRep = true;
          repFeedback = "Too fast! Control the rep.";
          AudioService.instance.speakCorrection(["Slow down the descent."]);
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
    } else { // Currently standing, waiting to go DOWN
      if (isDeepEnough) { 
        isDown = true; 
        repFeedback = "Depth reached. Stand!";
      } else {
        repFeedback = "Drop lower...";
        
        // Half-Rep Detection: Returned to standing but never hit depth
        if (isStanding) {
          bool attemptedSquat = isFrontFacing ? _highestHipRatio > 0.70 : _lowestKneeAngle < 130.0;
          bool missedDepth = isFrontFacing ? _highestHipRatio < 0.85 : _lowestKneeAngle > 100.0;

          if (attemptedSquat && missedDepth) {
            if (publishedFormState != -1) {
              AudioService.instance.speakCorrection([
                "Partial rep. Break parallel.",
                "Go deeper.",
                "Drop your hips lower."
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