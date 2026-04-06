import 'dart:math' as math;
import 'dart:ui';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
// NOTE: I deleted the audio_service.dart import here. Math engines don't speak.
import '../biomechanics_engine.dart';

class PushUpEvaluator extends BaseEvaluator {
  @override
  Map<String, dynamic> evaluate(Pose pose) {
    final landmarks = pose.landmarks;
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];

    if (leftShoulder == null || rightShoulder == null) return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Full body not visible.", 'activeJoints': <PoseLandmarkType>{}, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0, 'audioCue': null};

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
      return {'goodRepTriggered': false, 'badRepTriggered': false, 'formState': 0, 'feedback': "Align side profile to camera.", 'activeJoints': activeJoints, 'faultyJoints': <PoseLandmarkType>{}, 'formScore': 0.0, 'audioCue': null};
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

    // --- HEURISTIC PIPELINE ---
    
    if (shoulderWidth > torsoLength * 0.55) {
      rawFormState = -1;
      rawFaultyJoints.addAll(activeJoints); 
      if (rawFormError.isEmpty) {
        rawFormError = "Turn sideways.";
        ttsVariations = ["Turn sideways. Front view is not supported.", "Please face sideways to the camera.","Face the side for better tracking.", "Side profile only."];
      }
    } 
    else if (hipHingeAngle < 165.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee]);
      if (rawFormError.isEmpty) {
        rawFormError = "Core not straight.";
        ttsVariations = [
          "Keep your body in a straight line.", 
          "Tighten your core.", 
          "Straighten your back.",
          "Lock your core tight.",
          "Don't let your hips sag nor be raised too high.",
          "Maintain a straight line from head to heels.",
          "Imagine a straight line running through your body from head to heels. Keep your hips in line with your shoulders and ankles."
        ];
      }
    } 
    else if (kneeFlexionAngle < 160.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle, PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle]);
      if (rawFormError.isEmpty) {
        rawFormError = "Knees bent.";
        ttsVariations = ["Knees are bent, straighten your legs.", "Keep your legs completely straight.", "Lock your knees out.", "Straighten your legs and squeeze your quads.", "Keep your knees aligned with your ankles."];
      }
    } 
    else if (shoulderAngle > 90.0) {
      rawFormState = -1;
      rawFaultyJoints.addAll([PoseLandmarkType.leftHip, PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, PoseLandmarkType.rightHip, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow]);
      if (rawFormError.isEmpty) {
        rawFormError = "Hands too far forward.";
        ttsVariations = ["Move your hands back. Stack them under your shoulders.", "Your hands are too far forward.", "Stack your wrists directly under your shoulders.", "Keep your hands under your shoulders for better leverage.", "Your hands should be in line with your shoulders, not ahead of them.", "Adjust your hand position to be directly under your shoulders."];
      }
    }

    // 1. CAPTURE THE CUE FROM THE BASE EVALUATOR
    List<String>? audioCuePayload = processFormState(
      rawFormState: rawFormState, rawFormError: rawFormError, 
      rawFaultyJoints: rawFaultyJoints, ttsVariations: ttsVariations, 
      amnesiaConditionMet: elbowAngle >= 140.0 
    );

    // --- START THE STOPWATCH ---
    if (elbowAngle < 140.0 && repMovementStartTime == null) {
      repMovementStartTime = DateTime.now();
    }

    // --- STRICT REP LOGIC ---
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
          // Add the audio cue directly to the payload instead of calling hardware
          audioCuePayload ??= ["Slow down. Don't rush.", "Control the weight. Too fast.","Focus on form, not speed.","Quality over quantity. Slow down your reps.", "Don't rush your reps. Slow and controlled movements lead to better gains.", "Take your time with each rep. Aim for a slow and controlled movement."];
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
        repFeedback = "Lower yourself.";
        
        // Lockout-Proof Half-Rep Detector
        if (elbowAngle >= 150.0 && lowestElbowAngle <= 120.0 && lowestElbowAngle > 90.0) {
          if (publishedFormState != -1) {
            // Add the audio cue directly to the payload instead of calling hardware
            audioCuePayload ??= [
              "Partial repetition. Go lower next time.", 
              "Not low enough. Break 90 degrees.", 
              "Chest to the floor.",
              "Keep your chest close to the floor throughout the movement.",
              "Aim to get your chest closer to the floor. Try to break 90 degrees at the elbow.",
              "To get the most out of your push-ups, aim to lower yourself until your elbows are at least at a 90 degree angle. Try to get your chest as close to the floor as possible."
            ];
          }
          lowestElbowAngle = 180.0; 
        }
      }
    }

    // 2. INJECT THE CAPTURED CUE INTO THE DATA PIPELINE
    return {
      'goodRepTriggered': goodRep, 'badRepTriggered': badRep,
      'formState': publishedFormState, 'feedback': publishedFormState == -1 ? publishedFormError : repFeedback,
      'activeJoints': activeJoints, 'faultyJoints': publishedFaultyJoints, 'formScore': smoothedFormScore,
      'audioCue': audioCuePayload, // PIPELINE COMPLETED
    };
  }
}