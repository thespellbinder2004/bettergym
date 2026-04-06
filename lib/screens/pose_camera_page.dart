import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart';
import '../services/audio_service.dart';
import '../services/hardware_service.dart';
import '../services/biomechanics_engine.dart';
import '../services/local_db_service.dart';
import '../services/api_services.dart';
import 'session_setup_page.dart';
import 'session_summary_page.dart';
import '../state/frame_controller.dart'; // THE NEW ARCHITECTURE INJECTION

enum SessionPhase { acquisition, prep, active, rest, paused, finished }

class PoseCameraPage extends ConsumerStatefulWidget {
  final List<WorkoutSet> routine;

  const PoseCameraPage({super.key, required this.routine});

  @override
  ConsumerState<PoseCameraPage> createState() => _PoseCameraPageState();
}

class _PoseCameraPageState extends ConsumerState<PoseCameraPage>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  late final PoseDetector _poseDetector;

  bool _isCheckingPermission = true;
  bool _hasCameraPermission = false;

  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isFrontCamera = false;

  InputImageRotation _rotation = InputImageRotation.rotation0deg;
  final ValueNotifier<PoseOverlayData?> _overlayNotifier =
      ValueNotifier<PoseOverlayData?>(null);
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _processIntervalMs = 30;

  SessionPhase _currentPhase = SessionPhase.acquisition;
  SessionPhase? _previousPhase;

  int _currentExerciseIndex = 0;
  int _prepTimeSetting = 10;
  int _restTimeSetting = 30;
  int _countdownSeconds = 12;
  Timer? _phaseTimer;

  int _repsOrSecondsRemaining = 0;
  int _badRepsSessionCount = 0;

  bool _showToast = false;
  Timer? _toastTimer;
  int _acquisitionMissingSeconds = 0;
  int _exitCountdown = 4;
  Timer? _exitTimer;

  int _previousFormState = 1;
  List<int> _formBreakSeconds = [];

  late List<ExerciseTelemetry> _sessionTelemetry;
  DateTime? _sessionStartTime;
  late final String _currentSessionId;

  double _currentRepScoreAccumulator = 0.0;
  int _currentRepFrameCount = 0;

  @override
  void initState() {
    super.initState();
    _currentSessionId = const Uuid().v4();
    WidgetsBinding.instance.addObserver(this);
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
          mode: PoseDetectionMode.stream, model: PoseDetectionModel.accurate),
    );

    _verifyPermissionsAndBoot();
    _unlockOrientation();
  }

  void _lockOrientation() {
    final orientation = MediaQuery.of(context).orientation;
    if (orientation == Orientation.landscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  void _unlockOrientation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _verifyPermissionsAndBoot() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      setState(() {
        _hasCameraPermission = true;
        _isCheckingPermission = false;
      });
      _initCamera();
      _loadSettingsAndStart();
    } else {
      setState(() {
        _hasCameraPermission = false;
        _isCheckingPermission = false;
      });
    }
  }

  Future<void> _loadSettingsAndStart() async {
    final prefs = await SharedPreferences.getInstance();
    await AudioService.instance.loadSettings();

    setState(() {
      _prepTimeSetting = prefs.getInt('prep_time') ?? 10;
      _restTimeSetting = prefs.getInt('rest_time') ?? 30;

      _sessionTelemetry = widget.routine
          .map((ex) => ExerciseTelemetry(
              name: ex.name, isDuration: ex.isDuration, target: ex.target))
          .toList();
    });

    if (widget.routine.isNotEmpty) {
      _sessionStartTime = DateTime.now();
      await LocalDBService.instance.createSessionRecord({
        'id': _currentSessionId,
        'user_id': prefs.getInt('user_id') ?? 1,
        'routine_id': null,
        'status': 'IN_PROGRESS',
        'global_score': 0,
        'duration_seconds': 0,
        'session_type': 'realtime',
        'sync_status': 0,
      });

      _startAcquisitionPhase();
    } else {
      _exitSession();
    }
  }

  void _pauseSession() {
    if (_currentPhase == SessionPhase.paused ||
        _currentPhase == SessionPhase.finished) return;

    _phaseTimer?.cancel();
    _toastTimer?.cancel();
    _exitTimer?.cancel();

    AudioService.instance.playPauseSound();

    setState(() {
      _previousPhase = _currentPhase;
      _currentPhase = SessionPhase.paused;
    });
  }

  void _resumeSession() {
    if (_currentPhase != SessionPhase.paused || _previousPhase == null) return;

    AudioService.instance.playResumeSound();

    setState(() {
      _currentPhase = _previousPhase!;
      _previousPhase = null;
    });

    if (_currentPhase == SessionPhase.acquisition) {
      _runCountdown(() => _startPrepPhase());
    } else if (_currentPhase == SessionPhase.prep) {
      _runCountdown(() => _startActivePhase());
    } else if (_currentPhase == SessionPhase.rest) {
      _runCountdown(() => _startActivePhase());
    } else if (_currentPhase == SessionPhase.active) {
      if (widget.routine[_currentExerciseIndex].isDuration) {
        _runCountdown(() => _completeExercise());
      }
    }
  }

  void _startAcquisitionPhase() {
    _unlockOrientation();
    setState(() {
      _currentPhase = SessionPhase.acquisition;
      _countdownSeconds = 5;
    });
    _triggerToast("Calibrating tracker...", 0);
    _runCountdown(() => _startPrepPhase());
  }

  void _startPrepPhase() {
    _lockOrientation();
    final currentExerciseName = widget.routine.isNotEmpty
        ? widget.routine[_currentExerciseIndex].name
        : "the exercise";
    final nameLower = currentExerciseName.toLowerCase();
    final isHorizontal =
        nameLower.contains("push") || nameLower.contains("plank");
    final isSquat = nameLower.contains("squat");
    final isLunge = nameLower.contains("lunge");
    final isVertical = !isHorizontal && !isSquat && !isLunge;

    setState(() {
      _currentPhase = SessionPhase.prep;
      _countdownSeconds = _prepTimeSetting;
    });

    _triggerToast("Get Ready.", 0);

    // REFACTORED: 16-second rule applied.
    if (_prepTimeSetting >= 16) {
      if (isHorizontal) {
        AudioService.instance.speakPriority([
          "Prepare for $currentExerciseName. Ensure your whole body is visible from the side. Landscape mode is highly recommended.",
          "Getting ready for $currentExerciseName. Drop to the floor, face sideways, and use landscape mode.",
          "Next up, $currentExerciseName. I need a clear side profile in landscape orientation.",
          "Prepare for $currentExerciseName. For best results, tilt your phone to landscape."
        ]);
      } else if (isSquat) {
        AudioService.instance.speakPriority([
          "Prepare for $currentExerciseName. Please face the camera directly. Portrait mode is recommended.",
          "Squats are next. Face the camera. Tilt your phone to portrait mode if its in landscape.",
          "Up next: $currentExerciseName. For best tracking, face the camera and use portrait orientation.",
          "Get ready for $currentExerciseName. Face the camera head on. Portrait mode works best."
        ]);
      } else if (isLunge) {
        AudioService.instance.speakPriority([
          "Prepare for $currentExerciseName. To avoid blocking your legs from the camera, face to the left if lunging with your left leg, and face right to lunge with your right leg.",
          "Getting ready for $currentExerciseName. Face the camera and choose your lunge direction to keep your legs visible. Face right if right foot goes forward, and vice versa.",
          "Next up, $currentExerciseName. Face the camera and orient yourself based on your leading leg for best tracking.",
        ]);
      } else if (isVertical) {
        AudioService.instance.speakPriority([
          "Prepare for $currentExerciseName. Portrait mode and a clear side profile are strictly required.",
          "Getting ready for $currentExerciseName. Drop to the floor and face sideways. Make sure to use portrait orientation.",
          "Next up, $currentExerciseName. I need a clear side profile in portrait orientation.",
          "Prepare for $currentExerciseName. For best results, tilt your phone to portrait and show a clear side view."
        ]);
      }
    }

    _runCountdown(() => _startActivePhase());
  }

  void _startRestPhase() {
    BiomechanicsEngine.instance.reset();
    _unlockOrientation();

    setState(() {
      _currentPhase = SessionPhase.rest;
      _countdownSeconds = _restTimeSetting;
    });

    final nextExerciseName = widget.routine[_currentExerciseIndex].name;
    final nameLower = nextExerciseName.toLowerCase();
    
    final isHorizontal =
        nameLower.contains("push") || nameLower.contains("plank");
    final orientationTip = isHorizontal ? "landscape" : "portrait";

    _triggerToast("Rest. Next: $nextExerciseName", 0);

    // 16-second rule applied.
    if (_restTimeSetting >= 16) {
      AudioService.instance.speakPriority([
        "Set complete. Rest up. We have $nextExerciseName next. Tilt your phone to $orientationTip for me tp track this better.",
        "Good set. Take a breather. $nextExerciseName is coming up. Make sure your phone is in $orientationTip mode.",
        "Take your rest. You'll need to tilt your phone to $orientationTip for the next movement: $nextExerciseName.",
        "Set finished. Next up is $nextExerciseName. For best results, use $orientationTip orientation for that one.",
        "Rest time. Be ready for the next set. Flip your phone if needed, $orientationTip mode works best for $nextExerciseName."
      ]);
    } else {
      AudioService.instance.speakPriority([
        "Set complete. Rest up.",
        "Good work. Catch your breath.",
        "Awesome job. Rest now.",
        "Set finished.",
        "Take a quick break.",
        "You finished a set. Rest up.",
        "Great work. Take a moment to rest.",
        "Set complete! Now take a quick break.",
        "Take a breather, I suggest you stretch out a bit before the next set.",
        "Rest time. Be ready for the next set."
      ]);
    }

    _runCountdown(() => _startActivePhase());
  }

  void _startActivePhase() {
    BiomechanicsEngine.instance.reset();
    _lockOrientation();
    _previousFormState = 1;
    _formBreakSeconds = [];

    final currentExercise = widget.routine[_currentExerciseIndex];
    setState(() {
      _currentPhase = SessionPhase.active;
      _repsOrSecondsRemaining = currentExercise.target;
    });

    _triggerToast("Begin ${currentExercise.name}!", 1);

    if (currentExercise.isDuration) {
      _runCountdown(() => _completeExercise());
    }
  }

  void _completeExercise() async {
    final currentExTelemetry = _sessionTelemetry[_currentExerciseIndex];
    if (currentExTelemetry.repScores.isNotEmpty) {
      await LocalDBService.instance.appendExerciseTelemetry({
        'id': const Uuid().v4(),
        'session_id': _currentSessionId,
        'exercise_name': currentExTelemetry.name,
        'good_reps': currentExTelemetry.goodReps,
        'bad_reps': currentExTelemetry.badReps,
        'exercise_score': currentExTelemetry.finalScore,
        'rep_scores_array': currentExTelemetry.repScores,
      });
      ApiService.syncOfflineData();
    }

    if (_currentExerciseIndex < widget.routine.length - 1) {
      setState(() => _currentExerciseIndex++);
      _startRestPhase();
    } else {
      setState(() => _currentPhase = SessionPhase.finished);
      AudioService.instance.playFinishSound();
      _exitSession(isCompleted: true);
    }
  }

  void _runCountdown(VoidCallback onComplete) {
    _phaseTimer?.cancel();
    _phaseTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _currentPhase == SessionPhase.paused) {
        timer.cancel();
        return;
      }

      final frameData = ref.read(frameProvider);

      setState(() {
        if (_currentPhase == SessionPhase.acquisition) {
          if (frameData.isUserInFrame) {
            _acquisitionMissingSeconds = 0; // Reset missing timer
            _countdownSeconds--;
            if (_countdownSeconds <= 0) {
              timer.cancel();
              onComplete();
            }
          } else {
            _countdownSeconds = 5;
            _acquisitionMissingSeconds++;
            
            // REFACTORED: Trigger audio if they've been missing for 4 seconds
            if (_acquisitionMissingSeconds == 4) {
              AudioService.instance.speakPriority([
                "Please step back so your full body is visible in the frame.",
                "I cannot see you. Please step back.",
                "Back up a bit, you are out of frame.",
                "Adjust your position. I need to see your whole body.",
                "Step further away from the camera.",
                "Your full body is not visible. Please move back a little.",
                "I need to see your whole body. Please adjust your position.",
                "Please adjust your position so I can see your whole body.",
                "You are out of frame. Please step back until your whole body is visible.",
                "I can't see you. Please move back until your whole body is visible in the frame."
              ]);
            }
          }
          return;
        }

        if (_currentPhase == SessionPhase.active &&
            widget.routine[_currentExerciseIndex].isDuration) {
          if (frameData.formState != -1) {
            _repsOrSecondsRemaining--;
            _sessionTelemetry[_currentExerciseIndex].repScores.add(frameData.formScore);
            _sessionTelemetry[_currentExerciseIndex].goodReps++;

            AudioService.instance.playTick();

            if (_repsOrSecondsRemaining <= 0) {
              timer.cancel();
              AudioService.instance.playChime(); // Accomplishment chime
              _completeExercise();
            }
          } else {
            _sessionTelemetry[_currentExerciseIndex].repScores.add(0.0);
            _sessionTelemetry[_currentExerciseIndex].badReps++;
          }
        } else {
          _countdownSeconds--;
          
          if ((_currentPhase == SessionPhase.prep || _currentPhase == SessionPhase.rest)) {
            
            // REFACTORED: 1-minute warning
            if (_countdownSeconds == 60) {
              AudioService.instance.speakPriority([
                "One minute remaining.",
                "Sixty seconds left.",
                "One minute to go. Keep breathing.",
                "Just a minute left on the clock.",
                "One minute remaining. Stay focused.",
                "Sixty seconds remaining. You're doing great.",
                "One minute left. Keep up the good work.",
                "Sixty seconds to go. Almost there."
              ]);
            }
            
            // REFACTORED: 10-second warning (only if original time was >= 15s)
            if (_countdownSeconds == 10 && 
               ((_currentPhase == SessionPhase.prep && _prepTimeSetting >= 15) || 
                (_currentPhase == SessionPhase.rest && _restTimeSetting >= 15))) {
              AudioService.instance.speakPriority([
                "Ten seconds remaining, assume your starting position.",
                "Ten seconds left, get ready."
                "Almost time. Get into position.",
                "Ten seconds. Prepare yourself.",
                "Less than 10 seconds, be in the starting form",
                "Ten seconds remaining. Get ready to start.",
                "Ten seconds left. Assume your starting position.",
                "Clock is ticking. Ten seconds to go.",
                "Prep time is almost up. Get into position in ten seconds.",
                "Rest time is almost up. Be ready to start in ten seconds."
              ]);
            }

            // Beeps at the end
            if (_countdownSeconds <= 3 && _countdownSeconds > 0) {
              AudioService.instance.playLeadInBeep();
            } else if (_countdownSeconds == 0) {
              AudioService.instance.playGoBeep();
            }
          }

          if (_countdownSeconds <= 0) {
            timer.cancel();
            onComplete();
          }
        }
      });
    });
  }
  
  void _triggerToast(String message, int state) {
    _toastTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _showToast = true;
    });

    // Push the forced feedback to Riverpod instead of local setState
    ref.read(frameProvider.notifier).forceFeedback(message, state);

    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showToast = false);
    });
  }

  void _handleTapDown(TapDownDetails details) {
    if (_currentPhase == SessionPhase.paused) return;
    _exitCountdown = 4;
    _triggerToast("Hold for $_exitCountdown seconds to end session", -1);
    _exitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _exitCountdown--;
        if (_exitCountdown <= 0) {
          timer.cancel();
          AudioService.instance.playAbortSound();
          _exitSession(isCompleted: false);
        } else {
          _triggerToast("Hold for $_exitCountdown seconds to end session", -1);
        }
      });
    });
  }

  void _handleTapCancel() {
    if (_exitTimer != null && _exitTimer!.isActive) {
      _exitTimer!.cancel();
      _triggerToast("Exit canceled.", 0);
    }
  }

  Future<void> _initCamera() async {
    try {
      final availableCams = HardwareService.instance.cameras;
      if (availableCams.isEmpty) throw Exception('No cameras found.');

      final camera = availableCams.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => availableCams.first);
      _isFrontCamera = camera.lensDirection == CameraLensDirection.front;
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        fps: 30,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();
      _rotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
              InputImageRotation.rotation0deg;
      await controller.startImageStream(_processCameraImage);

      WakelockPlus.enable();

      if (!mounted) return;
      setState(() {
        _cameraController = controller;
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    final now = DateTime.now();
    if (_isProcessing ||
        _currentPhase == SessionPhase.paused ||
        now.difference(_lastProcessed).inMilliseconds < _processIntervalMs)
      return;

    _isProcessing = true;
    _lastProcessed = now;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;
      final poses = await _poseDetector.processImage(inputImage);
      if (!mounted) return;

      bool targetLocked = false;
      if (poses.isNotEmpty) {
        final landmarks = poses.first.landmarks;
        final nose = landmarks[PoseLandmarkType.nose];
        final leftAnkle = landmarks[PoseLandmarkType.leftAnkle];
        final rightAnkle = landmarks[PoseLandmarkType.rightAnkle];

        if (nose != null && (leftAnkle != null || rightAnkle != null)) {
          if (nose.likelihood > 0.5 &&
              (leftAnkle!.likelihood > 0.5 || rightAnkle!.likelihood > 0.5)) {
            targetLocked = true;
          }
        }
      }

      int currentFormState = 0;
      double currentFormScore = 1.0;
      String currentFeedback = "Position yourself in frame.";
      Set<PoseLandmarkType> currentFaultyJoints = {};
      Set<PoseLandmarkType> activeJointsToRender = {};

      if (targetLocked &&
          _currentPhase == SessionPhase.active &&
          widget.routine.isNotEmpty) {
        final currentExercise = widget.routine[_currentExerciseIndex];

        final analysis = BiomechanicsEngine.instance.processFrame(
            pose: poses.first, exerciseName: currentExercise.name);

        // --- THE DECOUPLED AUDIO TRIGGER ---
        // We check if the math engine requested audio. If yes, the UI handles the hardware.
        if (analysis['audioCue'] != null) {
          AudioService.instance
              .speakCorrection(analysis['audioCue'] as List<String>);
        }
        // -----------------------------------

        activeJointsToRender = analysis['activeJoints'] ?? {};
        currentFormState = analysis['formState'] ?? 0;
        currentFeedback = analysis['feedback'] ?? "Keep going";
        currentFormScore = analysis['formScore'] ?? 1.0;
        currentFaultyJoints = analysis['faultyJoints'] ?? {};

        // Lifecycle data that must remain in StatefulWidget for the Rep Counter logic
        if (_previousFormState == 1 && currentFormState == -1) {
          if (currentExercise.isDuration) {
            _formBreakSeconds.add(_repsOrSecondsRemaining);
            _badRepsSessionCount++;
          }
        }
        _previousFormState = currentFormState;

        if (!currentExercise.isDuration) {
          _currentRepScoreAccumulator += currentFormScore;
          _currentRepFrameCount++;

          if (analysis['goodRepTriggered'] == true) {
            setState(() {
              _repsOrSecondsRemaining--;
            });

            double averageRepScore = _currentRepFrameCount > 0
                ? (_currentRepScoreAccumulator / _currentRepFrameCount)
                : 1.0;
            _sessionTelemetry[_currentExerciseIndex]
                .repScores
                .add(averageRepScore);
            _sessionTelemetry[_currentExerciseIndex].goodReps++;

            _currentRepScoreAccumulator = 0.0;
            _currentRepFrameCount = 0;

            AudioService.instance.playChime();
            if (_repsOrSecondsRemaining <= 0) _completeExercise();
          } else if (analysis['badRepTriggered'] == true) {
            _sessionTelemetry[_currentExerciseIndex].repScores.add(0.0);
            _sessionTelemetry[_currentExerciseIndex].badReps++;

            _currentRepScoreAccumulator = 0.0;
            _currentRepFrameCount = 0;

            // Trigger a toast but route it through the new controller
            _triggerToast("Invalid Rep: Watch your form!", -1);
          }
        }
      }

      // ARCHITECTURAL SHIFT: We no longer call setState() here. We push to Riverpod.
      ref.read(frameProvider.notifier).updateFrameData(
            isUserInFrame: targetLocked,
            formState: currentFormState,
            feedbackMessage: currentFeedback,
            formScore: currentFormScore,
            faultyJoints: currentFaultyJoints,
          );

      final isDevicePortrait =
          MediaQuery.of(context).orientation == Orientation.portrait;

      _overlayNotifier.value = PoseOverlayData(
        poses: poses,
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _rotation,
        isFrontCamera: _isFrontCamera,
        formState: currentFormState,
        isDevicePortrait: isDevicePortrait,
        activeJoints: activeJointsToRender,
        faultyJoints: currentFaultyJoints,
      );
    } catch (e) {
      debugPrint('POSE ERROR: $e');
    } finally {
      _isProcessing = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    final bytes = _concatenatePlanes(image.planes);
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  void _exitSession({bool isCompleted = false}) {
    _phaseTimer?.cancel();
    _toastTimer?.cancel();
    _exitTimer?.cancel();

    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    Duration finalDuration = const Duration(seconds: 0);
    if (_sessionStartTime != null) {
      finalDuration = DateTime.now().difference(_sessionStartTime!);
    }

    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => SessionSummaryPage(
                  sessionId: _currentSessionId,
                  isCompleted: isCompleted,
                  telemetryData: _sessionTelemetry,
                  totalDuration: finalDuration,
                )));
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _toastTimer?.cancel();
    _exitTimer?.cancel();

    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _poseDetector.close();
    _overlayNotifier.dispose();
    super.dispose();
  }

  double _calculateScale(BuildContext context, double previewRatio) {
    final size = MediaQuery.of(context).size;
    final screenRatio = size.width / size.height;
    return screenRatio > previewRatio
        ? screenRatio / previewRatio
        : previewRatio / screenRatio;
  }

  Widget _buildTransitionOverlay(FrameState frameData) {
    if (_currentPhase == SessionPhase.active ||
        _currentPhase == SessionPhase.finished) return const SizedBox.shrink();

    if (_currentPhase == SessionPhase.paused) {
      return Container(
        color: Colors.black.withOpacity(0.85),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.pause_circle_outline,
                  color: mintGreen, size: 80),
              const SizedBox(height: 16),
              const Text("SESSION PAUSED",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4.0)),
              const SizedBox(height: 48),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: mintGreen,
                  foregroundColor: navyBlue,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                icon: const Icon(Icons.play_arrow, size: 28),
                label: const Text("RESUME",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0)),
                onPressed: _resumeSession,
              ),
              const SizedBox(height: 32),
              TextButton(
                onPressed: () {
                  AudioService.instance.playAbortSound();
                  _exitSession(isCompleted: false);
                },
                child: const Text("END SESSION EARLY",
                    style: TextStyle(
                        color: neonRed, fontSize: 14, letterSpacing: 1.5)),
              )
            ],
          ),
        ),
      );
    }

    final isAcquisition = _currentPhase == SessionPhase.acquisition;
    final isPrep = _currentPhase == SessionPhase.prep;

    String nextExerciseName = "";
    if ((isAcquisition || isPrep) && widget.routine.isNotEmpty) {
      nextExerciseName = widget.routine[_currentExerciseIndex].name;
    } else if (_currentPhase == SessionPhase.rest &&
        _currentExerciseIndex < widget.routine.length) {
      nextExerciseName = widget.routine[_currentExerciseIndex].name;
    }

    final displayStatus = isAcquisition
        ? (frameData.isUserInFrame ? 'LOCK SECURED' : 'TARGET LOST')
        : (isPrep ? 'PREPARING' : 'REST');

    final statusColor = isAcquisition
        ? (frameData.isUserInFrame ? mintGreen : neonRed)
        : mintGreen;

    return Container(
      color: Colors.black
          .withOpacity(isAcquisition && !frameData.isUserInFrame ? 0.8 : 0.7),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isAcquisition)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.only(bottom: 24),
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  border: Border.all(color: statusColor, width: 4),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Icon(
                    frameData.isUserInFrame
                        ? Icons.center_focus_strong
                        : Icons.person_search,
                    color: statusColor,
                    size: 48,
                  ),
                ),
              ),
            Text(displayStatus,
                style: TextStyle(
                    color: statusColor,
                    fontSize: 18,
                    letterSpacing: 4.0,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (isAcquisition && !frameData.isUserInFrame)
              const Text("STEP BACK\nFULL BODY REQUIRED",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      height: 1.2))
            else if (isAcquisition && frameData.isUserInFrame)
              Text("HOLD POSITION: $_countdownSeconds",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold))
            else
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return SlideTransition(
                    position: Tween<Offset>(
                            begin: const Offset(0.0, -0.2), end: Offset.zero)
                        .animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: Text(_countdownSeconds.toString(),
                    key: ValueKey<int>(_countdownSeconds),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 120,
                        fontWeight: FontWeight.bold,
                        height: 1.0)),
              ),
            const SizedBox(height: 24),
            Text('NEXT: ${nextExerciseName.toUpperCase()}',
                style: const TextStyle(
                    color: Colors.grey, fontSize: 16, letterSpacing: 1.5)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingPermission) {
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator(color: mintGreen)));
    }

    if (!_hasCameraPermission) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () {
                  SystemChrome.setPreferredOrientations(
                      [DeviceOrientation.portraitUp]);
                  Navigator.pop(context);
                })),
        body: Center(
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text("Camera Access Required",
                    style: TextStyle(color: Colors.white, fontSize: 24)))),
      );
    }

    if (!_isInitialized || _cameraController == null) {
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator(color: mintGreen)));
    }

    // THE UI LISTENS TO RIVERPOD HERE
    final frameData = ref.watch(frameProvider);

    return OrientationBuilder(builder: (context, orientation) {
      final isPortrait = orientation == Orientation.portrait;
      final rawRatio = _cameraController!.value.aspectRatio;
      final previewRatio = isPortrait ? 1 / rawRatio : rawRatio;
      final scale = _calculateScale(context, previewRatio);
      final currentExercise = widget.routine.isNotEmpty
          ? widget.routine[_currentExerciseIndex]
          : null;

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          _pauseSession();
          // Alert dialog logic omitted for brevity, you can keep yours exactly the same
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _handleTapDown,
            onTapUp: (_) => _handleTapCancel(),
            onTapCancel: _handleTapCancel,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Transform.scale(
                  scale: scale,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: previewRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(_cameraController!),
                          ValueListenableBuilder<PoseOverlayData?>(
                            valueListenable: _overlayNotifier,
                            builder: (context, overlay, child) {
                              if (overlay == null ||
                                  _currentPhase == SessionPhase.paused)
                                return const SizedBox.shrink();
                              return RepaintBoundary(
                                child: CustomPaint(
                                  painter: PosePainter(
                                    poses: overlay.poses,
                                    imageSize: overlay.imageSize,
                                    rotation: overlay.rotation,
                                    isFrontCamera: overlay.isFrontCamera,
                                    formState: overlay.formState,
                                    isDevicePortrait: isPortrait,
                                    activeJoints: overlay.activeJoints,
                                    faultyJoints: overlay.faultyJoints,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _buildTransitionOverlay(frameData),
                if (_currentPhase != SessionPhase.paused)
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_currentPhase == SessionPhase.active &&
                                currentExercise != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 8),
                                decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(20)),
                                child: Text(
                                  currentExercise.name.toUpperCase(),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2.0),
                                ),
                              ),
                            const SizedBox(height: 12),
                            AnimatedOpacity(
                              opacity: _showToast ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 300),
                              child: Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: darkSlate.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: frameData.formState == -1
                                          ? neonRed
                                          : (frameData.formState == 1
                                              ? mintGreen
                                              : Colors.transparent),
                                      width: 2),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      frameData.formState == -1
                                          ? Icons.warning_amber_rounded
                                          : (frameData.formState == 1
                                              ? Icons.check_circle
                                              : Icons.info_outline),
                                      color: frameData.formState == -1
                                          ? neonRed
                                          : (frameData.formState == 1
                                              ? mintGreen
                                              : Colors.white),
                                    ),
                                    const SizedBox(width: 12),
                                    Flexible(
                                        child: Text(frameData.feedbackMessage,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold))),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_currentPhase != SessionPhase.paused &&
                    _currentPhase != SessionPhase.acquisition)
                  Positioned(
                    top: isPortrait ? 60 : 20,
                    right: 20,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _pauseSession,
                        borderRadius: BorderRadius.circular(30),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: mintGreen.withOpacity(0.5), width: 2)),
                          child: const Icon(Icons.pause,
                              color: mintGreen, size: 28),
                        ),
                      ),
                    ),
                  ),
                if (_currentPhase == SessionPhase.active &&
                    currentExercise != null &&
                    _currentPhase != SessionPhase.paused)
                  Positioned(
                    right: 20,
                    top: isPortrait
                        ? MediaQuery.of(context).size.height * 0.25
                        : 80,
                    bottom: isPortrait
                        ? MediaQuery.of(context).size.height * 0.25
                        : 80,
                    child: Container(
                      width: 16,
                      decoration: BoxDecoration(
                        color: darkSlate.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.grey.withOpacity(0.3), width: 2),
                      ),
                      alignment: Alignment.bottomCenter,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        height: (isPortrait
                                ? MediaQuery.of(context).size.height * 0.5
                                : MediaQuery.of(context).size.height - 160) *
                            frameData.formScore,
                        decoration: BoxDecoration(
                            color: Color.lerp(
                                neonRed, mintGreen, frameData.formScore),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                  color: Color.lerp(neonRed, mintGreen,
                                          frameData.formScore)!
                                      .withOpacity(0.5),
                                  blurRadius: 8)
                            ]),
                      ),
                    ),
                  ),
                if (_currentPhase == SessionPhase.active &&
                    currentExercise != null &&
                    _currentPhase != SessionPhase.paused)
                  Positioned(
                    bottom: isPortrait ? 40 : null,
                    top: isPortrait
                        ? null
                        : MediaQuery.of(context).size.height / 2 - 90,
                    left: 20,
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withOpacity(0.3),
                          border: Border.all(
                              color: frameData.formState == 1
                                  ? mintGreen.withOpacity(0.8)
                                  : (frameData.formState == -1
                                      ? neonRed
                                      : Colors.grey.withOpacity(0.3)),
                              width: 4),
                          boxShadow: [
                            if (frameData.formState == 1)
                              BoxShadow(
                                  color: mintGreen.withOpacity(0.4),
                                  blurRadius: 20,
                                  spreadRadius: 2),
                            if (frameData.formState == -1)
                              BoxShadow(
                                  color: neonRed.withOpacity(0.6),
                                  blurRadius: 30,
                                  spreadRadius: 8),
                          ]),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            transitionBuilder:
                                (Widget child, Animation<double> animation) {
                              return ScaleTransition(
                                  scale: animation, child: child);
                            },
                            child: Text(
                              _repsOrSecondsRemaining.toString(),
                              key: ValueKey<int>(_repsOrSecondsRemaining),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 80,
                                  fontWeight: FontWeight.bold,
                                  height: 1.0),
                            ),
                          ),
                          Text(currentExercise.isDuration ? 'SEC' : 'REPS',
                              style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16,
                                  letterSpacing: 2.0)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class PoseOverlayData {
  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final bool isFrontCamera;
  final int formState;
  final bool isDevicePortrait;
  final Set<PoseLandmarkType> activeJoints;
  final Set<PoseLandmarkType> faultyJoints;

  PoseOverlayData({
    required this.poses,
    required this.imageSize,
    required this.rotation,
    required this.isFrontCamera,
    required this.formState,
    required this.isDevicePortrait,
    required this.activeJoints,
    required this.faultyJoints,
  });
}

