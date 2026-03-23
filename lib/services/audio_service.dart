import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioService {
  static final AudioService instance = AudioService._internal();
  AudioService._internal();

  bool _masterSoundEnabled = true;
  bool _leadInBeepsEnabled = true;
  bool _repChimeEnabled = true;     // NEW
  bool _metronomeEnabled = true;    // NEW
  double _volume = 0.5;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _masterSoundEnabled = prefs.getBool('master_sound') ?? true;
    _leadInBeepsEnabled = prefs.getBool('leadin_beeps') ?? true;
    _repChimeEnabled = prefs.getBool('rep_chime') ?? true;       // NEW
    _metronomeEnabled = prefs.getBool('metronome') ?? true;      // NEW
    _volume = prefs.getDouble('audio_volume') ?? 0.5;
  }

  Future<void> _playSound(String fileName) async {
    if (!_masterSoundEnabled) return; // Ultimate override
    
    final player = AudioPlayer();
    await player.setVolume(_volume);
    
    player.onPlayerComplete.listen((_) => player.dispose());
    await player.play(AssetSource('sounds/$fileName'));
  }

  void playChime() {
    if (_repChimeEnabled) _playSound('chime.mp3');
  }

  void playTick() {
    if (_metronomeEnabled) _playSound('tick.mp3');
  }
  
  void playLeadInBeep() {
    if (_leadInBeepsEnabled) _playSound('beep.mp3');
  }

  void playGoBeep() {
    if (_leadInBeepsEnabled) _playSound('go.mp3');
  }
}