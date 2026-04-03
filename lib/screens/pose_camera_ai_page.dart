import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../main.dart';
import '../services/hardware_service.dart';
import 'session_setup_page.dart';
import '../services/api_services.dart';

enum AiSessionPhase {
  idle,
  prepCountdown,
  restCountdown,
  recording,
  paused,
  finished,
}

class PoseCameraAiPage extends StatefulWidget {
  final List<WorkoutSet> routine;

  const PoseCameraAiPage({
    super.key,
    required this.routine,
  });

  @override
  State<PoseCameraAiPage> createState() => _PoseCameraAiPageState();
}

class _PoseCameraAiPageState extends State<PoseCameraAiPage>
    with WidgetsBindingObserver {
  int _prepTimeSetting = 10;
  int _restTimeSetting = 30;

  CameraController? _cameraController;

  bool _isCheckingPermission = true;
  bool _hasCameraPermission = false;
  bool _isInitialized = false;
  bool _isFrontCamera = false;

  AiSessionPhase _phase = AiSessionPhase.idle;
  AiSessionPhase? _phaseBeforePause;

  int _currentExerciseIndex = 0;
  int _countdownSeconds = 0;
  Timer? _countdownTimer;

  bool _isRecording = false;
  bool _isSaving = false;
  String _savingText = 'Saving video...';

  late final String _sessionId;
  Directory? _sessionDirectory;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionId = const Uuid().v4();
    _unlockOrientation();
    _boot();
  }

  Future<void> _boot() async {
    await _loadSettings();
    await _verifyPermissionsAndBoot();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    _prepTimeSetting = prefs.getInt('prep_time') ?? 10;
    _restTimeSetting = prefs.getInt('rest_time') ?? 30;
  }

  Future<void> _verifyPermissionsAndBoot() async {
    final status = await Permission.camera.request();

    if (status.isGranted) {
      if (!mounted) return;
      setState(() {
        _hasCameraPermission = true;
        _isCheckingPermission = false;
      });

      await _initCamera();
      await _prepareSessionFolder();
    } else {
      if (!mounted) return;
      setState(() {
        _hasCameraPermission = false;
        _isCheckingPermission = false;
      });
    }
  }

  Future<void> _initCamera() async {
    try {
      final availableCams = HardwareService.instance.cameras;
      if (availableCams.isEmpty) {
        throw Exception('No cameras found.');
      }

      final camera = availableCams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => availableCams.first,
      );

      _isFrontCamera = camera.lensDirection == CameraLensDirection.front;

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: true,
        fps: 30,
      );

      await controller.initialize();
      await controller.prepareForVideoRecording();

      if (!mounted) return;

      setState(() {
        _cameraController = controller;
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint('AI camera init error: $e');
    }
  }

  Future<void> _prepareSessionFolder() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final sessionsDir = Directory(p.join(baseDir.path, 'ai_sessions'));

    if (!await sessionsDir.exists()) {
      await sessionsDir.create(recursive: true);
    }

    final sessionDir = Directory(
      p.join(
        sessionsDir.path,
        'session_${DateTime.now().millisecondsSinceEpoch}_$_sessionId',
      ),
    );

    if (!await sessionDir.exists()) {
      await sessionDir.create(recursive: true);
    }

    _sessionDirectory = sessionDir;
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

  WorkoutSet? get _currentExercise {
    if (widget.routine.isEmpty) return null;
    if (_currentExerciseIndex < 0 ||
        _currentExerciseIndex >= widget.routine.length) {
      return null;
    }
    return widget.routine[_currentExerciseIndex];
  }

  bool get _isLastExercise =>
      _currentExerciseIndex == widget.routine.length - 1;

  Future<void> _startRoutine() async {
    if (widget.routine.isEmpty) return;

    setState(() {
      _currentExerciseIndex = 0;
    });

    await _startPrepCountdown();
  }

  Future<void> _startPrepCountdown() async {
    _countdownTimer?.cancel();
    _lockOrientation();

    if (!mounted) return;
    setState(() {
      _phase = AiSessionPhase.prepCountdown;
      _countdownSeconds = _prepTimeSetting;
      _isRecording = false;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_phase != AiSessionPhase.prepCountdown) {
        timer.cancel();
        return;
      }

      if (_countdownSeconds <= 1) {
        timer.cancel();
        setState(() {
          _countdownSeconds = 0;
        });
        await _startRecordingForCurrentExercise();
      } else {
        setState(() {
          _countdownSeconds--;
        });
      }
    });
  }

  Future<void> _startRestCountdown() async {
    _countdownTimer?.cancel();
    _unlockOrientation();

    if (!mounted) return;
    setState(() {
      _phase = AiSessionPhase.restCountdown;
      _countdownSeconds = _restTimeSetting;
      _isRecording = false;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_phase != AiSessionPhase.restCountdown) {
        timer.cancel();
        return;
      }

      if (_countdownSeconds <= 1) {
        timer.cancel();

        setState(() {
          _countdownSeconds = 0;
          _currentExerciseIndex++; // move to next
        });

        // 🔥 DIRECTLY RECORD (NO PREP)
        await _startRecordingForCurrentExercise();
      } else {
        setState(() {
          _countdownSeconds--;
        });
      }
    });
  }

  Future<void> _startRecordingForCurrentExercise() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (_currentExercise == null) return;

    try {
      if (_cameraController!.value.isRecordingVideo) {
        await _cameraController!.stopVideoRecording();
      }

      await _cameraController!.startVideoRecording();

      if (!mounted) return;

      setState(() {
        _phase = AiSessionPhase.recording;
        _isRecording = true;
      });
    } catch (e) {
      debugPrint('Start recording error: $e');
    }
  }

  Future<void> _finishCurrentExerciseAndContinue() async {
    if (_cameraController == null || _currentExercise == null || _isSaving)
      return;

    final currentExercise = _currentExercise!;
    final isLastExercise = _isLastExercise;

    try {
      if (mounted) {
        setState(() {
          _isSaving = true;
          _isRecording = false;
          _savingText = isLastExercise
              ? 'Saving final video...'
              : 'Saving exercise video...';
        });
      }

      XFile? recordedFile;

      if (_cameraController!.value.isRecordingVideo) {
        recordedFile = await _cameraController!.stopVideoRecording();
      }

      if (recordedFile != null && _sessionDirectory != null) {
        final safeExerciseName = currentExercise.name
            .toLowerCase()
            .replaceAll(' ', '_')
            .replaceAll(RegExp(r'[^a-z0-9_]'), '');

        final fileName = '${_currentExerciseIndex + 1}_$safeExerciseName.mp4';
        final targetPath = p.join(_sessionDirectory!.path, fileName);

        if (mounted) {
          setState(() {
            _savingText = 'Saving video to device...';
          });
        }

        final savedFile = await File(recordedFile.path).copy(targetPath);

        try {
          final prefs = await SharedPreferences.getInstance();
          final userId = prefs.getInt('user_id');

          if (userId != null) {
            if (mounted) {
              setState(() {
                _savingText = 'Uploading video...';
              });
            }

            final result = await ApiService.uploadExerciseVideo(
              userId: userId,
              sessionId: _sessionId,
              exerciseName: currentExercise.name,
              videoPath: savedFile.path,
            );

            debugPrint('UPLOAD SUCCESS: $result');
          } else {
            debugPrint('UPLOAD SKIPPED: user_id is null');
          }
        } catch (e) {
          debugPrint('UPLOAD ERROR: $e');
        }
      }

      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }

      if (isLastExercise) {
        await _finishSession();
      } else {
        await _startRestCountdown();
      }
    } catch (e) {
      debugPrint('Finish exercise error: $e');

      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _pauseSession() {
    if (_phase == AiSessionPhase.finished || _phase == AiSessionPhase.idle)
      return;

    _countdownTimer?.cancel();
    _phaseBeforePause = _phase;

    setState(() {
      _phase = AiSessionPhase.paused;
    });
  }

  Future<void> _resumeSession() async {
    if (_cameraController == null) return;

    final previous = _phaseBeforePause;

    if (_isRecording && _cameraController!.value.isRecordingVideo) {
      setState(() {
        _phase = AiSessionPhase.recording;
      });
      return;
    }

    if (previous == AiSessionPhase.restCountdown) {
      await _startRestCountdown();
    } else if (previous == AiSessionPhase.prepCountdown) {
      await _startPrepCountdown();
    } else {
      await _startPrepCountdown();
    }
  }

  Future<void> _finishSession() async {
    setState(() {
      _phase = AiSessionPhase.finished;
      _isRecording = false;
    });

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: darkSlate,
        title: const Text(
          'SESSION COMPLETE',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        content: Text(
          _sessionDirectory == null
              ? 'Workout finished.'
              : 'All exercise videos were saved in:\n\n${_sessionDirectory!.path}',
          style: const TextStyle(color: Colors.grey, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: mintGreen,
              foregroundColor: navyBlue,
            ),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text(
              'DONE',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  double _calculateScale(BuildContext context, double previewRatio) {
    final size = MediaQuery.of(context).size;
    final screenRatio = size.width / size.height;
    return screenRatio > previewRatio
        ? screenRatio / previewRatio
        : previewRatio / screenRatio;
  }

  Widget _buildTransitionOverlay() {
    if (_phase == AiSessionPhase.recording ||
        _phase == AiSessionPhase.finished) {
      return const SizedBox.shrink();
    }

    if (_phase == AiSessionPhase.paused) {
      return Container(
        color: Colors.black.withOpacity(0.85),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.pause_circle_outline,
                  color: mintGreen, size: 80),
              const SizedBox(height: 16),
              const Text(
                "SESSION PAUSED",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4.0,
                ),
              ),
              const SizedBox(height: 48),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: mintGreen,
                  foregroundColor: navyBlue,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                icon: const Icon(Icons.play_arrow, size: 28),
                label: const Text(
                  "RESUME",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                  ),
                ),
                onPressed: _resumeSession,
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  "END SESSION",
                  style: TextStyle(
                    color: neonRed,
                    fontSize: 14,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_phase == AiSessionPhase.idle) {
      return Container(
        color: Colors.black.withOpacity(0.68),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: mintGreen.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: mintGreen.withOpacity(0.4), width: 2),
                ),
                child: const Icon(Icons.videocam, color: mintGreen, size: 56),
              ),
              const SizedBox(height: 24),
              const Text(
                'READY TO RECORD',
                style: TextStyle(
                  color: mintGreen,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Each exercise will be recorded\nas a separate video.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: mintGreen,
                  foregroundColor: navyBlue,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                onPressed: _startRoutine,
                child: const Text(
                  'START ROUTINE',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final bool isRest = _phase == AiSessionPhase.restCountdown;
    final String heading = isRest ? 'REST' : 'GET READY';

    return Container(
      color: Colors.black.withOpacity(0.72),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              heading,
              style: const TextStyle(
                color: mintGreen,
                fontSize: 18,
                letterSpacing: 4.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                _countdownSeconds.toString(),
                key: ValueKey('${_phase.name}_$_countdownSeconds'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 120,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (_currentExercise != null)
              Text(
                isRest
                    ? (_isLastExercise
                        ? 'LAST EXERCISE COMPLETED'
                        : 'NEXT: ${widget.routine[_currentExerciseIndex + 1].name.toUpperCase()}')
                    : 'NEXT: ${_currentExercise!.name.toUpperCase()}',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                  letterSpacing: 1.5,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavingOverlay() {
    if (!_isSaving) return const SizedBox.shrink();

    return Container(
      color: Colors.black.withOpacity(0.82),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: mintGreen),
            const SizedBox(height: 24),
            Text(
              _savingText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Please wait...',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopOverlay(WorkoutSet currentExercise) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              currentExercise.name.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPauseButton(bool isPortrait) {
    return Positioned(
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
                color: mintGreen.withOpacity(0.5),
                width: 2,
              ),
            ),
            child: const Icon(Icons.pause, color: mintGreen, size: 28),
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingIndicator() {
    return Positioned(
      top: 110,
      left: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: neonRed.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.fiber_manual_record, color: neonRed, size: 14),
            SizedBox(width: 8),
            Text(
              'RECORDING',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressPill() {
    return Positioned(
      top: 160,
      left: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.65),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'EXERCISE ${_currentExerciseIndex + 1}/${widget.routine.length}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }

  Widget _buildTargetCircle(WorkoutSet currentExercise, bool isPortrait) {
    return Positioned(
      bottom: isPortrait ? 40 : null,
      top: isPortrait ? null : MediaQuery.of(context).size.height / 2 - 90,
      left: 20,
      child: Container(
        width: 180,
        height: 180,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withOpacity(0.32),
          border: Border.all(
            color: mintGreen.withOpacity(0.8),
            width: 4,
          ),
          boxShadow: [
            BoxShadow(
              color: mintGreen.withOpacity(0.25),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              currentExercise.target.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 72,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
            ),
            Text(
              currentExercise.isDuration ? 'SEC' : 'REPS',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 16,
                letterSpacing: 2.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNextButton(bool isPortrait) {
    return Positioned(
      right: 20,
      bottom: isPortrait ? 40 : 30,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: mintGreen,
          foregroundColor: navyBlue,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        onPressed: _isSaving ? null : _finishCurrentExerciseAndContinue,
        icon: Icon(_isLastExercise ? Icons.check : Icons.skip_next),
        label: Text(
          _isSaving ? 'SAVING...' : (_isLastExercise ? 'FINISH' : 'NEXT'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingPermission) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: mintGreen),
        ),
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
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: neonRed.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.videocam_off, color: neonRed, size: 64),
                ),
                const SizedBox(height: 32),
                const Text(
                  "Camera Access Required",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "This mode records each exercise as a separate video.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 48),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mintGreen,
                    foregroundColor: navyBlue,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: openAppSettings,
                  child: const Text(
                    'OPEN SYSTEM SETTINGS',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isInitialized || _cameraController == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: mintGreen),
        ),
      );
    }

    return OrientationBuilder(
      builder: (context, orientation) {
        final isPortrait = orientation == Orientation.portrait;
        final rawRatio = _cameraController!.value.aspectRatio;
        final previewRatio = isPortrait ? 1 / rawRatio : rawRatio;
        final scale = _calculateScale(context, previewRatio);
        final currentExercise = _currentExercise;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;

            if (_phase == AiSessionPhase.recording ||
                _phase == AiSessionPhase.prepCountdown ||
                _phase == AiSessionPhase.restCountdown) {
              _pauseSession();
            }

            final shouldLeave = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: darkSlate,
                title: const Text(
                  'END SESSION?',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                content: const Text(
                  'Are you sure you want to leave this recording session?',
                  style: TextStyle(color: Colors.grey, height: 1.5),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child:
                        const Text('STAY', style: TextStyle(color: mintGreen)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: neonRed,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      'LEAVE',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );

            if (shouldLeave == true) {
              Navigator.pop(context);
            } else if (_phase == AiSessionPhase.paused) {
              _resumeSession();
            }
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                Transform.scale(
                  scale: scale,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: previewRatio,
                      child: CameraPreview(_cameraController!),
                    ),
                  ),
                ),
                _buildTransitionOverlay(),
                _buildSavingOverlay(),
                if (_phase == AiSessionPhase.recording &&
                    currentExercise != null) ...[
                  _buildTopOverlay(currentExercise),
                  _buildPauseButton(isPortrait),
                  _buildRecordingIndicator(),
                  _buildProgressPill(),
                  _buildTargetCircle(currentExercise, isPortrait),
                  _buildNextButton(isPortrait),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _cameraController?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }
}
