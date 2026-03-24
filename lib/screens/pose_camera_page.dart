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

import '../main.dart';
import '../services/audio_service.dart'; 
import '../services/hardware_service.dart'; 
import '../services/biomechanics_engine.dart';
import 'session_setup_page.dart';
import 'session_summary_page.dart';

enum SessionPhase { acquisition, prep, active, rest, paused, finished }

class PoseCameraPage extends StatefulWidget {
  final List<WorkoutSet> routine;

  const PoseCameraPage({super.key, required this.routine});

  @override
  State<PoseCameraPage> createState() => _PoseCameraPageState();
}

class _PoseCameraPageState extends State<PoseCameraPage> with WidgetsBindingObserver {
  CameraController? _cameraController;
  late final PoseDetector _poseDetector;

  bool _isCheckingPermission = true;
  bool _hasCameraPermission = false;

  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isFrontCamera = false;
  bool _isUserInFrame = false;

  InputImageRotation _rotation = InputImageRotation.rotation0deg;
  final ValueNotifier<PoseOverlayData?> _overlayNotifier = ValueNotifier<PoseOverlayData?>(null);
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _processIntervalMs = 30;

  SessionPhase _currentPhase = SessionPhase.acquisition;
  SessionPhase? _previousPhase; 
  
  int _currentExerciseIndex = 0;
  int _prepTimeSetting = 10;
  int _restTimeSetting = 30;
  int _countdownSeconds = 0;
  Timer? _phaseTimer;

  int _repsOrSecondsRemaining = 0;
  int _badRepsSessionCount = 0;
  int _formState = 0;
  String _feedbackMessage = "Position yourself in frame.";
  double _formScore = 1.0; 
  Set<PoseLandmarkType> _faultyJoints = {}; 
  
  bool _showToast = false;
  Timer? _toastTimer;

