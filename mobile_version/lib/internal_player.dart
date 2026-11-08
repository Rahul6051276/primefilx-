// ============================================================================
// INTERNAL VIDEO PLAYER (WITH FULL INTERACTIVE SEEK SLIDER + CROP + LOCK)
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
  }) : streamUrl = (streamUrl != null && streamUrl.isNotEmpty)
            ? streamUrl
            : (videoUrl ?? '');

  @override
  State<InternalPlayerScreen> createState() => _InternalPlayerScreenState();
}

class _InternalPlayerScreenState extends State<InternalPlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInit = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _showControls = true;
  Timer? _controlsTimer;

  // Screen Lock State
  bool _isLocked = false;
  bool _showUnlockButton = false;
  Timer? _unlockTimer;

  // Gesture Controls (Volume & Brightness)
  double _volume = 1.0;
  double _brightness = 0.5;
  String _overlayText = '';
  IconData _overlayIcon = Icons.volume_up_rounded;
  bool _showOverlayIndicator = false;
  Timer? _overlayTimer;

  // 0: FIT (16:9), 1: FILL (Stretch), 2: CROP (Zoom / Notch-fill default)
  int _scaleMode = 2;

  // Seeking State
  bool _isDraggingSlider = false;
  double _dragValue = 0.0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.streamUrl),
        httpHeaders: const {
          'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18 (Linux; Android 13)',
          'Accept': '*/*',
          'Connection': 'keep-alive',
          'Icy-MetaData': '1',
        },
      );

      await _controller.initialize();
      _controller.setVolume(_volume);
      _controller.play();
      _startHideTimer();

      if (mounted) {
        setState(() => _isInit = true);
      }

      _controller.addListener(() {
        if (mounted && !_isDraggingSlider) setState(() {});
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _startHideTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller.value.isPlaying && !_isDraggingSlider) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    if (_isLocked) {
      setState(() => _showUnlockButton = !_showUnlockButton);
      if (_showUnlockButton) {
        _unlockTimer?.cancel();
        _unlockTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _showUnlockButton = false);
        });
      }
      return;
    }

    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  void _togglePlayPause() {
    if (!_isInit || _isLocked) return;
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
      _showControls = true;
    });
    _startHideTimer();
  }

  void _seekRelative(int seconds) {
    if (!_isInit || _isLocked) return;
    final currentPos = _controller.value.position;
    final totalDur = _controller.value.duration;

    var newPos = currentPos + Duration(seconds: seconds);
    if (newPos < Duration.zero) newPos = Duration.zero;
    if (totalDur > Duration.zero && newPos > totalDur) newPos = totalDur;

    _controller.seekTo(newPos);
    _startHideTimer();
  }

  void _cycleScaleMode() {
    if (_isLocked) return;
    setState(() {
      _scaleMode = (_scaleMode + 1) % 3;
      _showControls = true;
    });
    _startHideTimer();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, double screenWidth, double screenHeight) {
    if (_isLocked) return;

    final delta = -details.primaryDelta! / (screenHeight * 0.75);

    if (details.localPosition.dx < screenWidth / 2) {
      // Left Screen: Brightness
      setState(() {
        _brightness = (_brightness + delta).clamp(0.0, 1.0);
        _overlayText = '${(_brightness * 100).toInt()}%';
        _overlayIcon = Icons.brightness_6_rounded;
        _showOverlayIndicator = true;
      });
    } else {
      // Right Screen: Volume
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
    _unlockTimer?.cancel();
    _controller.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Widget _buildVideoOutput() {
    if (!_isInit) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1E88E5)),
      );
    }

    if (_scaleMode == 1) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: _controller.value.size.width,
            height: _controller.value.size.height,
            child: VideoPlayer(_controller),
          ),
        ),
      );
    } else if (_scaleMode == 2) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller.value.size.width,
            height: _controller.value.size.height,
            child: VideoPlayer(_controller),
          ),
        ),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: VideoPlayer(_controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scaleNames = ['FIT (16:9)', 'FILL (STRETCH)', 'CROP (ZOOM)'];
    final size = MediaQuery.of(context).size;

    final Duration totalDur = _isInit ? _controller.value.duration : Duration.zero;
    final Duration currentPos = _isInit ? _controller.value.position : Duration.zero;

    final double maxMs = totalDur.inMilliseconds > 0 ? totalDur.inMilliseconds.toDouble() : 1.0;
    final double currentMs = _isDraggingSlider
        ? _dragValue
        : currentPos.inMilliseconds.toDouble().clamp(0.0, maxMs);

    final Duration displayPos = _isDraggingSlider
        ? Duration(milliseconds: _dragValue.toInt())
        : currentPos;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        alignment: Alignment.center,
        children: [
          _buildVideoOutput(),

          if (_isInit && _controller.value.isBuffering)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF1E88E5)),
            ),

          IgnorePointer(
            child: Container(
              color: Colors.black.withOpacity((1.0 - _brightness) * 0.75),
            ),
          ),

          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            onVerticalDragUpdate: (details) => _onVerticalDragUpdate(details, size.width, size.height),
            child: Container(color: Colors.transparent),
          ),

          if (_showOverlayIndicator && !_isLocked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF0C111B).withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF1E88E5).withOpacity(0.5), width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_overlayIcon, color: const Color(0xFF1E88E5), size: 28),
                  const SizedBox(width: 10),
                  Text(
                    _overlayText,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

          if (_hasError)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C111B).withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.6), width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 10),
                    const Text(
                      'Stream load nahi ho saki',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

          if (_isLocked && _showUnlockButton)
            Positioned(
              left: 24,
              top: 24,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _isLocked = false;
                    _showUnlockButton = false;
                    _showControls = true;
                  });
                  _startHideTimer();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(color: const Color(0xFF1E88E5), width: 1.5),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_open_rounded, color: Color(0xFF1E88E5), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Unlock Screen',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (_showControls && _isInit && !_isLocked)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black87,
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black87,
                  ],
                  stops: [0.0, 0.22, 0.72, 1.0],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 18,
                    left: 24,
                    right: 24,
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white12),
                            ),
                            child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isLocked = true;
                              _showControls = false;
                              _showUnlockButton = true;
                            });
                            _unlockTimer?.cancel();
                            _unlockTimer = Timer(const Duration(seconds: 3), () {
                              if (mounted) setState(() => _showUnlockButton = false);
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 10),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161922).withOpacity(0.9),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24, width: 1.2),
                            ),
                            child: const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 18),
                          ),
                        ),
                        GestureDetector(
                          onTap: _cycleScaleMode,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161922).withOpacity(0.9),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF1E88E5), width: 1.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.aspect_ratio_rounded, color: Color(0xFF1E88E5), size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  scaleNames[_scaleMode],
                                  style: const TextStyle(
                                    color: Color(0xFF1E88E5),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
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
                        GestureDetector(
                          onTap: () => _seekRelative(-30),
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black45,
                              border: Border.all(color: Colors.white24, width: 1.5),
                            ),
                            child: const Icon(
                              Icons.replay_30_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                        const SizedBox(width: 40),
                        GestureDetector(
                          onTap: _togglePlayPause,
                          child: Container(
                            width: 65,
                            height: 65,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF1E88E5).withOpacity(0.85),
                              border: Border.all(color: Colors.white24, width: 2),
                            ),
                            child: Icon(
                              _controller.value.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 42,
                            ),
                          ),
                        ),
                        const SizedBox(width: 40),
                        GestureDetector(
                          onTap: () => _seekRelative(30),
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black45,
                              border: Border.all(color: Colors.white24, width: 1.5),
                            ),
                            child: const Icon(
                              Icons.forward_30_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bottom Bar: Progress Bar + Time
                  Positioned(
                    bottom: 12,
                    left: 20,
                    right: 20,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (totalDur.inMilliseconds > 0)
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3.5,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                              activeTrackColor: const Color(0xFF1E88E5),
                              inactiveTrackColor: Colors.white24,
                              thumbColor: const Color(0xFF38BDF8),
                              overlayColor: const Color(0xFF1E88E5).withOpacity(0.2),
                            ),
                            child: Slider(
                              value: currentMs,
                              min: 0.0,
                              max: maxMs,
                              onChangeStart: (val) {
                                _isDraggingSlider = true;
                                _dragValue = val;
                                _controlsTimer?.cancel();
                              },
                              onChanged: (val) {
                                setState(() {
                                  _dragValue = val;
                                });
                              },
                              onChangeEnd: (val) {
                                _isDraggingSlider = false;
                                _controller.seekTo(Duration(milliseconds: val.toInt()));
                                _startHideTimer();
                              },
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(displayPos),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                totalDur.inMilliseconds > 0 ? _formatDuration(totalDur) : 'LIVE',
                                style: TextStyle(
                                  color: totalDur.inMilliseconds > 0 ? Colors.white70 : const Color(0xFFE50914),
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
