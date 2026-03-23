import 'dart:async';
import 'dart:io';
<<<<<<< HEAD
import 'dart:ui';
=======
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';

<<<<<<< HEAD
import '../main.dart'; 
=======
import '../main.dart';
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
import 'progress_report_page.dart';
import 'session_setup_page.dart';

enum SessionPhase { prep, active, rest, finished }

class PoseCameraPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final List<WorkoutSet> routine;

<<<<<<< HEAD
  const PoseCameraPage({super.key, required this.cameras, required this.routine});
=======
  const PoseCameraPage(
      {super.key, required this.cameras, required this.routine});
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9

  @override
  State<PoseCameraPage> createState() => _PoseCameraPageState();
}

class _PoseCameraPageState extends State<PoseCameraPage> with WidgetsBindingObserver {
  CameraController? _cameraController;
  late final PoseDetector _poseDetector;

  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isFrontCamera = false;

  InputImageRotation _rotation = InputImageRotation.rotation0deg;
<<<<<<< HEAD
  final ValueNotifier<PoseOverlayData?> _overlayNotifier = ValueNotifier<PoseOverlayData?>(null);
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _processIntervalMs = 30; 

  SessionPhase _currentPhase = SessionPhase.prep;
  int _currentExerciseIndex = 0;
  
  int _prepTimeSetting = 10;
  int _restTimeSetting = 30;
  int _countdownSeconds = 0;
  Timer? _phaseTimer;

  int _repsOrSecondsRemaining = 0;
  int _formState = 0; 
  String _feedbackMessage = "Position yourself in frame.";
  bool _showToast = false;
  Timer? _toastTimer;

  int _exitCountdown = 4;
  Timer? _exitTimer;
=======
  final ValueNotifier<PoseOverlayData?> _overlayNotifier =
      ValueNotifier<PoseOverlayData?>(null);
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _processIntervalMs = 30;
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9

  SessionPhase _currentPhase = SessionPhase.prep;
  int _currentExerciseIndex = 0;

  int _prepTimeSetting = 10;
  int _restTimeSetting = 30;
  int _countdownSeconds = 0;
  Timer? _phaseTimer;

  int _repsOrSecondsRemaining = 0;
  int _formState = 0;
  String _feedbackMessage = "Position yourself in frame.";
  bool _showToast = false;
  Timer? _toastTimer;

