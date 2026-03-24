import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'audio_service.dart';

import 'evaluators/push_up.dart';
import 'evaluators/bench_dip.dart';
import 'evaluators/bicep_curl.dart';

// --- THE BASE CLASS (Shared Logic for ALL Exercises) ---
abstract class BaseEvaluator {
  bool isDown = false;
  bool hasFormBrokenThisRep = false;
  double lowestElbowAngle = 180.0; 
  
  int consecutiveBadFrames = 0;
  int consecutiveGoodFrames = 0;
  static const int debounceThreshold = 5; 

  int publishedFormState = 1;
  String publishedFormError = "";
  Set<PoseLandmarkType> publishedFaultyJoints = {};
  double smoothedFormScore = 1.0; 

  void reset() {
    isDown = false;
    hasFormBrokenThisRep = false;
    lowestElbowAngle = 180.0;
    consecutiveBadFrames = 0;
    consecutiveGoodFrames = 0;
    publishedFormState = 1;
    publishedFormError = "";
    publishedFaultyJoints = {};
    smoothedFormScore = 1.0;
  }

  double calculateAngle(PoseLandmark first, PoseLandmark middle, PoseLandmark last) {
    final double radians = math.atan2(last.y - middle.y, last.x - middle.x) -
        math.atan2(first.y - middle.y, first.x - middle.x);

    double degrees = (radians * 180.0 / math.pi).abs();
    if (degrees > 180.0) degrees = 360.0 - degrees;
    return degrees;
  }

  void processFormState({
    required int rawFormState,
    required String rawFormError,
    required Set<PoseLandmarkType> rawFaultyJoints,
    required List<String> ttsVariations,
    required bool amnesiaConditionMet, 
  }) {
    if (amnesiaConditionMet && rawFormState == 1 && !isDown) {
      hasFormBrokenThisRep = false; 
    }

    if (rawFormState == -1) {
      consecutiveBadFrames++;
      consecutiveGoodFrames = 0;
      if (consecutiveBadFrames >= debounceThreshold) {
        publishedFormState = -1;
        publishedFormError = rawFormError;
        publishedFaultyJoints = Set.from(rawFaultyJoints);
        
        if (ttsVariations.isNotEmpty) AudioService.instance.speakCorrection(ttsVariations);
        hasFormBrokenThisRep = true; 
      }
    } else {
      consecutiveGoodFrames++;
      consecutiveBadFrames = 0;
      if (consecutiveGoodFrames >= debounceThreshold) {
        publishedFormState = 1;
        publishedFormError = "";
        publishedFaultyJoints = {};
      }
    }
  }

  // Every specific exercise file MUST implement this method
  Map<String, dynamic> evaluate(Pose pose);
}

// --- THE ROUTER ---
class BiomechanicsEngine {
  static final BiomechanicsEngine instance = BiomechanicsEngine._internal();
  BiomechanicsEngine._internal();

  BaseEvaluator? _currentEvaluator;
  String _currentExerciseName = "";

  void reset() {
    _currentEvaluator?.reset();
  }

  Map<String, dynamic> processFrame({required Pose pose, required String exerciseName}) {
    // If the exercise changed, load the correct evaluator file
    if (_currentExerciseName != exerciseName || _currentEvaluator == null) {
      _currentExerciseName = exerciseName;
      _currentEvaluator = _getEvaluator(exerciseName);
    }

    if (_currentEvaluator == null) {
      return {
        'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 1,
        'feedback': "Tracking not available for $exerciseName.",
        'activeJoints': <PoseLandmarkType>{}, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 1.0 
      };
    }

    return _currentEvaluator!.evaluate(pose);
  }

  BaseEvaluator? _getEvaluator(String name) {
    switch (name.toLowerCase()) {
      case 'pushup': case 'pushups': case 'push ups': return PushUpEvaluator();
      case 'bench dip': case 'bench dips': case 'dips': return BenchDipEvaluator();
      case 'bicep curl': case 'bicep curls': return BicepCurlEvaluator();
      default: return null;
    }
  }
}