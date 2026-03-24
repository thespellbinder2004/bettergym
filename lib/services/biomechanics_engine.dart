import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class BiomechanicsEngine {
  // Singleton
  static final BiomechanicsEngine instance = BiomechanicsEngine._internal();
  BiomechanicsEngine._internal();

  // State tracking for reps
  bool _isDown = false;

  // Resets the state machine between sets
  void reset() {
    _isDown = false;
  }

  // Master Math Formula
  double _calculateAngle(PoseLandmark first, PoseLandmark middle, PoseLandmark last) {
    final double radians = math.atan2(last.y - middle.y, last.x - middle.x) -
        math.atan2(first.y - middle.y, first.x - middle.x);

    double degrees = (radians * 180.0 / math.pi).abs();
    if (degrees > 180.0) {
      degrees = 360.0 - degrees;
    }
    return degrees;
  }

  /// Evaluates the frame based on the current exercise.
  /// Returns a Map containing:
  /// - 'repTriggered': bool (true if a rep was just completed)
  /// - 'formState': int (1 for good, -1 for bad, 0 for neutral)
  /// - 'feedback': String
  /// - 'activeJoints': Set<PoseLandmarkType> (for the UI to highlight)
  Map<String, dynamic> processFrame({
    required Pose pose,
    required String exerciseName,
  }) {
    // Default fallback state
    Map<String, dynamic> result = {
      'repTriggered': false,
      'formState': 0,
      'feedback': "Position yourself in frame.",
      'activeJoints': <PoseLandmarkType>{},
    };

    switch (exerciseName.toLowerCase()) {
      case 'pushup':
      case 'pushups':
      case 'push ups':
        result = _evaluatePushUp(pose);
        break;
      // Future exercises will be plugged in here
      default:
        result['feedback'] = "Tracking not available for $exerciseName.";
    }

    return result;
  }

Map<String, dynamic> _evaluatePushUp(Pose pose) {
    final landmarks = pose.landmarks;

    // Determine which side is facing the camera
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];

    if (leftShoulder == null || rightShoulder == null) {
      return {'repTriggered': false, 'formState': 0, 'feedback': "Full body not visible.", 'activeJoints': <PoseLandmarkType>{}};
    }

    final bool isLeftVisible = leftShoulder.likelihood > rightShoulder.likelihood;

    final shoulder = isLeftVisible ? landmarks[PoseLandmarkType.leftShoulder] : landmarks[PoseLandmarkType.rightShoulder];
    final elbow = isLeftVisible ? landmarks[PoseLandmarkType.leftElbow] : landmarks[PoseLandmarkType.rightElbow];
    final wrist = isLeftVisible ? landmarks[PoseLandmarkType.leftWrist] : landmarks[PoseLandmarkType.rightWrist];
    final hip = isLeftVisible ? landmarks[PoseLandmarkType.leftHip] : landmarks[PoseLandmarkType.rightHip];
    final ankle = isLeftVisible ? landmarks[PoseLandmarkType.leftAnkle] : landmarks[PoseLandmarkType.rightAnkle];

    final activeJoints = <PoseLandmarkType>{
      PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist,
      PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
      PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle,
    };

    if (shoulder == null || elbow == null || wrist == null || hip == null || ankle == null ||
        shoulder.likelihood < 0.5 || hip.likelihood < 0.5 || ankle.likelihood < 0.5) {
      return {'repTriggered': false, 'formState': 0, 'feedback': "Align side profile to camera.", 'activeJoints': activeJoints};
    }

    // 1. Kinetic Chain Alignment (Strict 160+ degrees)
    final coreAngle = _calculateAngle(shoulder, hip, ankle);
    
    // 2. Elbow Flexion / Depth (Must hit 90 degrees or less)
    final elbowAngle = _calculateAngle(shoulder, elbow, wrist);

    // 3. Sagittal Shoulder Drift (Prevents reaching too far forward)
    final shoulderAngle = _calculateAngle(hip, shoulder, elbow);

    // --- HEURISTIC ENFORCEMENT ---

    // Check 1: The Core
    if (coreAngle < 160.0) {
      return {'repTriggered': false, 'formState': -1, 'feedback': "Keep your spine rigid! Hips are sagging or piked.", 'activeJoints': activeJoints};
    }

    // Check 2: Joint Stacking
    if (shoulderAngle > 100.0) {
      return {'repTriggered': false, 'formState': -1, 'feedback': "Hands are too far forward. Stack wrists under shoulders.", 'activeJoints': activeJoints};
    }

    // --- REP COUNTING LOGIC ---
    bool repTriggered = false;
    String feedback = "Good posture. Lower to 90 degrees.";
    int formState = 1; // Green outline

    if (_isDown) {
      feedback = "Push up!";
      if (elbowAngle >= 160.0) {
        _isDown = false; 
        repTriggered = true; // They successfully locked out
        feedback = "Perfect rep!";
      }
    } else {
      if (elbowAngle <= 90.0) {
        _isDown = true; // They successfully hit depth
        feedback = "Depth reached. Push!";
      } else {
        feedback = "Lower... hit 90 degrees.";
      }
    }

    return {
      'repTriggered': repTriggered,
      'formState': formState,
      'feedback': feedback,
      'activeJoints': activeJoints,
    };
  }
}