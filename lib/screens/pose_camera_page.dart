import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PoseCameraPage extends StatefulWidget {
  const PoseCameraPage({super.key, required this.cameras});

  final List<CameraDescription> cameras;

  @override
  State<PoseCameraPage> createState() => _PoseCameraPageState();
}

class _PoseCameraPageState extends State<PoseCameraPage>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  late final PoseDetector _poseDetector;

  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isFrontCamera = false;

  String _status = 'Initializing...';

  InputImageRotation _rotation = InputImageRotation.rotation0deg;

  final ValueNotifier<PoseOverlayData?> _overlayNotifier =
      ValueNotifier<PoseOverlayData?>(null);

  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);

  // Increase this if preview still feels laggy.
  // 100 ms = about 10 pose detections per second.
  static const int _processIntervalMs = 30;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.base,
      ),
    );

    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final camera = widget.cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => widget.cameras.first,
      );

      _isFrontCamera = camera.lensDirection == CameraLensDirection.front;

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        fps: 30,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();

      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);

      await controller.setExposureMode(ExposureMode.auto);
      await controller.setFocusMode(FocusMode.auto);

      await controller.setExposurePoint(null);
      await controller.setFocusPoint(null);

      try {
        await controller.setExposureOffset(0.5);
      } catch (_) {
        // Some devices may not support this cleanly.
      }

      _rotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
              InputImageRotation.rotation0deg;

      await controller.startImageStream(_processCameraImage);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _isInitialized = true;
        _status = 'Ready';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Camera init error: $e';
      });
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    final now = DateTime.now();

    if (_isProcessing) return;
    if (now.difference(_lastProcessed).inMilliseconds < _processIntervalMs) {
      return;
    }

    _isProcessing = true;
    _lastProcessed = now;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        _overlayNotifier.value = null;
        return;
      }

      final poses = await _poseDetector.processImage(inputImage);

      if (!mounted) return;

      _overlayNotifier.value = PoseOverlayData(
        poses: poses,
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _rotation,
        isFrontCamera: _isFrontCamera,
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

    if (Platform.isAndroid && format != InputImageFormat.nv21) {
      debugPrint('Android image format is not NV21: $format');
      return null;
    }

    if (Platform.isIOS && format != InputImageFormat.bgra8888) {
      debugPrint('iOS image format is not BGRA8888: $format');
      return null;
    }

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;

    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _cameraController = null;
      _isInitialized = false;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _poseDetector.close();
    _overlayNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;

    if (!_isInitialized || controller == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('ML Kit Pose Test')),
        body: Center(child: Text(_status)),
      );
    }

    final previewAspectRatio = 1 / controller.value.aspectRatio;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ML Kit Pose Test'),
      ),
      body: SafeArea(
        child: Center(
          child: AspectRatio(
            aspectRatio: previewAspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(controller),
                ValueListenableBuilder<PoseOverlayData?>(
                  valueListenable: _overlayNotifier,
                  builder: (context, overlay, child) {
                    if (overlay == null) return const SizedBox.shrink();

                    return RepaintBoundary(
                      child: CustomPaint(
                        painter: PosePainter(
                          poses: overlay.poses,
                          imageSize: overlay.imageSize,
                          rotation: overlay.rotation,
                          isFrontCamera: overlay.isFrontCamera,
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
    );
  }
}

class PoseOverlayData {
  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final bool isFrontCamera;

  PoseOverlayData({
    required this.poses,
    required this.imageSize,
    required this.rotation,
    required this.isFrontCamera,
  });
}

class PosePainter extends CustomPainter {
  PosePainter({
    required this.poses,
    required this.imageSize,
    required this.rotation,
    required this.isFrontCamera,
  });

  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final bool isFrontCamera;

  @override
  void paint(Canvas canvas, Size size) {
    final pointPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 4
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    for (final pose in poses) {
      final landmarks = pose.landmarks;

      void drawPoint(PoseLandmarkType type) {
        final landmark = landmarks[type];
        if (landmark == null) return;

        final point = _mapPoint(Offset(landmark.x, landmark.y), size);
        canvas.drawCircle(point, 4, pointPaint);
      }

      void drawLine(PoseLandmarkType a, PoseLandmarkType b) {
        final p1 = landmarks[a];
        final p2 = landmarks[b];
        if (p1 == null || p2 == null) return;

        final start = _mapPoint(Offset(p1.x, p1.y), size);
        final end = _mapPoint(Offset(p2.x, p2.y), size);
        canvas.drawLine(start, end, linePaint);
      }

      for (final type in landmarks.keys) {
        drawPoint(type);
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
    }
  }

  Offset _mapPoint(Offset point, Size canvasSize) {
    final double x = point.dx;
    final double y = point.dy;

    double mappedX;
    double mappedY;

    switch (rotation) {
      case InputImageRotation.rotation90deg:
        mappedX = x / imageSize.height * canvasSize.width;
        mappedY = y / imageSize.width * canvasSize.height;
        break;

      case InputImageRotation.rotation270deg:
        mappedX = x / imageSize.height * canvasSize.width;
        mappedY = y / imageSize.width * canvasSize.height;
        break;

      case InputImageRotation.rotation180deg:
        mappedX = x / imageSize.width * canvasSize.width;
        mappedY = y / imageSize.height * canvasSize.height;
        break;

      case InputImageRotation.rotation0deg:
      default:
        mappedX = x / imageSize.width * canvasSize.width;
        mappedY = y / imageSize.height * canvasSize.height;
        break;
    }

    if (isFrontCamera) {
      mappedX = canvasSize.width - mappedX;
    }

    return Offset(mappedX, mappedY);
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    return oldDelegate.poses != poses ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.rotation != rotation ||
        oldDelegate.isFrontCamera != isFrontCamera;
  }
}