  int _exitCountdown = 4;
  Timer? _exitTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poseDetector = PoseDetector(
<<<<<<< HEAD
      options: PoseDetectorOptions(mode: PoseDetectionMode.stream, model: PoseDetectionModel.base),
=======
      options: PoseDetectorOptions(
          mode: PoseDetectionMode.stream, model: PoseDetectionModel.base),
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
    );
    _initCamera();
    _loadSettingsAndStart();
  }

  Future<void> _loadSettingsAndStart() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _prepTimeSetting = prefs.getInt('prep_time') ?? 10;
      _restTimeSetting = prefs.getInt('rest_time') ?? 30;
    });

    if (widget.routine.isNotEmpty) {
      _startPrepPhase();
    } else {
      _exitSession();
    }
  }

  void _startPrepPhase() {
    setState(() {
      _currentPhase = SessionPhase.prep;
      _countdownSeconds = _prepTimeSetting;
    });
    _triggerToast("Get Ready.", 0);
    _runCountdown(() => _startActivePhase());
  }

  void _startRestPhase() {
    setState(() {
      _currentPhase = SessionPhase.rest;
      _countdownSeconds = _restTimeSetting;
    });
    _triggerToast("Rest.", 0);
    _runCountdown(() {
      setState(() => _currentExerciseIndex++);
      _startActivePhase();
    });
  }

  void _startActivePhase() {
    final currentExercise = widget.routine[_currentExerciseIndex];
    setState(() {
      _currentPhase = SessionPhase.active;
      _repsOrSecondsRemaining = currentExercise.target;
    });
<<<<<<< HEAD
    
=======

>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
    _triggerToast("Begin ${currentExercise.name}!", 1);

    if (currentExercise.isDuration) {
      _runCountdown(() => _completeExercise());
    } else {
      _simulateRepDetection();
    }
  }

  void _runCountdown(VoidCallback onComplete) {
    _phaseTimer?.cancel();
    _phaseTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
<<<<<<< HEAD
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        if (_currentPhase == SessionPhase.active && widget.routine[_currentExerciseIndex].isDuration) {
=======
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_currentPhase == SessionPhase.active &&
            widget.routine[_currentExerciseIndex].isDuration) {
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
          _repsOrSecondsRemaining--;
          if (_repsOrSecondsRemaining <= 0) {
            timer.cancel();
            _completeExercise();
          }
        } else {
          _countdownSeconds--;
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
      _exitSession();
    }
  }

  void _simulateRepDetection() {
<<<<<<< HEAD
    _phaseTimer?.cancel(); 
    _phaseTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted || _currentPhase != SessionPhase.active || widget.routine[_currentExerciseIndex].isDuration) {
        timer.cancel(); return;
=======
    _phaseTimer?.cancel();
    _phaseTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted ||
          _currentPhase != SessionPhase.active ||
          widget.routine[_currentExerciseIndex].isDuration) {
        timer.cancel();
        return;
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
      }
      setState(() {
        _repsOrSecondsRemaining--;
        if (_repsOrSecondsRemaining <= 0) {
<<<<<<< HEAD
          timer.cancel(); _completeExercise();
        } else if (_repsOrSecondsRemaining % 3 == 0) {
          _triggerToast("Knees caving in!", -1);
        } else {
          _formState = 1; 
=======
          timer.cancel();
          _completeExercise();
        } else if (_repsOrSecondsRemaining % 3 == 0) {
          _triggerToast("Knees caving in!", -1);
        } else {
          _formState = 1;
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
        }
      });
    });
  }

  void _triggerToast(String message, int state) {
    _toastTimer?.cancel(); // This enforces the "Trample" logic
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
    _exitCountdown = 4;
    _triggerToast("Hold for $_exitCountdown seconds to end session", -1);
    _exitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _exitCountdown--;
        if (_exitCountdown <= 0) {
          timer.cancel();
          _exitSession();
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
<<<<<<< HEAD
      final camera = widget.cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => widget.cameras.first);
=======
      final camera = widget.cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => widget.cameras.first);
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
      _isFrontCamera = camera.lensDirection == CameraLensDirection.front;
      final controller = CameraController(
        camera, ResolutionPreset.medium, enableAudio: false, fps: 30,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
<<<<<<< HEAD
      
      _rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation0deg;
=======

      _rotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
              InputImageRotation.rotation0deg;
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
      await controller.startImageStream(_processCameraImage);

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
<<<<<<< HEAD
    if (_isProcessing || now.difference(_lastProcessed).inMilliseconds < _processIntervalMs) return;
=======
    if (_isProcessing ||
        now.difference(_lastProcessed).inMilliseconds < _processIntervalMs)
      return;
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
    _isProcessing = true;
    _lastProcessed = now;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;
      final poses = await _poseDetector.processImage(inputImage);
      if (!mounted) return;
      
      _overlayNotifier.value = PoseOverlayData(
        poses: poses,
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
<<<<<<< HEAD
        rotation: _rotation, isFrontCamera: _isFrontCamera, formState: _formState, 
=======
        rotation: _rotation,
        isFrontCamera: _isFrontCamera,
        formState: _formState,
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
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

  void _exitSession() {
    _phaseTimer?.cancel();
    _toastTimer?.cancel();
    _exitTimer?.cancel();
<<<<<<< HEAD
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ProgressReportPage(cameras: widget.cameras)));
=======
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => ProgressReportPage(cameras: widget.cameras)));
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _toastTimer?.cancel();
    _exitTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _poseDetector.close();
    _overlayNotifier.dispose();
    super.dispose();
  }

  double _calculateScale(BuildContext context, double previewRatio) {
    final size = MediaQuery.of(context).size;
    final screenRatio = size.width / size.height;
<<<<<<< HEAD
    return screenRatio > previewRatio ? screenRatio / previewRatio : previewRatio / screenRatio;
  }

  Widget _buildTransitionOverlay() {
    if (_currentPhase == SessionPhase.active || _currentPhase == SessionPhase.finished) return const SizedBox.shrink();
    
=======
    return screenRatio > previewRatio
        ? screenRatio / previewRatio
        : previewRatio / screenRatio;
  }

  Widget _buildTransitionOverlay() {
    if (_currentPhase == SessionPhase.active ||
        _currentPhase == SessionPhase.finished) return const SizedBox.shrink();

>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
    final isPrep = _currentPhase == SessionPhase.prep;
    String nextExerciseName = "";
    if (isPrep && widget.routine.isNotEmpty) {
      nextExerciseName = widget.routine[_currentExerciseIndex].name;
<<<<<<< HEAD
    } else if (_currentPhase == SessionPhase.rest && _currentExerciseIndex + 1 < widget.routine.length) {
=======
    } else if (_currentPhase == SessionPhase.rest &&
        _currentExerciseIndex + 1 < widget.routine.length) {
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
      nextExerciseName = widget.routine[_currentExerciseIndex + 1].name;
    }

    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
<<<<<<< HEAD
            Text(isPrep ? 'PREPARING' : 'REST', style: const TextStyle(color: mintGreen, fontSize: 18, letterSpacing: 4.0, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text(_countdownSeconds.toString(), style: const TextStyle(color: Colors.white, fontSize: 120, fontWeight: FontWeight.bold, height: 1.0)),
            const SizedBox(height: 24),
            Text('NEXT: ${nextExerciseName.toUpperCase()}', style: const TextStyle(color: Colors.grey, fontSize: 16, letterSpacing: 1.5)),
=======
            Text(isPrep ? 'PREPARING' : 'REST',
                style: const TextStyle(
                    color: mintGreen,
                    fontSize: 18,
                    letterSpacing: 4.0,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text(_countdownSeconds.toString(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 120,
                    fontWeight: FontWeight.bold,
                    height: 1.0)),
            const SizedBox(height: 24),
            Text('NEXT: ${nextExerciseName.toUpperCase()}',
                style: const TextStyle(
                    color: Colors.grey, fontSize: 16, letterSpacing: 1.5)),
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _cameraController == null) {
<<<<<<< HEAD
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: mintGreen)));
=======
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator(color: mintGreen)));
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
    }

    final previewRatio = 1 / _cameraController!.value.aspectRatio;
    final scale = _calculateScale(context, previewRatio);