  int _exitCountdown = 4;
  Timer? _exitTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(mode: PoseDetectionMode.stream, model: PoseDetectionModel.accurate),
    );
    
    _verifyPermissionsAndBoot();

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
    });

    if (widget.routine.isNotEmpty) {
      _startAcquisitionPhase();
    } else {
      _exitSession();
    }
  }

  void _pauseSession() {
    if (_currentPhase == SessionPhase.paused || _currentPhase == SessionPhase.finished) return;

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
      _runCountdown(() {
        setState(() => _currentExerciseIndex++);
        _startActivePhase();
      });
    } else if (_currentPhase == SessionPhase.active) {
      if (widget.routine[_currentExerciseIndex].isDuration) {
        _runCountdown(() => _completeExercise());
      } 
    }
  }

  void _startAcquisitionPhase() {
    setState(() {
      _currentPhase = SessionPhase.acquisition;
      _countdownSeconds = 5; 
    });
    _triggerToast("Calibrating tracker...", 0);
    _runCountdown(() => _startPrepPhase()); 
  }

  void _startPrepPhase() {
    final currentExerciseName = widget.routine.isNotEmpty ? widget.routine[_currentExerciseIndex].name : "the exercise";
    final isPushUp = currentExerciseName.toLowerCase().contains("push");

    setState(() {
      _currentPhase = SessionPhase.prep;
      _countdownSeconds = _prepTimeSetting;
    });
    
    _triggerToast("Get Ready.", 0);
    
    if (_prepTimeSetting >= 20) {
      if (isPushUp) {
        AudioService.instance.speakPriority([
          "Prepare for $currentExerciseName. Ensure your whole body is visible from the side.",
          "Next up, $currentExerciseName. Set your phone down and give me a clear side profile."
        ]);
      } else {
        AudioService.instance.speakPriority([
          "Prepare for $currentExerciseName. Take your time to breathe or grab some water.",
          "Next up, $currentExerciseName. You have plenty of time to get into position."
        ]);
      }
    } else {
      if (isPushUp) {
        AudioService.instance.speakPriority([
          "Prepare for $currentExerciseName. Side profile required.",
          "Get ready for $currentExerciseName. Face sideways to the camera."
        ]);
      } else {
        AudioService.instance.speakPriority([
          "Prepare for $currentExerciseName.",
          "Get ready for $currentExerciseName."
        ]);
      }
    }
    
    _runCountdown(() => _startActivePhase());
  }

  void _startRestPhase() {
    BiomechanicsEngine.instance.reset();
    setState(() {
      _currentPhase = SessionPhase.rest;
      _countdownSeconds = _restTimeSetting;
    });
    _triggerToast("Rest.", 0);
    
    AudioService.instance.speakPriority([
      "Set complete. Take a breather.",
      "Great work. Rest and recover.",
      "Take a moment to catch your breath.",
      "Excellent effort. Time to rest.",
      "Relax your muscles. Rest period starting."
    ]);

    _runCountdown(() {
      setState(() => _currentExerciseIndex++);
      _startActivePhase();
    });
  }

  void _startActivePhase() {
    BiomechanicsEngine.instance.reset();
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

  void _runCountdown(VoidCallback onComplete) {
    _phaseTimer?.cancel();
    _phaseTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _currentPhase == SessionPhase.paused) { timer.cancel(); return; }
      
      setState(() {
        if (_currentPhase == SessionPhase.acquisition) {
          if (_isUserInFrame) {
            _countdownSeconds--;
            if (_countdownSeconds <= 0) {
              timer.cancel();
              onComplete(); 
            }
          } else {
            _countdownSeconds = 5; 
          }
          return; 
        }

        if (_currentPhase == SessionPhase.active && widget.routine[_currentExerciseIndex].isDuration) {
          _repsOrSecondsRemaining--;
          AudioService.instance.playTick(); 

          if (_repsOrSecondsRemaining <= 0) {
            timer.cancel();
            AudioService.instance.playChime(); 
            _completeExercise();
          }
        } else {
          _countdownSeconds--;
          
          if ((_currentPhase == SessionPhase.prep || _currentPhase == SessionPhase.rest)) {
            if (_countdownSeconds == 10) {
              AudioService.instance.speakPriority([
                "Ten seconds remaining.",
                "Ten seconds to go."
              ]);
            } else if (_countdownSeconds <= 3 && _countdownSeconds > 0) {
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

  void _completeExercise() {
    if (_currentExerciseIndex < widget.routine.length - 1) {
      _startRestPhase();
    } else {
      setState(() => _currentPhase = SessionPhase.finished);
      AudioService.instance.playFinishSound(); 
      _exitSession(isCompleted: true);
    }
  }

  void _triggerToast(String message, int state) {
    _toastTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _feedbackMessage = message;
      _formState = state;
      _showToast = true;
    });
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

      final camera = availableCams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => availableCams.first);
      _isFrontCamera = camera.lensDirection == CameraLensDirection.front;
      final controller = CameraController(
        camera, ResolutionPreset.high, enableAudio: false, fps: 30,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();
      _rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation0deg;
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
    if (_isProcessing || _currentPhase == SessionPhase.paused || now.difference(_lastProcessed).inMilliseconds < _processIntervalMs) return;
    
    _isProcessing = true;
    _lastProcessed = now;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;
      final poses = await _poseDetector.processImage(inputImage);
      if (!mounted) return;

      // --- STRICT FULL-BODY TARGET LOCK ---
      bool targetLocked = false;
      if (poses.isNotEmpty) {
        final landmarks = poses.first.landmarks;
        final nose = landmarks[PoseLandmarkType.nose];
        final leftAnkle = landmarks[PoseLandmarkType.leftAnkle];
        final rightAnkle = landmarks[PoseLandmarkType.rightAnkle];

        if (nose != null && (leftAnkle != null || rightAnkle != null)) {
          if (nose.likelihood > 0.5 && (leftAnkle!.likelihood > 0.5 || rightAnkle!.likelihood > 0.5)) {
            targetLocked = true;
          }
        }
      }

      Set<PoseLandmarkType> activeJointsToRender = {};

      if (targetLocked && _currentPhase == SessionPhase.active && widget.routine.isNotEmpty) {
        final currentExercise = widget.routine[_currentExerciseIndex];
        
        if (!currentExercise.isDuration) {
          final analysis = BiomechanicsEngine.instance.processFrame(
            pose: poses.first, 
            exerciseName: currentExercise.name
          );

          activeJointsToRender = analysis['activeJoints'];

          setState(() {
            _formState = analysis['formState'];
            _feedbackMessage = analysis['feedback'];
            _formScore = analysis['formScore'] ?? 1.0;     
            _faultyJoints = analysis['faultyJoints'] ?? {}; 

            if (analysis['goodRepTriggered'] == true) {
              _repsOrSecondsRemaining--;
              AudioService.instance.playChime();
              
              if (_repsOrSecondsRemaining <= 0) {
                _completeExercise();
              }
            } else if (analysis['badRepTriggered'] == true) {
              _badRepsSessionCount++;
              _triggerToast("Invalid Rep: Watch your form!", -1);
            }
          });
        }
      }

      setState(() {
        _isUserInFrame = targetLocked;
      });
      
      final isDevicePortrait = MediaQuery.of(context).orientation == Orientation.portrait;

      _overlayNotifier.value = PoseOverlayData(
        poses: poses,
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _rotation,
        isFrontCamera: _isFrontCamera,
        formState: _formState,
        isDevicePortrait: isDevicePortrait,
        activeJoints: activeJointsToRender, 
        faultyJoints: _faultyJoints, 
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
        rotation: _rotation, format: format, bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final plane in planes) { allBytes.putUint8List(plane.bytes); }
    return allBytes.done().buffer.asUint8List();
  }

  void _exitSession({bool isCompleted = false}) {
    _phaseTimer?.cancel();
    _toastTimer?.cancel();
    _exitTimer?.cancel();
    
    WakelockPlus.disable(); 
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    
    Navigator.pushReplacement(
      context, 
      MaterialPageRoute(builder: (_) => SessionSummaryPage(isCompleted: isCompleted)) 
    );
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
    return screenRatio > previewRatio ? screenRatio / previewRatio : previewRatio / screenRatio;
  }

  Widget _buildTransitionOverlay() {
    if (_currentPhase == SessionPhase.active || _currentPhase == SessionPhase.finished) return const SizedBox.shrink();

    if (_currentPhase == SessionPhase.paused) {
      return Container(
        color: Colors.black.withOpacity(0.85),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.pause_circle_outline, color: mintGreen, size: 80),
              const SizedBox(height: 16),
              const Text("SESSION PAUSED", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4.0)),
              const SizedBox(height: 48),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: mintGreen,
                  foregroundColor: navyBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                icon: const Icon(Icons.play_arrow, size: 28),
                label: const Text("RESUME", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
                onPressed: _resumeSession,
              ),
              const SizedBox(height: 32),
              TextButton(
                onPressed: () {
                  AudioService.instance.playAbortSound(); 
                  _exitSession(isCompleted: false);
                },
                child: const Text("END SESSION EARLY", style: TextStyle(color: neonRed, fontSize: 14, letterSpacing: 1.5)),
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
    } else if (_currentPhase == SessionPhase.rest && _currentExerciseIndex + 1 < widget.routine.length) {
      nextExerciseName = widget.routine[_currentExerciseIndex + 1].name;
    }

    final displayStatus = isAcquisition 
        ? (_isUserInFrame ? 'LOCK SECURED' : 'TARGET LOST') 
        : (isPrep ? 'PREPARING' : 'REST');
        
    final statusColor = isAcquisition 
        ? (_isUserInFrame ? mintGreen : neonRed) 
        : mintGreen;

    return Container(
      color: Colors.black.withOpacity(isAcquisition && !_isUserInFrame ? 0.8 : 0.7),
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
                    _isUserInFrame ? Icons.center_focus_strong : Icons.person_search,
                    color: statusColor,
                    size: 48,
                  ),
                ),
              ),

            Text(displayStatus,
                style: TextStyle(color: statusColor, fontSize: 18, letterSpacing: 4.0, fontWeight: FontWeight.bold)),
            
            const SizedBox(height: 16),
            
            if (isAcquisition && !_isUserInFrame)
              const Text("STEP BACK\nFULL BODY REQUIRED", 
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, height: 1.2))
            else if (isAcquisition && _isUserInFrame)
              Text("HOLD POSITION: $_countdownSeconds", 
                style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold))
            else
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0.0, -0.2), end: Offset.zero).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: Text(
                  _countdownSeconds.toString(),
                  key: ValueKey<int>(_countdownSeconds),
                  style: const TextStyle(color: Colors.white, fontSize: 120, fontWeight: FontWeight.bold, height: 1.0)
                ),
              ),
              
            const SizedBox(height: 24),
            Text('NEXT: ${nextExerciseName.toUpperCase()}',
                style: const TextStyle(color: Colors.grey, fontSize: 16, letterSpacing: 1.5)),
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
        body: Center(child: CircularProgressIndicator(color: mintGreen))
      );
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
              SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
              Navigator.pop(context); 
            }
          )
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: neonRed.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.videocam_off, color: neonRed, size: 64),
                ),
                const SizedBox(height: 32),
                const Text("Camera Access Required", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const Text(
                  "Better-GYM requires your camera to track your form and count reps. We process everything locally and do not store your video.", 
                  textAlign: TextAlign.center, 
                  style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.5)
                ),
                const SizedBox(height: 48),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mintGreen,
                    foregroundColor: navyBlue,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    openAppSettings(); 
                  },
                  child: const Text('OPEN SYSTEM SETTINGS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isInitialized || _cameraController == null) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: mintGreen)));
    }

    return OrientationBuilder(
      builder: (context, orientation) {
        final isPortrait = orientation == Orientation.portrait;
        final rawRatio = _cameraController!.value.aspectRatio;
        final previewRatio = isPortrait ? 1 / rawRatio : rawRatio;
        final scale = _calculateScale(context, previewRatio);
        final currentExercise = widget.routine.isNotEmpty ? widget.routine[_currentExerciseIndex] : null;

        // --- BACK BUTTON TRAP (PopScope) ---
        return PopScope(
          canPop: false, 
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            
            _pauseSession();
            
            final bool? shouldAbort = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: darkSlate,
                title: const Text('ABORT SESSION?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                content: const Text('Are you sure you want to end this workout early? Your progress will be saved as an incomplete session.', style: TextStyle(color: Colors.grey, height: 1.5)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('RESUME', style: TextStyle(color: mintGreen)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: neonRed, foregroundColor: Colors.white),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('ABORT', style: TextStyle(fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            );

            if (shouldAbort == true) {
              AudioService.instance.playAbortSound();
              _exitSession(isCompleted: false);
            } else {
              _resumeSession();
            }
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
                                if (overlay == null || _currentPhase == SessionPhase.paused) return const SizedBox.shrink();
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

                  _buildTransitionOverlay(),

                  if (_currentPhase != SessionPhase.paused)
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_currentPhase == SessionPhase.active && currentExercise != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(20)),
                                  child: Text(
                                    currentExercise.name.toUpperCase(),
                                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2.0),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              AnimatedOpacity(
                                opacity: _showToast ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 300),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 20),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: darkSlate.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: _formState == -1 ? neonRed : (_formState == 1 ? mintGreen : Colors.transparent),
                                        width: 2),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _formState == -1 ? Icons.warning_amber_rounded : (_formState == 1 ? Icons.check_circle : Icons.info_outline),
                                        color: _formState == -1 ? neonRed : (_formState == 1 ? mintGreen : Colors.white),
                                      ),
                                      const SizedBox(width: 12),
                                      Flexible(child: Text(_feedbackMessage, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  if (_currentPhase != SessionPhase.paused && _currentPhase != SessionPhase.acquisition)
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
                              border: Border.all(color: mintGreen.withOpacity(0.5), width: 2),
                            ),
                            child: const Icon(Icons.pause, color: mintGreen, size: 28),
                          ),
                        ),
                      ),
                    ),

                  if (_currentPhase == SessionPhase.active && currentExercise != null && _currentPhase != SessionPhase.paused)
                    Positioned(
                      right: 20,
                      top: isPortrait ? MediaQuery.of(context).size.height * 0.25 : 80,
                      bottom: isPortrait ? MediaQuery.of(context).size.height * 0.25 : 80,
                      child: Container(
                        width: 16,
                        decoration: BoxDecoration(
                          color: darkSlate.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.withOpacity(0.3), width: 2),
                        ),
                        alignment: Alignment.bottomCenter,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          height: (isPortrait ? MediaQuery.of(context).size.height * 0.5 : MediaQuery.of(context).size.height - 160) * _formScore,
                          decoration: BoxDecoration(
                            color: Color.lerp(neonRed, mintGreen, _formScore),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(color: Color.lerp(neonRed, mintGreen, _formScore)!.withOpacity(0.5), blurRadius: 8)
                            ]
                          ),
                        ),
                      ),
                    ),

                  if (_currentPhase == SessionPhase.active && currentExercise != null && _currentPhase != SessionPhase.paused)
                    Positioned(
                      bottom: isPortrait ? 40 : null,
                      top: isPortrait ? null : MediaQuery.of(context).size.height / 2 - 90,
                      left: 20,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withOpacity(0.3),
                          border: Border.all(
                            color: _formState == 1 ? mintGreen.withOpacity(0.8) : (_formState == -1 ? neonRed : Colors.grey.withOpacity(0.3)), 
                            width: 4
                          ),
                          boxShadow: [
                            if (_formState == 1) BoxShadow(color: mintGreen.withOpacity(0.4), blurRadius: 20, spreadRadius: 2),
                            if (_formState == -1) BoxShadow(color: neonRed.withOpacity(0.6), blurRadius: 30, spreadRadius: 8),
                          ]
                        ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            transitionBuilder: (Widget child, Animation<double> animation) {
                              return ScaleTransition(scale: animation, child: child);
                            },
                            child: Text(
                              _repsOrSecondsRemaining.toString(),
                              key: ValueKey<int>(_repsOrSecondsRemaining),
                              style: const TextStyle(color: Colors.white, fontSize: 80, fontWeight: FontWeight.bold, height: 1.0),
                            ),
                          ),
                          Text(currentExercise.isDuration ? 'SEC' : 'REPS',
                              style: const TextStyle(color: Colors.grey, fontSize: 16, letterSpacing: 2.0)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }
    );
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
    final glowPaint = Paint()..color = Colors.white.withOpacity(0.6)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    final solidPointPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final inactivePointPaint = Paint()..color = Colors.grey.withOpacity(0.5)..style = PaintingStyle.fill;

    final activeLinePaint = Paint()..color = mintGreen.withOpacity(0.8)..strokeWidth = 6..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    final faultyLinePaint = Paint()..color = neonRed..strokeWidth = 8..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    final inactiveLinePaint = Paint()..color = Colors.grey.withOpacity(0.3)..strokeWidth = 4..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;

    final double absoluteImageWidth = isDevicePortrait ? imageSize.height : imageSize.width;
    final double absoluteImageHeight = isDevicePortrait ? imageSize.width : imageSize.height;

    for (final pose in poses) {
      final landmarks = pose.landmarks;

      void drawPoint(PoseLandmarkType type) {
        final landmark = landmarks[type];
        if (landmark == null || landmark.likelihood < 0.6) return;
        final point = _mapPoint(Offset(landmark.x, landmark.y), size, absoluteImageWidth, absoluteImageHeight);
        
        if (activeJoints.isEmpty || activeJoints.contains(type)) {
          // NEW: Make the nose (head) significantly larger
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
        if (p1 == null || p2 == null || p1.likelihood < 0.6 || p2.likelihood < 0.6) return;
        final start = _mapPoint(Offset(p1.x, p1.y), size, absoluteImageWidth, absoluteImageHeight);
        final end = _mapPoint(Offset(p2.x, p2.y), size, absoluteImageWidth, absoluteImageHeight);
        
        bool isFaulty = faultyJoints.contains(a) && faultyJoints.contains(b);
        bool isActive = activeJoints.isEmpty || (activeJoints.contains(a) && activeJoints.contains(b));

        if (isFaulty) {
          canvas.drawLine(start, end, faultyLinePaint);
        } else if (isActive) {
          canvas.drawLine(start, end, activeLinePaint);
        } else {
          canvas.drawLine(start, end, inactiveLinePaint);
        }
      }

      // Arms
      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow);
      drawLine(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist);
      drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow);
      drawLine(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist);
      
      // Torso & Legs
      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip);
      drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip);
      drawLine(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip);
      drawLine(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee);
      drawLine(PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle);
      drawLine(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee);
      drawLine(PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle);

      // NEW: Draw the Neck Line connecting Nose to Mid-Shoulder
      final nose = landmarks[PoseLandmarkType.nose];
      final lShoulder = landmarks[PoseLandmarkType.leftShoulder];
      final rShoulder = landmarks[PoseLandmarkType.rightShoulder];
      
      if (nose != null && lShoulder != null && rShoulder != null) {
        final nosePoint = _mapPoint(Offset(nose.x, nose.y), size, absoluteImageWidth, absoluteImageHeight);
        final midShoulderX = (lShoulder.x + rShoulder.x) / 2;
        final midShoulderY = (lShoulder.y + rShoulder.y) / 2;
        final midShoulderPoint = _mapPoint(Offset(midShoulderX, midShoulderY), size, absoluteImageWidth, absoluteImageHeight);
        
        // Draw the neck in active color if shoulders are active
        if (activeJoints.contains(PoseLandmarkType.leftShoulder)) {
          canvas.drawLine(nosePoint, midShoulderPoint, activeLinePaint);
        } else {
          canvas.drawLine(nosePoint, midShoulderPoint, inactiveLinePaint);
        }
      }

      final bodyNodes = [
        PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow,
        PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist,
        PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee,
        PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle,
        PoseLandmarkType.nose
      ];
      for (final type in bodyNodes) {
        drawPoint(type);
      }
    }
  }

  Offset _mapPoint(Offset point, Size canvasSize, double imgWidth, double imgHeight) {
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