class PosePainter extends CustomPainter {
  PosePainter({
    required this.poses,
    required this.imageSize,
    required this.rotation,
    required this.isFrontCamera,
    required this.formState,
    required this.isDevicePortrait,
    required this.activeJoints,
    required this.faultyJoints,
  });

  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final bool isFrontCamera;
  final int formState;
  final bool isDevicePortrait;
  final Set<PoseLandmarkType> activeJoints;
  final Set<PoseLandmarkType> faultyJoints;

  @override
  void paint(Canvas canvas, Size size) {
    final glowPaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    final solidPointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final inactivePointPaint = Paint()
      ..color = Colors.grey.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    final activeLinePaint = Paint()
      ..color = mintGreen.withOpacity(0.8)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final faultyLinePaint = Paint()
      ..color = neonRed
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final inactiveLinePaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final double absoluteImageWidth =
        isDevicePortrait ? imageSize.height : imageSize.width;
    final double absoluteImageHeight =
        isDevicePortrait ? imageSize.width : imageSize.height;

    for (final pose in poses) {
      final landmarks = pose.landmarks;

      void drawPoint(PoseLandmarkType type) {
        final landmark = landmarks[type];
        if (landmark == null || landmark.likelihood < 0.6) return;
        final point = _mapPoint(Offset(landmark.x, landmark.y), size,
            absoluteImageWidth, absoluteImageHeight);

        if (activeJoints.isEmpty || activeJoints.contains(type)) {
          if (type == PoseLandmarkType.nose) {
            canvas.drawCircle(point, 30, glowPaint);
            canvas.drawCircle(point, 16, solidPointPaint);
          } else {
            canvas.drawCircle(point, 18, glowPaint);
            canvas.drawCircle(point, 8, solidPointPaint);
          }
        } else {
          canvas.drawCircle(point, 6, inactivePointPaint);
        }
      }

      void drawLine(PoseLandmarkType a, PoseLandmarkType b) {
        final p1 = landmarks[a];
        final p2 = landmarks[b];
        if (p1 == null ||
            p2 == null ||
            p1.likelihood < 0.6 ||
            p2.likelihood < 0.6) return;
        final start = _mapPoint(
            Offset(p1.x, p1.y), size, absoluteImageWidth, absoluteImageHeight);
        final end = _mapPoint(
            Offset(p2.x, p2.y), size, absoluteImageWidth, absoluteImageHeight);

        bool isFaulty = faultyJoints.contains(a) && faultyJoints.contains(b);
        bool isActive = activeJoints.isEmpty ||
            (activeJoints.contains(a) && activeJoints.contains(b));

        if (isFaulty) {
          canvas.drawLine(start, end, faultyLinePaint);
        } else if (isActive) {
          canvas.drawLine(start, end, activeLinePaint);
        } else {
          canvas.drawLine(start, end, inactiveLinePaint);
        }
      }

      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow);
      drawLine(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist);
      drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow);
      drawLine(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist);

      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip);
      drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip);
      drawLine(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip);
      drawLine(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee);
      drawLine(PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle);
      drawLine(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee);
      drawLine(PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle);

      final nose = landmarks[PoseLandmarkType.nose];
      final lShoulder = landmarks[PoseLandmarkType.leftShoulder];
      final rShoulder = landmarks[PoseLandmarkType.rightShoulder];

      if (nose != null && lShoulder != null && rShoulder != null) {
        final nosePoint = _mapPoint(Offset(nose.x, nose.y), size,
            absoluteImageWidth, absoluteImageHeight);
        final midShoulderX = (lShoulder.x + rShoulder.x) / 2;
        final midShoulderY = (lShoulder.y + rShoulder.y) / 2;
        final midShoulderPoint = _mapPoint(Offset(midShoulderX, midShoulderY),
            size, absoluteImageWidth, absoluteImageHeight);

        if (activeJoints.contains(PoseLandmarkType.leftShoulder)) {
          canvas.drawLine(nosePoint, midShoulderPoint, activeLinePaint);
        } else {
          canvas.drawLine(nosePoint, midShoulderPoint, inactiveLinePaint);
        }
      }

      final bodyNodes = [
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftElbow,
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.leftWrist,
        PoseLandmarkType.rightWrist,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightKnee,
        PoseLandmarkType.leftAnkle,
        PoseLandmarkType.rightAnkle,
        PoseLandmarkType.nose
      ];
      for (final type in bodyNodes) {
        drawPoint(type);
      }
    }
  }

  Offset _mapPoint(
      Offset point, Size canvasSize, double imgWidth, double imgHeight) {
    double mappedX = point.dx / imgWidth * canvasSize.width;
    double mappedY = point.dy / imgHeight * canvasSize.height;
    if (isFrontCamera) mappedX = canvasSize.width - mappedX;
    return Offset(mappedX, mappedY);
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    return oldDelegate.poses != poses ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.rotation != rotation ||
        oldDelegate.isFrontCamera != isFrontCamera ||
        oldDelegate.formState != formState ||
        oldDelegate.isDevicePortrait != isDevicePortrait;
  }
}