<<<<<<< HEAD
    final currentExercise = widget.routine.isNotEmpty ? widget.routine[_currentExerciseIndex] : null;
=======
    final currentExercise = widget.routine.isNotEmpty
        ? widget.routine[_currentExerciseIndex]
        : null;
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _handleTapDown,
        onTapUp: (_) => _handleTapCancel(),
        onTapCancel: _handleTapCancel,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Camera & Skeleton Layer
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
                          if (overlay == null) return const SizedBox.shrink();
                          return RepaintBoundary(
                            child: CustomPaint(
                              painter: PosePainter(
<<<<<<< HEAD
                                poses: overlay.poses, imageSize: overlay.imageSize,
                                rotation: overlay.rotation, isFrontCamera: overlay.isFrontCamera, formState: overlay.formState,
=======
                                poses: overlay.poses,
                                imageSize: overlay.imageSize,
                                rotation: overlay.rotation,
                                isFrontCamera: overlay.isFrontCamera,
                                formState: overlay.formState,
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
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

            // 2. Prep / Rest Overlay
            _buildTransitionOverlay(),

            // 3. UI: Top Stack (Exercise Name -> Notification Toast)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // Hugs the contents tightly
                    children: [
                      // Exercise Name Banner (Always top)
<<<<<<< HEAD
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
                      
=======
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

>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
                      // Auto-hiding Toast Notification (Right beneath the banner)
                      AnimatedOpacity(
                        opacity: _showToast ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20),
<<<<<<< HEAD
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: darkSlate.withOpacity(0.9), borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _formState == -1 ? neonRed : (_formState == 1 ? mintGreen : Colors.transparent), width: 2),
=======
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: darkSlate.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: _formState == -1
                                    ? neonRed
                                    : (_formState == 1
                                        ? mintGreen
                                        : Colors.transparent),
                                width: 2),
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
<<<<<<< HEAD
                                _formState == -1 ? Icons.warning_amber_rounded : (_formState == 1 ? Icons.check_circle : Icons.info_outline),
                                color: _formState == -1 ? neonRed : (_formState == 1 ? mintGreen : Colors.white),
                              ),
                              const SizedBox(width: 12),
                              Flexible(child: Text(_feedbackMessage, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
=======
                                _formState == -1
                                    ? Icons.warning_amber_rounded
                                    : (_formState == 1
                                        ? Icons.check_circle
                                        : Icons.info_outline),
                                color: _formState == -1
                                    ? neonRed
                                    : (_formState == 1
                                        ? mintGreen
                                        : Colors.white),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                  child: Text(_feedbackMessage,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold))),
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 4. UI: Bottom-Left Massive Rep Counter
            if (_currentPhase == SessionPhase.active && currentExercise != null)
              Positioned(
                bottom: 40,
                left: 20,
                child: Container(
<<<<<<< HEAD
                  width: 180, 
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.3), 
                    border: Border.all(color: Colors.grey.withOpacity(0.3), width: 4),
=======
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.3),
                    border: Border.all(
                        color: Colors.grey.withOpacity(0.3), width: 4),
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _repsOrSecondsRemaining.toString(),
<<<<<<< HEAD
                        style: const TextStyle(color: Colors.white, fontSize: 80, fontWeight: FontWeight.bold, height: 1.0),
                      ),
                      Text(currentExercise.isDuration ? 'SEC' : 'REPS', style: const TextStyle(color: Colors.grey, fontSize: 16, letterSpacing: 2.0)),
