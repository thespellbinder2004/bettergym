import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class BiomechanicsEngine {
  static final BiomechanicsEngine instance = BiomechanicsEngine._internal();
  BiomechanicsEngine._internal();

  bool _isDown = false;
  bool _hasFormBrokenThisRep = false;

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
      'goodRepTriggered': false, 
      'badRepTriggered': false,  
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
    final knee = isLeftVisible ? landmarks[PoseLandmarkType.leftKnee] : landmarks[PoseLandmarkType.rightKnee]; 
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

    // --- PERSPECTIVE LOCK: Enforce Side Profile ---
    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final torsoLength = math.sqrt(math.pow(shoulder.x - hip.x, 2) + math.pow(shoulder.y - hip.y, 2));

    if (shoulderWidth > torsoLength * 0.6) {
      return {
        'goodRepTriggered': false, 
        'badRepTriggered': false, 
        'formState': 0, 
        'feedback': "Turn sideways! Front view is not supported.", 
        'activeJoints': activeJoints, 
        'faultyJoints': <PoseLandmarkType>{}, 
        'formScore': 0.0
      };
    }

    // 1. The 4-Point Kinetic Chain
    final hipHingeAngle = _calculateAngle(shoulder, hip, knee); 
    final kneeFlexionAngle = _calculateAngle(hip, knee, ankle); 
    final elbowAngle = _calculateAngle(shoulder, elbow, wrist); 
    final shoulderAngle = _calculateAngle(hip, shoulder, elbow); 

    // 2. Strict Continuous Math
    double coreScore = ((hipHingeAngle - 155.0) / 20.0).clamp(0.0, 1.0);
    double kneeScore = ((kneeFlexionAngle - 155.0) / 20.0).clamp(0.0, 1.0);
    double handScore = ((105.0 - shoulderAngle) / 20.0).clamp(0.0, 1.0);
    
    double formScore = math.min(coreScore, math.min(kneeScore, handScore));

    // 3. Strict Heuristic Enforcement & Limb Specific Coloring
    Set<PoseLandmarkType> faultyJoints = {};
    int formState = 1; 
    String feedback = "Good posture. Lower to 90 degrees.";

    if (kneeFlexionAngle < 160.0) {
      formState = -1;
      feedback = "Straighten your legs! Knees are bent.";
      faultyJoints.addAll([PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle, PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle]);
    } else if (hipHingeAngle < 160.0) {
      formState = -1;
      feedback = "Keep your spine rigid! Hips are sagging.";
      faultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee]);
    } else if (shoulderAngle > 100.0) {
      formState = -1;
      feedback = "Hands too far forward. Stack wrists under shoulders.";
      faultyJoints.addAll([PoseLandmarkType.leftHip, PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, PoseLandmarkType.rightHip, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow]);
    }

    if (formState == -1) {
      _hasFormBrokenThisRep = true;
    }

    // 4. Strict Rep Logic
    bool goodRep = false;
    bool badRep = false;

    if (_isDown) {
      feedback = formState == -1 ? feedback : "Push up!";
      if (elbowAngle >= 160.0) {
        _isDown = false; 
        
        if (_hasFormBrokenThisRep) {
          badRep = true; 
          feedback = "Rep invalid. Fix your form!";
        } else {
          goodRep = true; 
          feedback = "Perfect rep!";
        }
        _hasFormBrokenThisRep = false; 
      }
    } else {
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

    final activeJoints = <PoseLandmarkType>{
      PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist,
      PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
    };

    if (shoulder == null || elbow == null || wrist == null || hip == null || shoulder.likelihood < 0.5 || elbow.likelihood < 0.5) {
      return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Align side profile to camera.", 'activeJoints': activeJoints, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0};
    }

    // --- PERSPECTIVE LOCK: Enforce Side Profile ---
    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final torsoLength = math.sqrt(math.pow(shoulder.x - hip.x, 2) + math.pow(shoulder.y - hip.y, 2));

    if (shoulderWidth > torsoLength * 0.6) {
      return {
        'goodRepTriggered': false, 
        'badRepTriggered': false, 
        'formState': 0, 
        'feedback': "Turn sideways! Front view is not supported.", 
        'activeJoints': activeJoints, 
        'faultyJoints': <PoseLandmarkType>{}, 
        'formScore': 0.0
      };
    }

    final elbowAngle = _calculateAngle(shoulder, elbow, wrist);
    final shoulderSwingAngle = _calculateAngle(hip, shoulder, elbow);

    double formScore = ((35.0 - shoulderSwingAngle) / 20.0).clamp(0.0, 1.0);

    Set<PoseLandmarkType> faultyJoints = {};
    int formState = 1; 
    String feedback = "Good posture.";

    if (shoulderSwingAngle > 35.0) {
      formState = -1;
      feedback = "Keep elbows tucked! Stop swinging.";
      faultyJoints.addAll([PoseLandmarkType.leftHip, PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, PoseLandmarkType.rightHip, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow]);
    }

    if (formState == -1) {
      _hasFormBrokenThisRep = true;
    }

    bool goodRep = false;
    bool badRep = false;

    if (_isDown) {
      feedback = formState == -1 ? feedback : "Curl it up!";
      if (elbowAngle < 50.0) {
        _isDown = false; 
        
        if (_hasFormBrokenThisRep) {
          badRep = true;
          feedback = "Rep invalid. Stop swinging!";
        } else {
          goodRep = true;
          feedback = "Good squeeze!";
        }
        _hasFormBrokenThisRep = false;
      }
    } else {
      if (elbowAngle > 150.0) {
        _isDown = true; 
        feedback = formState == -1 ? feedback : "Fully extended. Curl!";
      } else {
        feedback = formState == -1 ? feedback : "Lower the weight fully.";
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
}