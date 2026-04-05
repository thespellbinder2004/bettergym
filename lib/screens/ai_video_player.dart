import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class AiVideoPlayerPage extends StatefulWidget {
  final String videoUrl;
  final String title;

  const AiVideoPlayerPage({
    super.key,
    required this.videoUrl,
    required this.title,
  });

  @override
  State<AiVideoPlayerPage> createState() => _AiVideoPlayerPageState();
}

class _AiVideoPlayerPageState extends State<AiVideoPlayerPage> {
  late VideoPlayerController _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {
          _loading = false;
        });
      }).catchError((e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      "Failed to load video:\n$_error",
                      textAlign: TextAlign.center,
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: _controller.value.aspectRatio == 0
                            ? 16 / 9
                            : _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      ),
                      const SizedBox(height: 16),
                      IconButton(
                        iconSize: 40,
                        icon: Icon(
                          _controller.value.isPlaying
                              ? Icons.pause_circle
                              : Icons.play_circle,
                        ),
                        onPressed: _togglePlayPause,
                      ),
                    ],
                  ),
      ),
    );
  }
}
