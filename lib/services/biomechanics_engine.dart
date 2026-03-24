import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../services/audio_service.dart';

class BiomechanicsEngine {
  static final BiomechanicsEngine instance = BiomechanicsEngine._internal();
  BiomechanicsEngine._internal();

  // --- REP & DEBOUNCE STATE ---
  bool _isDown = false;
  bool _hasFormBrokenThisRep = false;
  
  int _consecutiveBadFrames = 0;
  int _consecutiveGoodFrames = 0;
  static const int _debounceThreshold = 8; // Rock-solid symmetric debounce

  int _publishedFormState = 1;
  String _publishedFormError = "";
  Set<PoseLandmarkType> _publishedFaultyJoints = {};
  double _smoothedFormScore = 1.0; 

  void reset() {
    _isDown = false;
    _hasFormBrokenThisRep = false;
    _consecutiveBadFrames = 0;
    _consecutiveGoodFrames = 0;
    _publishedFormState = 1;
    _publishedFormError = "";
    _publishedFaultyJoints = {};
    _smoothedFormScore = 1.0;
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
      'formState': 1,
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

    // --- PERSPECTIVE LOCK ---
    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final torsoLength = math.sqrt(math.pow(shoulder.x - hip.x, 2) + math.pow(shoulder.y - hip.y, 2));

    if (shoulderWidth > torsoLength * 0.6) {
      return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Turn sideways! Front view is not supported.", 'activeJoints': activeJoints, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0};
    }

    // 1. The 4-Point Kinetic Chain
    final hipHingeAngle = _calculateAngle(shoulder, hip, knee); 
    final kneeFlexionAngle = _calculateAngle(hip, knee, ankle); 
    final elbowAngle = _calculateAngle(shoulder, elbow, wrist); 
    final shoulderAngle = _calculateAngle(hip, shoulder, elbow); 

    // 2. Thermometer Smoothing
    double coreScore = ((hipHingeAngle - 155.0) / 20.0).clamp(0.0, 1.0);
    double kneeScore = ((kneeFlexionAngle - 155.0) / 20.0).clamp(0.0, 1.0);
    double handScore = ((105.0 - shoulderAngle) / 20.0).clamp(0.0, 1.0);
    double rawFormScore = math.min(coreScore, math.min(kneeScore, handScore));
    
    _smoothedFormScore = (_smoothedFormScore * 0.8) + (rawFormScore * 0.2);

    // 3. Raw Heuristic Checks
    int rawFormState = 1; 
    String rawFormError = "";
    Set<PoseLandmarkType> rawFaultyJoints = {};

    // --- SAGGING VS PIKING MATH ---
    double expectedHipY = shoulder.y + (hip.x - shoulder.x) * ((knee.y - shoulder.y) / (knee.x - shoulder.x == 0 ? 0.001 : knee.x - shoulder.x));
    bool isSagging = hip.y > expectedHipY;

    if (kneeFlexionAngle < 160.0) {
      rawFormState = -1;
      rawFormError = "Knees bent.";
      rawFaultyJoints.addAll([PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle, PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle]);
      
      AudioService.instance.speakCorrection([
        "Knees are bent, straighten your legs.",
        "Keep your legs completely straight.",
        "Lock your knees out."
      ]);

    } else if (hipHingeAngle < 160.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee]);
      
