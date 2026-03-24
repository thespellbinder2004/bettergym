import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class BiomechanicsEngine {
  static final BiomechanicsEngine instance = BiomechanicsEngine._internal();
  BiomechanicsEngine._internal();

  bool _isDown = false;
  bool _hasFormBrokenThisRep = false; // NEW: The Tainted Rep tracker

  void reset() {
    _isDown = false;
    _hasFormBrokenThisRep = false;
  }

  double _calculateAngle(PoseLandmark first, PoseLandmark middle, PoseLandmark last) {
    final double radians = math.atan2(last.y - middle.y, last.x - middle.x) -
        math.atan2(first.y - middle.y, first.x - middle.x);

    double degrees = (radians * 180.0 / math.pi).abs();
    if (degrees > 180.0) {
      degrees = 360.0 - degrees;
    }
    return degrees;
  }

  Map<String, dynamic> processFrame({required Pose pose, required String exerciseName}) {
    Map<String, dynamic> result = {
      'goodRepTriggered': false, // NEW
      'badRepTriggered': false,  // NEW
      'formState': 0,
      'feedback': "Position yourself in frame.",
      'activeJoints': <PoseLandmarkType>{},
      'faultyJoints': <PoseLandmarkType>{}, 
      'formScore': 1.0,                     
    };

    switch (exerciseName.toLowerCase()) {
      case 'pushup':
      case 'pushups':
      case 'push ups':
        result = _evaluatePushUp(pose);
        break;
      case 'bicep curl':
      case 'bicep curls':
        result = _evaluateBicepCurl(pose);
        break;
      default:
        result['feedback'] = "Tracking not available for $exerciseName.";
    }
    return result;
  }

  Map<String, dynamic> _evaluatePushUp(Pose pose) {
    final landmarks = pose.landmarks;
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];

    if (leftShoulder == null || rightShoulder == null) {
      return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Full body not visible.", 'activeJoints': <PoseLandmarkType>{}, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0};
    }

    final bool isLeftVisible = leftShoulder.likelihood > rightShoulder.likelihood;

    final shoulder = isLeftVisible ? landmarks[PoseLandmarkType.leftShoulder] : landmarks[PoseLandmarkType.rightShoulder];
    final elbow = isLeftVisible ? landmarks[PoseLandmarkType.leftElbow] : landmarks[PoseLandmarkType.rightElbow];
    final wrist = isLeftVisible ? landmarks[PoseLandmarkType.leftWrist] : landmarks[PoseLandmarkType.rightWrist];
    final hip = isLeftVisible ? landmarks[PoseLandmarkType.leftHip] : landmarks[PoseLandmarkType.rightHip];
    final knee = isLeftVisible ? landmarks[PoseLandmarkType.leftKnee] : landmarks[PoseLandmarkType.rightKnee]; // NEW
    final ankle = isLeftVisible ? landmarks[PoseLandmarkType.leftAnkle] : landmarks[PoseLandmarkType.rightAnkle];

    final activeJoints = <PoseLandmarkType>{
      PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist,
      PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
      PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle,
    };

    if (shoulder == null || elbow == null || wrist == null || hip == null || knee == null || ankle == null ||
        shoulder.likelihood < 0.5 || hip.likelihood < 0.5 || knee.likelihood < 0.5 || ankle.likelihood < 0.5) {
      return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Align side profile to camera.", 'activeJoints': activeJoints, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0};
    }

    // 1. The 4-Point Kinetic Chain
    final hipHingeAngle = _calculateAngle(shoulder, hip, knee); // Checks sagging/piking
    final kneeFlexionAngle = _calculateAngle(hip, knee, ankle); // Checks bent knees
    final elbowAngle = _calculateAngle(shoulder, elbow, wrist); // Checks depth
    final shoulderAngle = _calculateAngle(hip, shoulder, elbow); // Checks hand placement

    // 2. Strict Continuous Math (The Thermometer)
    // 175+ is perfect (1.0). 155 is failing (0.0).
    double coreScore = ((hipHingeAngle - 155.0) / 20.0).clamp(0.0, 1.0);
    double kneeScore = ((kneeFlexionAngle - 155.0) / 20.0).clamp(0.0, 1.0);
    double handScore = ((105.0 - shoulderAngle) / 20.0).clamp(0.0, 1.0);
    
    // The thermometer takes the absolute worst metric currently happening
    double formScore = math.min(coreScore, math.min(kneeScore, handScore));

    // 3. Strict Heuristic Enforcement & Limb Specific Coloring
    Set<PoseLandmarkType> faultyJoints = {};
    int formState = 1; 
    String feedback = "Good posture. Lower to 90 degrees.";

    if (kneeFlexionAngle < 160.0) {
      formState = -1;
      feedback = "Straighten your legs! Knees are bent.";
      // Color only the legs red
      faultyJoints.addAll([PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle, PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle]);
    } else if (hipHingeAngle < 160.0) {
      formState = -1;
      feedback = "Keep your spine rigid! Hips are sagging.";
      // Color the torso and upper legs red
      faultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee]);
    } else if (shoulderAngle > 100.0) {
      formState = -1;
      feedback = "Hands too far forward. Stack wrists under shoulders.";
      // Color the arms and torso red
      faultyJoints.addAll([PoseLandmarkType.leftHip, PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, PoseLandmarkType.rightHip, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow]);
    }

    // Taint the rep if the form broke during this frame
    if (formState == -1) {
      _hasFormBrokenThisRep = true;
    }

    // 4. Strict Rep Logic
    bool goodRep = false;
    bool badRep = false;

    if (_isDown) {
      feedback = formState == -1 ? feedback : "Push up!";
      // The Lockout
      if (elbowAngle >= 160.0) {
        _isDown = false; 
        
        if (_hasFormBrokenThisRep) {
          badRep = true; // Rep is finished, but invalid
          feedback = "Rep invalid. Fix your form!";
        } else {
          goodRep = true; // Flawless rep
          feedback = "Perfect rep!";
        }
        _hasFormBrokenThisRep = false; // Reset the taint tracker for the next rep
      }
    } else {
      // The Descent
      if (elbowAngle <= 90.0) {
        _isDown = true; 
        feedback = formState == -1 ? feedback : "Depth reached. Push!";
      } else {
        feedback = formState == -1 ? feedback : "Lower... hit 90 degrees.";
      }
    }

    return {
      'goodRepTriggered': goodRep,
      'badRepTriggered': badRep,
      'formState': formState,
      'feedback': feedback,
      'activeJoints': activeJoints,
      'faultyJoints': faultyJoints, 
      'formScore': formScore,       
    };
  }

  Map<String, dynamic> _evaluateBicepCurl(Pose pose) {
    // [Keep your Bicep Curl logic exactly as it was, just change the return mapping at the bottom to match the new Push-up structure (goodRepTriggered/badRepTriggered) instead of repTriggered.]
    // For brevity, I'll provide the updated return block for the bicep curl here:
    // ... [bicep math] ...
    
    // (Bicep Form Enforcement)
    // if (shoulderSwingAngle > 35.0) {
    //   formState = -1;
    //   _hasFormBrokenThisRep = true;
    // ...
    //
    // bool goodRep = false;
    // bool badRep = false;
    // if (_isDown) { ... if (elbowAngle < 50.0) { _isDown = false; if (_hasFormBrokenThisRep) { badRep=true; } else { goodRep=true; } _hasFormBrokenThisRep = false; }
    
    return {
      'goodRepTriggered': false, // Update this when you fully build out the bicep rep logic
      'badRepTriggered': false,  // Update this when you fully build out the bicep rep logic
      'formState': 0,
      'feedback': "Bicep strict mode pending...",
      'activeJoints': <PoseLandmarkType>{},
      'faultyJoints': <PoseLandmarkType>{},
      'formScore': 1.0,
    };
  }
}