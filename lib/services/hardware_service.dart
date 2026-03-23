import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class HardwareService {
  // Singleton pattern so the hardware state is shared globally
  static final HardwareService instance = HardwareService._internal();
  HardwareService._internal();

  late List<CameraDescription> cameras;

  Future<void> init() async {
    try {
      cameras = await availableCameras();
      debugPrint('Hardware initialized: ${cameras.length} cameras found.');
    } catch (e) {
      debugPrint('HardwareService Error: Failed to initialize cameras: $e');
      cameras = []; // Fallback to empty list to prevent fatal null crashes
    }
  }
}