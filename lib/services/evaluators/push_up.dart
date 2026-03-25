import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../audio_service.dart';
import '../biomechanics_engine.dart';

class PushUpEvaluator extends BaseEvaluator {
  @override
  Map<String, dynamic> evaluate(Pose pose) {
    final landmarks = pose.landmarks;
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];

    if (leftShoulder == null || rightShoulder == null) return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Full body not visible.", 'activeJoints': <PoseLandmarkType>{}, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0};

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

    final hipHingeAngle = calculateAngle(shoulder, hip, knee); 
    final kneeFlexionAngle = calculateAngle(hip, knee, ankle); 
    final elbowAngle = calculateAngle(shoulder, elbow, wrist); 
    final shoulderAngle = calculateAngle(hip, shoulder, elbow); 

    if (elbowAngle < lowestElbowAngle) lowestElbowAngle = elbowAngle;

    double coreScore = ((hipHingeAngle - 155.0) / 20.0).clamp(0.0, 1.0);
    double kneeScore = ((kneeFlexionAngle - 155.0) / 20.0).clamp(0.0, 1.0);
    double handScore = ((100.0 - shoulderAngle) / 20.0).clamp(0.0, 1.0);
    double rawFormScore = math.min(coreScore, math.min(kneeScore, handScore));
    smoothedFormScore = (smoothedFormScore * 0.8) + (rawFormScore * 0.2);

    int rawFormState = 1; 
    String rawFormError = "";
    Set<PoseLandmarkType> rawFaultyJoints = {};
    List<String> ttsVariations = [];

    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final torsoLength = math.sqrt(math.pow(shoulder.x - hip.x, 2) + math.pow(shoulder.y - hip.y, 2));
    double expectedHipY = shoulder.y + (hip.x - shoulder.x) * ((knee.y - shoulder.y) / (knee.x - shoulder.x == 0 ? 0.001 : knee.x - shoulder.x));
    bool isSagging = hip.y > expectedHipY;

    if (shoulderWidth > torsoLength * 0.55) {
      rawFormState = -1;
      rawFaultyJoints.addAll(activeJoints); 
      if (rawFormError.isEmpty) {
        rawFormError = "Turn sideways.";
        ttsVariations = ["Turn sideways. Front view is not supported.", "Please face sideways to the camera."];
      }
    } else if (kneeFlexionAngle < 160.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle, PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle]);
      if (rawFormError.isEmpty) {
        rawFormError = "Knees bent.";
        ttsVariations = ["Knees are bent, straighten your legs.", "Keep your legs completely straight.", "Lock your knees out."];
      }
    } else if (hipHingeAngle < 165.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee]);
      if (rawFormError.isEmpty) {
        if (isSagging) {
          rawFormError = "Hips sagging.";
          ttsVariations = ["Hips are dropping. Squeeze your core.", "Keep your back straight. Don't let your hips sag.", "Tighten your core."];
        } else {
          rawFormError = "Butt too high.";
          ttsVariations = ["Lower your hips. Your butt is too high.", "Bring your hips down into a straight plank.", "Flatten your back."];
        }
      }
    } else if (shoulderAngle > 90.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftHip, PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, PoseLandmarkType.rightHip, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow]);
      if (rawFormError.isEmpty) {
        rawFormError = "Hands too far forward.";
        ttsVariations = ["Move your hands back. Stack them under your shoulders.", "Your hands are too far forward.", "Stack your wrists directly under your shoulders."];
      }
    }

    processFormState(
      rawFormState: rawFormState, rawFormError: rawFormError, 
      rawFaultyJoints: rawFaultyJoints, ttsVariations: ttsVariations, 
      amnesiaConditionMet: elbowAngle >= 140.0 
    );

    // --- START THE STOPWATCH ---
    if (elbowAngle < 140.0 && repMovementStartTime == null) {
      repMovementStartTime = DateTime.now();
    }

    bool goodRep = false;
    bool badRep = false;
    String repFeedback = "";

    if (isDown) {
      repFeedback = "Push up!";
      if (elbowAngle >= 150.0) {
        isDown = false; 
        lowestElbowAngle = 180.0; 
        
        bool isRushed = false;
        if (repMovementStartTime != null) {
          final durationMs = DateTime.now().difference(repMovementStartTime!).inMilliseconds;
          if (durationMs < 1500) isRushed = true; 
        }
        repMovementStartTime = null; 
        
        if (isRushed) {
          badRep = true; 
          repFeedback = "Too fast! Control the rep.";
          AudioService.instance.speakCorrection(["Slow down. Don't rush.", "Control the weight. Too fast."]);
        } else if (hasFormBrokenThisRep) {
          badRep = true; 
          repFeedback = "Rep invalid. Fix your form!";
        } else {
          goodRep = true; 
          repFeedback = "Perfect rep!";
        }
      }
    } else {
      if (elbowAngle <= 90.0) {
        isDown = true; 
        repFeedback = "Depth reached. Push!";
      } else {
        repFeedback = "Lower... hit 90 degrees.";
        
        // --- THE PARADOX FIX ---
        // Only trigger a half-rep if they stand back up to 140 BUT their lowest drop was greater than 100
        if (elbowAngle >= 140.0 && lowestElbowAngle > 100.0) {
          AudioService.instance.speakCorrection(["Half rep. Go lower next time.", "Not low enough. Break 90 degrees.", "Chest to the floor."]);
          lowestElbowAngle = 180.0; 
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