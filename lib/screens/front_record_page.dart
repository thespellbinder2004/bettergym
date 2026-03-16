import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FrontRecordPage extends StatefulWidget {
  const FrontRecordPage({super.key, required this.cameras});

  final List<CameraDescription> cameras;

  @override
  State<FrontRecordPage> createState() => _FrontRecordPageState();
}

class _FrontRecordPageState extends State<FrontRecordPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isRecording = false;
  String _status = 'Ready';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    final frontCamera = widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );

    final controller = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: true,
      fps: 30,
    );

    try {
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);

      // Force auto exposure + auto focus
      await controller.setExposureMode(ExposureMode.auto);
      await controller.setFocusMode(FocusMode.auto);

      // Reset metering points to default center/system behavior
      await controller.setExposurePoint(null);
      await controller.setFocusPoint(null);

      // Optional: brighten slightly if your front cam still looks dark
      // Try 0.5 first, then 1.0 if needed.
      await controller.setExposureOffset(0.5);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isInitialized = true;
        _status = 'Ready';
      });
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _status = 'Camera init error: $e';
      });
    }
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isRecordingVideo) return;

    try {
      await controller.startVideoRecording();

      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _status = 'Recording...';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Start error: $e';
      });
    }
  }

  Future<void> _stopRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (!controller.value.isRecordingVideo) return;

    try {
      final file = await controller.stopVideoRecording();

      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _status = 'Saved: ${file.path}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Stop error: $e';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
      _isInitialized = false;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (!_isInitialized || controller == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Front Camera Recorder')),
        body: Center(
          child: Text(_status),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Front Camera Recorder')),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: CameraPreview(controller),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  _status,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _isRecording ? null : _startRecording,
                      child: const Text('Start'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isRecording ? _stopRecording : null,
                      child: const Text('Stop'),
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