=======
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 80,
                            fontWeight: FontWeight.bold,
                            height: 1.0),
                      ),
                      Text(currentExercise.isDuration ? 'SEC' : 'REPS',
                          style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 16,
                              letterSpacing: 2.0)),
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PoseOverlayData {
  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final bool isFrontCamera;
  final int formState;

<<<<<<< HEAD
  PoseOverlayData({required this.poses, required this.imageSize, required this.rotation, required this.isFrontCamera, required this.formState});
}

class PosePainter extends CustomPainter {
  PosePainter({required this.poses, required this.imageSize, required this.rotation, required this.isFrontCamera, required this.formState});
=======
  PoseOverlayData(
      {required this.poses,
      required this.imageSize,
      required this.rotation,
      required this.isFrontCamera,
      required this.formState});
}

class PosePainter extends CustomPainter {
  PosePainter(
      {required this.poses,
      required this.imageSize,
      required this.rotation,
      required this.isFrontCamera,
      required this.formState});
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9

  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final bool isFrontCamera;
  final int formState;

  @override
  void paint(Canvas canvas, Size size) {
<<<<<<< HEAD
    final glowPaint = Paint()..color = Colors.white.withOpacity(0.6)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    final solidPointPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
=======
    final glowPaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    final solidPointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9

    Color edgeColor = Colors.grey.withOpacity(0.7);
    if (formState == 1) edgeColor = mintGreen;
    if (formState == -1) edgeColor = neonRed;

<<<<<<< HEAD
    final linePaint = Paint()..color = edgeColor..strokeWidth = 8..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;

    // --- MATHEMATICAL FIX FOR THE ALIGNMENT BUG ---
    // If the device is in portrait mode, the raw image width and height from the camera are actually swapped.
    final bool isPortrait = rotation == InputImageRotation.rotation90deg || rotation == InputImageRotation.rotation270deg;
    final double absoluteImageWidth = isPortrait ? imageSize.height : imageSize.width;
    final double absoluteImageHeight = isPortrait ? imageSize.width : imageSize.height;
=======
    final linePaint = Paint()
      ..color = edgeColor
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9

    // --- MATHEMATICAL FIX FOR THE ALIGNMENT BUG ---
    // If the device is in portrait mode, the raw image width and height from the camera are actually swapped.
    final bool isPortrait = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    final double absoluteImageWidth =
        isPortrait ? imageSize.height : imageSize.width;
    final double absoluteImageHeight =
        isPortrait ? imageSize.width : imageSize.height;

    for (final pose in poses) {
      final landmarks = pose.landmarks;

      void drawPoint(PoseLandmarkType type) {
        final landmark = landmarks[type];
        if (landmark == null || landmark.likelihood < 0.6) return;
<<<<<<< HEAD
        final point = _mapPoint(Offset(landmark.x, landmark.y), size, absoluteImageWidth, absoluteImageHeight);
        canvas.drawCircle(point, 18, glowPaint); 
        canvas.drawCircle(point, 8, solidPointPaint); 
=======
        final point = _mapPoint(Offset(landmark.x, landmark.y), size,
            absoluteImageWidth, absoluteImageHeight);
        canvas.drawCircle(point, 18, glowPaint);
        canvas.drawCircle(point, 8, solidPointPaint);
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
      }

      void drawLine(PoseLandmarkType a, PoseLandmarkType b) {
        final p1 = landmarks[a];
        final p2 = landmarks[b];
<<<<<<< HEAD
        if (p1 == null || p2 == null || p1.likelihood < 0.6 || p2.likelihood < 0.6) return;
        final start = _mapPoint(Offset(p1.x, p1.y), size, absoluteImageWidth, absoluteImageHeight);
        final end = _mapPoint(Offset(p2.x, p2.y), size, absoluteImageWidth, absoluteImageHeight);
=======
        if (p1 == null ||
            p2 == null ||
            p1.likelihood < 0.6 ||
            p2.likelihood < 0.6) return;
        final start = _mapPoint(
            Offset(p1.x, p1.y), size, absoluteImageWidth, absoluteImageHeight);
        final end = _mapPoint(
            Offset(p2.x, p2.y), size, absoluteImageWidth, absoluteImageHeight);
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
        canvas.drawLine(start, end, linePaint);
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

      drawPoint(PoseLandmarkType.nose);

      final bodyNodes = [
<<<<<<< HEAD
        PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow,
        PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist,
        PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee,
        PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle
=======
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
        PoseLandmarkType.rightAnkle
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
      ];
      for (final type in bodyNodes) {
        drawPoint(type);
      }
    }
  }

<<<<<<< HEAD
  Offset _mapPoint(Offset point, Size canvasSize, double imgWidth, double imgHeight) {
=======
  Offset _mapPoint(
      Offset point, Size canvasSize, double imgWidth, double imgHeight) {
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
    // We now divide the points by the corrected, portrait-adjusted width and height
    double mappedX = point.dx / imgWidth * canvasSize.width;
    double mappedY = point.dy / imgHeight * canvasSize.height;
    if (isFrontCamera) mappedX = canvasSize.width - mappedX;
    return Offset(mappedX, mappedY);
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
<<<<<<< HEAD
    return oldDelegate.poses != poses || oldDelegate.imageSize != imageSize ||
        oldDelegate.rotation != rotation || oldDelegate.isFrontCamera != isFrontCamera ||
=======
    return oldDelegate.poses != poses ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.rotation != rotation ||
        oldDelegate.isFrontCamera != isFrontCamera ||
>>>>>>> 50253ec5d3fb46bf3865df1e72df528b515e20c9
        oldDelegate.formState != formState;
  }
}