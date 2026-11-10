// ============================================================================
// INTERNAL VIDEO PLAYER (TV REMOTE D-PAD + FULL LANDSCAPE FIX + GESTURES + CROP)
// ============================================================================
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class InternalPlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;

  InternalPlayerScreen({
    super.key,
    String? videoUrl,
    String? streamUrl,
    required this.title,
  }) : streamUrl = (streamUrl != null && streamUrl.isNotEmpty) ? streamUrl : (videoUrl ?? '');

  @override
  State<InternalPlayerScreen> createState() => _InternalPlayerScreenState();
}

class _InternalPlayerScreenState extends State<InternalPlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInit = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _showControls = true;
  bool _isLocked = false;
  Timer? _controlsTimer;

  double _volume = 1.0;
  double _brightness = 0.5;
  String _overlayText = '';
  IconData _overlayIcon = Icons.volume_up_rounded;
  bool _showOverlayIndicator = false;
  Timer? _overlayTimer;

  int _scaleMode = 2;
  final FocusNode _playerFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.streamUrl),
        httpHeaders: const {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': '*/*',
          'Connection': 'keep-alive',
        },
      );

      await _controller.initialize();
      _controller.setVolume(_volume);
      _controller.play();

      if (mounted) {
        setState(() => _isInit = true);
        _startHideTimer();
        _playerFocusNode.requestFocus();
      }

      _controller.addListener(() { if (mounted) setState(() {}); });
    } catch (e) {
      if (mounted) setState(() { _hasError = true; _errorMessage = e.toString(); });
    }
  }

  void _startHideTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller.value.isPlaying && !_isLocked) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      if (_isLocked) {
        _controlsTimer?.cancel();
        _controlsTimer = Timer(const Duration(seconds: 3), () {
          if (mounted && _isLocked) setState(() => _showControls = false);
        });
      } else {
        _startHideTimer();
      }
    }
  }

  void _togglePlayPause() {
    if (!_isInit || _isLocked) return;
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
      _showControls = true;
    });
    if (_controller.value.isPlaying) _startHideTimer();
  }

  void _seekRelative(int seconds) {
    if (!_isInit || _isLocked) return;
    final currentPos = _controller.value.position;
    final totalDur = _controller.value.duration;

    var newPos = currentPos + Duration(seconds: seconds);
    if (newPos < Duration.zero) newPos = Duration.zero;
    if (newPos > totalDur) newPos = totalDur;

    _controller.seekTo(newPos);

    setState(() {
      _overlayText = seconds > 0 ? '+$seconds s' : '$seconds s';
      _overlayIcon = seconds > 0 ? Icons.forward_30_rounded : Icons.replay_30_rounded;
      _showOverlayIndicator = true;
      _showControls = true;
    });

    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _showOverlayIndicator = false);
    });

    _startHideTimer();
  }

  void _cycleScaleMode() {
    if (_isLocked) return;
    setState(() { _scaleMode = (_scaleMode + 1) % 3; _showControls = true; });
    _startHideTimer();
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      if (_isLocked) {
        _controlsTimer?.cancel();
        _controlsTimer = Timer(const Duration(seconds: 2), () {
          if (mounted && _isLocked) setState(() => _showControls = false);
        });
      } else {
        _showControls = true;
        _startHideTimer();
      }
    });
  }

  KeyEventResult _handleTvRemoteKeys(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA || key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay || key == LogicalKeyboardKey.mediaPause) {
      _togglePlayPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.mediaFastForward || key == LogicalKeyboardKey.mediaTrackNext) {
      _seekRelative(30);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.mediaRewind || key == LogicalKeyboardKey.mediaTrackPrevious) {
      _seekRelative(-30);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      _toggleControls();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, double screenWidth, double screenHeight) {
    if (_isLocked) return;
    final delta = -details.primaryDelta! / (screenHeight * 0.75);
    if (details.localPosition.dx < screenWidth / 2) {
      setState(() {
        _brightness = (_brightness + delta).clamp(0.05, 1.0);
        _overlayText = '${(_brightness * 100).toInt()}%';
        _overlayIcon = Icons.brightness_6_rounded;
        _showOverlayIndicator = true;
      });
    } else {
      setState(() {
        _volume = (_volume + delta).clamp(0.0, 1.0);
        _controller.setVolume(_volume);
        _overlayText = '${(_volume * 100).toInt()}%';
        _overlayIcon = _volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded;
        _showOverlayIndicator = true;
      });
    }
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _showOverlayIndicator = false);
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _overlayTimer?.cancel();
    _playerFocusNode.dispose();
    _controller.dispose();

    // TV SCREEN FULL LANDSCAPE FIX (TV par kabhi vertical/mobile mode me nahi jayega)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Widget _buildVideoOutput() {
    if (!_isInit) return const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)));

    if (_scaleMode == 1) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(width: _controller.value.size.width, height: _controller.value.size.height, child: VideoPlayer(_controller)),
        ),
      );
    } else if (_scaleMode == 2) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(width: _controller.value.size.width, height: _controller.value.size.height, child: VideoPlayer(_controller)),
        ),
      );
    }

    return Center(
      child: AspectRatio(aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scaleNames = ['FIT (16:9)', 'FILL (STRETCH)', 'CROP (ZOOM)'];
    final size = MediaQuery.of(context).size;

    return Focus(
      focusNode: _playerFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) => _handleTvRemoteKeys(event),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildVideoOutput(),
            IgnorePointer(child: Container(color: Colors.black.withOpacity((1.0 - _brightness) * 0.8))),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              onVerticalDragUpdate: (details) => _onVerticalDragUpdate(details, size.width, size.height),
              child: Container(color: Colors.transparent),
            ),
            if (_showOverlayIndicator)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF181818).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE50914).withOpacity(0.5), width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_overlayIcon, color: const Color(0xFFE50914), size: 28),
                      const SizedBox(width: 10),
                      Text(_overlayText, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            if (_showControls && _isInit && !_isLocked)
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent, Colors.transparent, Colors.black87],
                    stops: [0.0, 0.22, 0.72, 1.0],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 20, left: 20, right: 20,
                      child: Row(
                        children: [
                          InkWell(
                            onTap: () => Navigator.pop(context),
                            child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle, border: Border.all(color: Colors.white24)), child: const Icon(Icons.arrow_back, color: Colors.white, size: 22)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                          InkWell(
                            onTap: _cycleScaleMode,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(color: const Color(0xFF181818).withOpacity(0.9), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE50914), width: 1.5)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.aspect_ratio, color: Color(0xFFE50914), size: 18),
                                  const SizedBox(width: 6),
                                  Text(scaleNames[_scaleMode], style: const TextStyle(color: Color(0xFFE50914), fontWeight: FontWeight.bold, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          InkWell(
                            onTap: () => _seekRelative(-30),
                            child: Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black45, border: Border.all(color: Colors.white24, width: 1.5)), child: const Icon(Icons.replay_30, color: Colors.white, size: 34)),
                          ),
                          const SizedBox(width: 44),
                          InkWell(
                            onTap: _togglePlayPause,
                            child: Container(width: 68, height: 68, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFE50914), border: Border.all(color: Colors.white30, width: 2)), child: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 42)),
                          ),
                          const SizedBox(width: 44),
                          InkWell(
                            onTap: () => _seekRelative(30),
                            child: Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black45, border: Border.all(color: Colors.white24, width: 1.5)), child: const Icon(Icons.forward_30, color: Colors.white, size: 34)),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      bottom: 16, left: 24, right: 24,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          VideoProgressIndicator(_controller, allowScrubbing: true, padding: const EdgeInsets.symmetric(vertical: 8), colors: const VideoProgressColors(playedColor: Color(0xFFE50914), bufferedColor: Colors.white38, backgroundColor: Colors.white12)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatDuration(_controller.value.position), style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                              Text(_formatDuration(_controller.value.duration), style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (_showControls && _isInit)
              Positioned(
                left: 20, top: size.height / 2 - 25,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleLock,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: _isLocked ? const Color(0xFFE50914) : Colors.black54, shape: BoxShape.circle, border: Border.all(color: _isLocked ? Colors.white : Colors.white38, width: 1.5)),
                    child: Icon(_isLocked ? Icons.lock : Icons.lock_open, color: Colors.white, size: 24),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
