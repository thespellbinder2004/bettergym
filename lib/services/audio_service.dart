import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // Required for Haptics
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioService {
  // Singleton pattern
  static final AudioService instance = AudioService._internal();
  AudioService._internal();

  // --- Core Engines ---
  final FlutterTts _tts = FlutterTts();
  final Random _random = Random();

  // Persistent Audio Channels (Prevents memory leaks from spawning new players)
  final AudioPlayer _chimePlayer = AudioPlayer();
  final AudioPlayer _tickPlayer = AudioPlayer();
  final AudioPlayer _beepPlayer = AudioPlayer();
  final AudioPlayer _uiPlayer = AudioPlayer();

  // --- State Tracking ---
  bool _masterSoundEnabled = true;
  double _feedbackVolume = 1.0;
  double _beepsVolume = 1.0;
  
  // Anti-Spam Tracking
  bool _isSpeaking = false;
  DateTime _lastSpokenTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _cooldownSeconds = 4;
  String _lastSpokenPhrase = "";

  /// Initializes volumes and lifecycle hooks
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _masterSoundEnabled = prefs.getBool('master_sound') ?? true;
    _feedbackVolume = prefs.getDouble('feedback_volume') ?? 1.0;
    _beepsVolume = prefs.getDouble('beeps_volume') ?? 1.0;

    // Apply SFX Volumes
    await _chimePlayer.setVolume(_beepsVolume);
    await _tickPlayer.setVolume(_beepsVolume);
    await _beepPlayer.setVolume(_beepsVolume);
    await _uiPlayer.setVolume(_beepsVolume);

    // Apply TTS Volumes & Configuration
    await _tts.setVolume(_feedbackVolume);
    await _tts.setSpeechRate(0.5); // Natural coaching pace
    await _tts.setPitch(1.0);

    // TTS Lifecycle Hooks for precise state tracking
    _tts.setStartHandler(() => _isSpeaking = true);
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      _lastSpokenTime = DateTime.now(); // Clock starts when silence begins
    });
    _tts.setErrorHandler((msg) => _isSpeaking = false);
    _tts.setCancelHandler(() => _isSpeaking = false);
  }

  // ==========================================
  // CHANNEL 1: TEXT-TO-SPEECH (FEEDBACK)
  // ==========================================

  /// Priority messages (Setup, Rest) stop current audio and bypass the cooldown.
  Future<void> speakPriority(List<String> variations) async {
    if (!_masterSoundEnabled || _feedbackVolume <= 0.0) return;
    
    await _tts.stop(); 
    await _tts.setVolume(_feedbackVolume);

    final phrase = _getUniquePhrase(variations);
    await _tts.speak(phrase);
    
    // We don't update _lastSpokenTime here because the completion handler does it.
  }

  /// Correction messages (Form breaks) strictly obey the 4-second cooldown AND haptics.
  Future<void> speakCorrection(List<String> variations) async {
    if (!_masterSoundEnabled || _feedbackVolume <= 0.0 || _isSpeaking) return;

    final now = DateTime.now();
    if (now.difference(_lastSpokenTime).inSeconds >= _cooldownSeconds) {
      
      final phrase = _getUniquePhrase(variations);
      
      // Physical interrupt for users with music playing
      HapticFeedback.heavyImpact(); 
      
      await _tts.setVolume(_feedbackVolume);
      await _tts.speak(phrase);
    }
  }

  /// Ensures we don't repeat the exact same nagging phrase twice in a row.
  String _getUniquePhrase(List<String> variations) {
    if (variations.isEmpty) return "";
    if (variations.length == 1) return variations.first;

    String phrase;
    do {
      phrase = variations[_random.nextInt(variations.length)];
    } while (phrase == _lastSpokenPhrase);
    
    _lastSpokenPhrase = phrase;
    return phrase;
  }

  // ==========================================
  // CHANNEL 2: SOUND EFFECTS (BEEPS)
  // ==========================================

  /// Reuses existing memory channels instead of creating new instances.
  Future<void> _playOnChannel(AudioPlayer channel, String assetPath) async {
    if (!_masterSoundEnabled || _beepsVolume <= 0.0) return; 
    
    if (channel.state == PlayerState.playing) {
      await channel.stop(); // Cut off the old sound if it's still trailing
    }
    
    try {
      await channel.play(AssetSource(assetPath));
    } catch (e) {
      debugPrint("AudioSFX Error: Could not play $assetPath - $e");
    }
  }

  // --- STANDARD WORKOUT SFX ---
  void playTick() => _playOnChannel(_tickPlayer, 'sounds/tick.mp3');
  void playChime() => _playOnChannel(_chimePlayer, 'sounds/chime.mp3');
  void playLeadInBeep() => _playOnChannel(_beepPlayer, 'sounds/beep_low.mp3');
  void playGoBeep() => _playOnChannel(_beepPlayer, 'sounds/beep_high.mp3');

  // --- SYSTEM SFX ---
  void playPauseSound() => _playOnChannel(_uiPlayer, 'sounds/pause.mp3');
  void playResumeSound() => _playOnChannel(_uiPlayer, 'sounds/resume.mp3');
  void playAbortSound() => _playOnChannel(_uiPlayer, 'sounds/abort.mp3');
  void playFinishSound() => _playOnChannel(_uiPlayer, 'sounds/finish.mp3');
}