      if (isSagging) {
        rawFormError = "Hips sagging.";
        AudioService.instance.speakCorrection([
          "Hips are dropping. Squeeze your core.",
          "Keep your back straight. Don't let your hips sag.",
          "Tighten your core. Your hips are falling."
        ]);
      } else {
        rawFormError = "Butt too high.";
        AudioService.instance.speakCorrection([
          "Lower your hips. Your butt is too high.",
          "Bring your hips down into a straight plank.",
          "Flatten your back. Hips are too high."
        ]);
      }

    } else if (shoulderAngle > 100.0) {
      rawFormState = -1;
      rawFormError = "Hands too far forward.";
      rawFaultyJoints.addAll([PoseLandmarkType.leftHip, PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, PoseLandmarkType.rightHip, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow]);
      
      AudioService.instance.speakCorrection([
        "Move your hands back. They should be under your shoulders.",
        "Your hands are too far forward. Bring them back.",
        "Stack your wrists directly under your shoulders."
      ]);
    }

    // --- THE FIXED AMNESIA PROTOCOL ---
    // Only resets the taint if you have NOT started the rep yet.
    if (elbowAngle >= 150.0 && rawFormState == 1 && !_isDown) {
      _hasFormBrokenThisRep = false; 
    }

    // --- ROCK SOLID SYMMETRIC DEBOUNCE ---
    if (rawFormState == -1) {
      _consecutiveBadFrames++;
      _consecutiveGoodFrames = 0;
      if (_consecutiveBadFrames >= _debounceThreshold) {
        _publishedFormState = -1;
        _publishedFormError = rawFormError;
        _publishedFaultyJoints = Set.from(rawFaultyJoints);
        
        // Form is officially broken, the rep is permanently tainted.
        _hasFormBrokenThisRep = true; 
      }
    } else {
      _consecutiveGoodFrames++;
      _consecutiveBadFrames = 0;
      if (_consecutiveGoodFrames >= _debounceThreshold) {
        _publishedFormState = 1;
        _publishedFormError = "";
        _publishedFaultyJoints = {};
      }
    }

    // 4. Strict Rep Logic
    bool goodRep = false;
    bool badRep = false;
    String repFeedback = "";

    if (_isDown) {
      repFeedback = "Push up!";
      if (elbowAngle >= 160.0) {
        _isDown = false; 
        if (_hasFormBrokenThisRep) {
          badRep = true; 
          repFeedback = "Rep invalid. Fix your form!";
        } else {
          goodRep = true; 
          repFeedback = "Perfect rep!";
        }
        _hasFormBrokenThisRep = false; 
      }
    } else {
      if (elbowAngle <= 90.0) {
        _isDown = true; 
        repFeedback = "Depth reached. Push!";
      } else {
        repFeedback = "Lower... hit 90 degrees.";
      }
    }

    String finalFeedback = _publishedFormState == -1 ? _publishedFormError : repFeedback;

    return {
      'goodRepTriggered': goodRep,
      'badRepTriggered': badRep,
      'formState': _publishedFormState,
      'feedback': finalFeedback,
      'activeJoints': activeJoints,
      'faultyJoints': _publishedFaultyJoints, 
      'formScore': _smoothedFormScore,       
    };
  }

  Map<String, dynamic> _evaluateBicepCurl(Pose pose) {
    // Keep exact same implementation as the Push-up rollback above, simplified for brevity here
    final landmarks = pose.landmarks;
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];

    if (leftShoulder == null || rightShoulder == null) return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Full body not visible.", 'activeJoints': <PoseLandmarkType>{}, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0};

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

    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final torsoLength = math.sqrt(math.pow(shoulder.x - hip.x, 2) + math.pow(shoulder.y - hip.y, 2));

    if (shoulderWidth > torsoLength * 0.6) {
      return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Turn sideways! Front view is not supported.", 'activeJoints': activeJoints, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0};
    }

    final elbowAngle = _calculateAngle(shoulder, elbow, wrist);
    final shoulderSwingAngle = _calculateAngle(hip, shoulder, elbow);

    double rawFormScore = ((35.0 - shoulderSwingAngle) / 20.0).clamp(0.0, 1.0);
    _smoothedFormScore = (_smoothedFormScore * 0.8) + (rawFormScore * 0.2);

    int rawFormState = 1; 
    String rawFormError = "";
    Set<PoseLandmarkType> rawFaultyJoints = {};

    if (shoulderSwingAngle > 35.0) {
      rawFormState = -1;
      rawFormError = "Keep elbows tucked! Stop swinging.";
      rawFaultyJoints.addAll([PoseLandmarkType.leftHip, PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, PoseLandmarkType.rightHip, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow]);
      
      AudioService.instance.speakCorrection([
        "Keep elbows tucked! Stop swinging.",
        "Lock your elbows to your side.",
        "Don't swing the weight."
      ]);
    }

    if (elbowAngle >= 150.0 && rawFormState == 1 && !_isDown) {
      _hasFormBrokenThisRep = false; 
    }

    if (rawFormState == -1) {
      _consecutiveBadFrames++;
      _consecutiveGoodFrames = 0;
      if (_consecutiveBadFrames >= _debounceThreshold) {
        _publishedFormState = -1;
        _publishedFormError = rawFormError;
        _publishedFaultyJoints = Set.from(rawFaultyJoints);
        _hasFormBrokenThisRep = true; 
      }
    } else {
      _consecutiveGoodFrames++;
      _consecutiveBadFrames = 0;
      if (_consecutiveGoodFrames >= _debounceThreshold) {
        _publishedFormState = 1;
        _publishedFormError = "";
        _publishedFaultyJoints = {};
      }
    }

    bool goodRep = false;
    bool badRep = false;
    String repFeedback = "";

    if (_isDown) {
      repFeedback = "Curl it up!";
      if (elbowAngle < 50.0) {
        _isDown = false; 
        if (_hasFormBrokenThisRep) {
          badRep = true;
          repFeedback = "Rep invalid. Stop swinging!";
        } else {
          goodRep = true;
          repFeedback = "Good squeeze!";
        }
        _hasFormBrokenThisRep = false;
      }
    } else {
      if (elbowAngle > 150.0) {
        _isDown = true; 
        repFeedback = "Fully extended. Curl!";
      } else {
        repFeedback = "Lower the weight fully.";
      }
    }

    String finalFeedback = _publishedFormState == -1 ? _publishedFormError : repFeedback;

    return {
      'goodRepTriggered': goodRep,
      'badRepTriggered': badRep,
      'formState': _publishedFormState,
      'feedback': finalFeedback,
      'activeJoints': activeJoints,
      'faultyJoints': _publishedFaultyJoints,
      'formScore': _smoothedFormScore,
    };
  }
}