import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioService {
  static final AudioService instance = AudioService._internal();
  AudioService._internal();

  final AudioPlayer _chimePlayer = AudioPlayer();
  final AudioPlayer _tickPlayer = AudioPlayer();
  final AudioPlayer _beepPlayer = AudioPlayer();
  final AudioPlayer _uiPlayer = AudioPlayer(); // NEW: Dedicated UI Channel

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

    await _chimePlayer.setVolume(_volume);
    await _tickPlayer.setVolume(_volume);
    await _beepPlayer.setVolume(_volume);
    await _uiPlayer.setVolume(_volume); // NEW
  }

  Future<void> _playOnChannel(AudioPlayer channel, String fileName) async {
    if (!_masterSoundEnabled) return; 
    
    if (channel.state == PlayerState.playing) {
      await channel.stop();
    }
    
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

  // --- NEW: UI SOUND TRIGGERS ---
  void playPauseSound() {
    _playOnChannel(_uiPlayer, 'pause.mp3');
  }

  void playResumeSound() {
    _playOnChannel(_uiPlayer, 'resume.mp3');
  }

  void playFinishSound() {
    _playOnChannel(_uiPlayer, 'finish.mp3');
  }

  void playAbortSound() {
    _playOnChannel(_uiPlayer, 'abort.mp3');
  }
}