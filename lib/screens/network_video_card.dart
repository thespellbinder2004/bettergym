import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class NetworkVideoCard extends StatefulWidget {
  final String videoUrl;
  final String title;

  const NetworkVideoCard({
    super.key,
    required this.videoUrl,
    required this.title,
  });

  @override
  State<NetworkVideoCard> createState() => _NetworkVideoCardState();
}

class _NetworkVideoCardState extends State<NetworkVideoCard> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      _controller =
          VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await _controller!.initialize();
      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          if (_loading)
            const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_hasError ||
              _controller == null ||
              !_controller!.value.isInitialized)
            const SizedBox(
              height: 180,
              child: Center(
                child: Text(
                  "Could not load video",
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            )
          else
            Column(
              children: [
                AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: VideoPlayer(_controller!),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        setState(() {
                          if (_controller!.value.isPlaying) {
                            _controller!.pause();
                          } else {
                            _controller!.play();
                          }
                        });
                      },
                      icon: Icon(
                        _controller!.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                      ),
                    ),
                    Expanded(
                      child: VideoProgressIndicator(
                        _controller!,
                        allowScrubbing: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}
