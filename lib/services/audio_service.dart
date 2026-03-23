import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioService {
  static final AudioService instance = AudioService._internal();
  AudioService._internal();

  // NEW: Dedicated, permanent audio channels to prevent memory leaks
  final AudioPlayer _chimePlayer = AudioPlayer();
  final AudioPlayer _tickPlayer = AudioPlayer();
  final AudioPlayer _beepPlayer = AudioPlayer();

  bool _masterSoundEnabled = true;
  bool _leadInBeepsEnabled = true;
  bool _repChimeEnabled = true;     
  bool _metronomeEnabled = true;    
  double _volume = 0.5;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _masterSoundEnabled = prefs.getBool('master_sound') ?? true;
    _leadInBeepsEnabled = prefs.getBool('leadin_beeps') ?? true;
    _repChimeEnabled = prefs.getBool('rep_chime') ?? true;       
    _metronomeEnabled = prefs.getBool('metronome') ?? true;      
    _volume = prefs.getDouble('audio_volume') ?? 0.5;

    // Pre-apply volume to all dedicated channels
    await _chimePlayer.setVolume(_volume);
    await _tickPlayer.setVolume(_volume);
    await _beepPlayer.setVolume(_volume);
  }

  Future<void> _playOnChannel(AudioPlayer channel, String fileName) async {
    if (!_masterSoundEnabled) return; 
    
    // If the channel is already playing a sound, stop it to prevent overlap clipping
    if (channel.state == PlayerState.playing) {
      await channel.stop();
    }
    
    // Reuse the same memory address to play the sound
    await channel.play(AssetSource('sounds/$fileName'));
  }

  void playChime() {
    if (_repChimeEnabled) _playOnChannel(_chimePlayer, 'chime.mp3');
  }

  void playTick() {
    if (_metronomeEnabled) _playOnChannel(_tickPlayer, 'tick.mp3');
  }
  
  void playLeadInBeep() {
    if (_leadInBeepsEnabled) _playOnChannel(_beepPlayer, 'beep.mp3');
  }

  void playGoBeep() {
    if (_leadInBeepsEnabled) _playOnChannel(_beepPlayer, 'go.mp3');
  }
}