import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../main.dart'; 
import 'progress_report_page.dart';

class PoseCameraPage extends StatefulWidget {
  const PoseCameraPage({super.key, required this.cameras});

  final List<CameraDescription> cameras;

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
  final ValueNotifier<PoseOverlayData?> _overlayNotifier = ValueNotifier<PoseOverlayData?>(null);
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _processIntervalMs = 30; 

  final String _currentExercise = "SQUATS";
  int _repsRemaining = 15;
  int _formState = 0; 
  String _feedbackMessage = "Position yourself in frame.";
  bool _showToast = true;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(mode: PoseDetectionMode.stream, model: PoseDetectionModel.base),
    );
    _initCamera();
    _simulateServerFeedback();
  }

  void _triggerToast(String message, int state) {
    _toastTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _feedbackMessage = message;
      _formState = state;
      _showToast = true;
    });
    // Auto-hide after 3 seconds
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showToast = false);
    });
  }

  void _simulateServerFeedback() async {
    _triggerToast("Tracking initialized.", 0);
    await Future.delayed(const Duration(seconds: 4));
    _triggerToast("Knees caving in! Push them outward.", -1);
    await Future.delayed(const Duration(seconds: 4));
    if (mounted) setState(() => _repsRemaining--);
    _triggerToast("Good form. Keep your chest up.", 1);
  }

  Future<void> _initCamera() async {
    try {
      final camera = widget.cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => widget.cameras.first,
      );
      _isFrontCamera = camera.lensDirection == CameraLensDirection.front;
      final controller = CameraController(
        camera, ResolutionPreset.medium, enableAudio: false, fps: 30,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await controller.setExposureMode(ExposureMode.auto);
      await controller.setFocusMode(FocusMode.auto);

      _rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation0deg;
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
    if (_isProcessing || now.difference(_lastProcessed).inMilliseconds < _processIntervalMs) return;

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
        rotation: _rotation,
        isFrontCamera: _isFrontCamera,
        formState: _formState, 
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
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ProgressReportPage(cameras: widget.cameras)),
    );
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _poseDetector.close();
    _overlayNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _cameraController == null) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: mintGreen)));
    }

    // Mathematical fix for the aspect ratio scaling
    final size = MediaQuery.of(context).size;
    final deviceRatio = size.width / size.height;
    final scale = 1 / (_cameraController!.value.aspectRatio * deviceRatio);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Full Screen Camera (Cropped to fill, fixing the skeleton alignment issue)
          Transform.scale(
            scale: scale,
            child: Center(
              child: AspectRatio(
                aspectRatio: 1 / _cameraController!.value.aspectRatio,
                child: CameraPreview(_cameraController!),
              ),
            ),
          ),

          // 2. ML Kit Skeleton Overlay (Scaled equivalently to match the cropped camera feed)
          Transform.scale(
            scale: scale,
            child: ValueListenableBuilder<PoseOverlayData?>(
              valueListenable: _overlayNotifier,
              builder: (context, overlay, child) {
                if (overlay == null) return const SizedBox.shrink();
                return Center(
                  child: AspectRatio(
                    aspectRatio: 1 / _cameraController!.value.aspectRatio,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: PosePainter(
                          poses: overlay.poses, imageSize: overlay.imageSize,
                          rotation: overlay.rotation, isFrontCamera: overlay.isFrontCamera,
                          formState: overlay.formState,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // 3. HUD: Auto-hiding Toast Notification
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Align(
                alignment: Alignment.topCenter,
                child: AnimatedOpacity(
                  opacity: _showToast ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: darkSlate.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _formState == -1 ? neonRed : (_formState == 1 ? mintGreen : Colors.transparent), width: 2),
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
              ),
            ),
          ),

          // 4. HUD: Control Deck (Bottom Layer)
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Bottom-Left Exit Button
                Container(
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey, size: 32),
                    onPressed: _exitSession,
                  ),
                ),

                // Bottom-Right Massive Rep Counter & Exercise Text
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_currentExercise, style: const TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
                    const SizedBox(height: 8),
                    Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(0.5),
                        border: Border.all(color: Colors.grey.withOpacity(0.5), width: 4),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _repsRemaining.toString(),
                            style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.bold, height: 1.0),
                          ),
                          const Text('REPS', style: TextStyle(color: Colors.grey, fontSize: 14, letterSpacing: 2.0)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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

  PoseOverlayData({required this.poses, required this.imageSize, required this.rotation, required this.isFrontCamera, required this.formState});
}

class PosePainter extends CustomPainter {
  PosePainter({required this.poses, required this.imageSize, required this.rotation, required this.isFrontCamera, required this.formState});

  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final bool isFrontCamera;
  final int formState;

  @override
  void paint(Canvas canvas, Size size) {
    // Increased node sizes
    final glowPaint = Paint()..color = Colors.white.withOpacity(0.6)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final solidPointPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;

    Color edgeColor = Colors.grey.withOpacity(0.7);
    if (formState == 1) edgeColor = mintGreen;
    if (formState == -1) edgeColor = neonRed;

    // Increased line thickness
    final linePaint = Paint()..color = edgeColor..strokeWidth = 8..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;

    for (final pose in poses) {
      final landmarks = pose.landmarks;

      void drawPoint(PoseLandmarkType type) {
        final landmark = landmarks[type];
        if (landmark == null || landmark.likelihood < 0.6) return;
        final point = _mapPoint(Offset(landmark.x, landmark.y), size);
        canvas.drawCircle(point, 12, glowPaint); 
        canvas.drawCircle(point, 6, solidPointPaint); 
      }

      void drawLine(PoseLandmarkType a, PoseLandmarkType b) {
        final p1 = landmarks[a];
        final p2 = landmarks[b];
        if (p1 == null || p2 == null || p1.likelihood < 0.6 || p2.likelihood < 0.6) return;
        final start = _mapPoint(Offset(p1.x, p1.y), size);
        final end = _mapPoint(Offset(p2.x, p2.y), size);
        canvas.drawLine(start, end, linePaint);
      }

      // Draw Edges (Bones)
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

      // Draw Single Head Node (Consolidated to Nose)
      drawPoint(PoseLandmarkType.nose);

      // Draw Body Nodes (Joints)
      final bodyNodes = [
        PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow,
        PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist,
        PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee,
        PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle
      ];
      for (final type in bodyNodes) {
        drawPoint(type);
      }
    }
  }

  Offset _mapPoint(Offset point, Size canvasSize) {
    double mappedX = point.dx / imageSize.width * canvasSize.width;
    double mappedY = point.dy / imageSize.height * canvasSize.height;
    if (isFrontCamera) mappedX = canvasSize.width - mappedX;
    return Offset(mappedX, mappedY);
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    return oldDelegate.poses != poses || oldDelegate.imageSize != imageSize ||
        oldDelegate.rotation != rotation || oldDelegate.isFrontCamera != isFrontCamera ||
        oldDelegate.formState != formState;
  }
}