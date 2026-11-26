import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'services/stream_service.dart';

class InternalPlayer extends StatefulWidget {
  final int tmdbId;
  final String title;
  final bool isTv;
  final int? season;
  final int? episode;

  const InternalPlayer({
    super.key,
    required this.tmdbId,
    required this.title,
    required this.isTv,
    this.season,
    this.episode,
  });

  @override
  State<InternalPlayer> createState() => _InternalPlayerState();
}

class _InternalPlayerState extends State<InternalPlayer> {
  static const Color _primeBlue = Color(0xFF00A8E1);
  static const Color _darkBg = Color(0xFF0F171E);

  late final Player _player;
  late final VideoController _controller;
  final FocusNode _playerFocusNode = FocusNode();

  final List<StreamLink> _servers = [];
  StreamSubscription<StreamLink>? _streamSub;
  int _activeServerIndex = -1;
  bool _isSearchingServers = true;
  bool _showControls = true;
  Timer? _hideTimer;
  BoxFit _videoFit = BoxFit.contain;

  bool _isPlaying = false;
  bool _isBuffering = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Brightness & Volume Swipe State
  double _brightness = 0.5;
  double _volume = 100.0;
  bool _isDraggingBrightness = false;
  bool _isDraggingVolume = false;
  bool _showSwipeIndicator = false;
  Timer? _indicatorTimer;

  @override
  void initState() {
    super.initState();
    _enterFullscreen();
    _initBrightness();

    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
      ),
    );
    _controller = VideoController(_player);

    _player.stream.playing.listen((v) {
      if (mounted) setState(() => _isPlaying = v);
    });
    _player.stream.buffering.listen((v) {
      if (mounted) setState(() => _isBuffering = v);
    });
    _player.stream.position.listen((v) {
      if (mounted) setState(() => _position = v);
    });
    _player.stream.duration.listen((v) {
      if (mounted) setState(() => _duration = v);
    });
    _player.stream.volume.listen((v) {
      if (mounted) _volume = v;
    });

    _startFetchingStreams();
    _resetHideTimer();
  }

  Future<void> _initBrightness() async {
    try {
      final current = await ScreenBrightness().application;
      if (mounted) {
        setState(() => _brightness = current.clamp(0.0, 1.0));
      }
    } catch (_) {}
  }

  void _enterFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _exitFullscreen() {
    try {
      ScreenBrightness().resetApplicationScreenBrightness();
    } catch (_) {}
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _startFetchingStreams() {
    _streamSub = StreamService.fetchStreams(
      tmdbId: widget.tmdbId,
      title: widget.title,
      isTv: widget.isTv,
      season: widget.season,
      episode: widget.episode,
    ).listen(
      (link) {
        if (!mounted) return;
        setState(() {
          _servers.add(link);
        });
        if (_activeServerIndex == -1) {
          _playServer(0);
        }
      },
      onDone: () {
        if (mounted) {
          setState(() => _isSearchingServers = false);
        }
      },
    );
  }

  Future<void> _playServer(int index) async {
    if (index < 0 || index >= _servers.length) return;
    final link = _servers[index];
    setState(() {
      _activeServerIndex = index;
      _isBuffering = true;
    });
    await _player.open(
      Media(link.url, httpHeaders: link.headers),
      play: true,
    );
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() => _showControls = !_showControls);
    if (_showControls) _resetHideTimer();
  }

  void _seekRelative(int seconds) {
    final target = _position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration && _duration > Duration.zero
            ? _duration
            : target);
    _player.seek(clamped);
    _resetHideTimer();
  }

  void _onVerticalDragStart(DragStartDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (details.globalPosition.dx < screenWidth / 2) {
      _isDraggingBrightness = true;
      _isDraggingVolume = false;
    } else {
      _isDraggingVolume = true;
      _isDraggingBrightness = false;
    }
    _indicatorTimer?.cancel();
    setState(() => _showSwipeIndicator = true);
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final delta = -details.delta.dy / 220;
    if (_isDraggingBrightness) {
      final newVal = (_brightness + delta).clamp(0.01, 1.0);
      setState(() => _brightness = newVal);
      try {
        ScreenBrightness().setApplicationScreenBrightness(newVal);
      } catch (_) {}
    } else if (_isDraggingVolume) {
      final newVal = (_volume + (delta * 100)).clamp(0.0, 100.0);
      setState(() => _volume = newVal);
      _player.setVolume(newVal);
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _indicatorTimer?.cancel();
    _indicatorTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _showSwipeIndicator = false;
          _isDraggingBrightness = false;
          _isDraggingVolume = false;
        });
      }
    });
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() => _showControls = true);
      _seekRelative(-10);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      setState(() => _showControls = true);
      _seekRelative(10);
    } else if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      _player.playOrPause();
      setState(() => _showControls = true);
      _resetHideTimer();
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      setState(() => _showControls = true);
      _resetHideTimer();
    } else if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  void _showServersSheet() {
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: _darkBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Available Servers',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (_isSearchingServers)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _primeBlue,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: _servers.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No servers found yet...',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _servers.length,
                        itemBuilder: (_, i) {
                          final s = _servers[i];
                          final isActive = i == _activeServerIndex;
                          return ListTile(
                            dense: true,
                            autofocus: i == 0,
                            focusColor: _primeBlue.withOpacity(0.35),
                            tileColor: isActive
                                ? _primeBlue.withOpacity(0.2)
                                : Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            leading: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _primeBlue,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                s.quality,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              s.providerName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              s.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                            trailing: isActive
                                ? const Icon(
                                    Icons.check_circle,
                                    color: _primeBlue,
                                  )
                                : const Icon(
                                    Icons.play_arrow,
                                    color: Colors.white70,
                                  ),
                            onTap: () {
                              Navigator.pop(ctx);
                              _playServer(i);
                              _resetHideTimer();
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTracksSheet() {
    _hideTimer?.cancel();
    final audioTracks = _player.state.tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    final subTracks = _player.state.tracks.subtitle
        .where((t) => t.id != 'auto')
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: _darkBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Audio',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: audioTracks.isEmpty
                            ? [
                                const Text(
                                  'Default Audio',
                                  style: TextStyle(color: Colors.white60),
                                )
                              ]
                            : audioTracks.map((t) {
                                final selected =
                                    _player.state.track.audio.id == t.id;
                                return ListTile(
                                  dense: true,
                                  focusColor: _primeBlue.withOpacity(0.35),
                                  title: Text(
                                    t.title ?? t.language ?? 'Track ${t.id}',
                                    style: TextStyle(
                                      color:
                                          selected ? _primeBlue : Colors.white,
                                    ),
                                  ),
                                  onTap: () {
                                    _player.setAudioTrack(t);
                                    Navigator.pop(ctx);
                                  },
                                );
                              }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Subtitles',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: subTracks.map((t) {
                          final selected =
                              _player.state.track.subtitle.id == t.id;
                          return ListTile(
                            dense: true,
                            focusColor: _primeBlue.withOpacity(0.35),
                            title: Text(
                              t.id == 'no'
                                  ? 'Off'
                                  : (t.title ?? t.language ?? 'Sub ${t.id}'),
                              style: TextStyle(
                                color: selected ? _primeBlue : Colors.white,
                              ),
                            ),
                            onTap: () {
                              _player.setSubtitleTrack(t);
                              Navigator.pop(ctx);
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _indicatorTimer?.cancel();
    _streamSub?.cancel();
    _playerFocusNode.dispose();
    _player.dispose();
    _exitFullscreen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayTitle = widget.isTv
        ? '${widget.title} • S${widget.season ?? 1}E${widget.episode ?? 1}'
        : widget.title;

    return Scaffold(
      backgroundColor: Colors.black,
      body: KeyboardListener(
        focusNode: _playerFocusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          onVerticalDragStart: _onVerticalDragStart,
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Native HD Video Surface
              Video(
                controller: _controller,
                fit: _videoFit,
                controls: NoVideoControls,
              ),

              // Brightness / Volume Swipe Indicator
              if (_showSwipeIndicator)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _primeBlue.withOpacity(0.6),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isDraggingBrightness
                              ? Icons.brightness_6
                              : (_volume <= 0
                                  ? Icons.volume_off
                                  : Icons.volume_up),
                          color: _primeBlue,
                          size: 26,
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 110,
                          child: LinearProgressIndicator(
                            value: _isDraggingBrightness
                                ? _brightness
                                : (_volume / 100.0),
                            backgroundColor: Colors.white24,
                            color: _primeBlue,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isDraggingBrightness
                              ? '${(_brightness * 100).round()}%'
                              : '${_volume.round()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Loading / No Server State
              if (_servers.isEmpty && _isSearchingServers)
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: _primeBlue),
                      SizedBox(height: 14),
                      Text(
                        'Connecting to fastest server...',
                        style: TextStyle(color: Colors.white, fontSize: 15),
                      ),
                    ],
                  ),
                )
              else if (_servers.isEmpty && !_isSearchingServers)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: _primeBlue, size: 48),
                      const SizedBox(height: 10),
                      const Text(
                        'No working stream found from your Gist providers.',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primeBlue,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Go Back'),
                      ),
                    ],
                  ),
                )
              else if (_isBuffering)
                const Center(
                  child: CircularProgressIndicator(color: _primeBlue),
                ),

              // PrimeFlix Controls Overlay
              if (_showControls)
                Container(
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
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Top Bar
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back,
                                    color: Colors.white),
                                onPressed: () => Navigator.pop(context),
                              ),
                              Expanded(
                                child: Text(
                                  displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _showServersSheet,
                                icon: const Icon(Icons.dns,
                                    color: _primeBlue, size: 18),
                                label: Text(
                                  'Servers (${_servers.length})',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Audio & Subtitles',
                                icon: const Icon(Icons.subtitles,
                                    color: Colors.white),
                                onPressed: _showTracksSheet,
                              ),
                              IconButton(
                                tooltip: 'Aspect Ratio',
                                icon: Icon(
                                  _videoFit == BoxFit.contain
                                      ? Icons.fit_screen
                                      : Icons.zoom_out_map,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _videoFit = _videoFit == BoxFit.contain
                                        ? BoxFit.cover
                                        : BoxFit.contain;
                                  });
                                },
                              ),
                            ],
                          ),

                          // Center Play/Pause & Seek
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                iconSize: 38,
                                icon: const Icon(Icons.replay_10,
                                    color: Colors.white),
                                onPressed: () => _seekRelative(-10),
                              ),
                              const SizedBox(width: 36),
                              IconButton(
                                iconSize: 56,
                                icon: Icon(
                                  _isPlaying
                                      ? Icons.pause_circle_filled
                                      : Icons.play_circle_filled,
                                  color: _primeBlue,
                                ),
                                onPressed: () {
                                  _player.playOrPause();
                                  _resetHideTimer();
                                },
                              ),
                              const SizedBox(width: 36),
                              IconButton(
                                iconSize: 38,
                                icon: const Icon(Icons.forward_10,
                                    color: Colors.white),
                                onPressed: () => _seekRelative(10),
                              ),
                            ],
                          ),

                          // Bottom Progress Bar
                          Row(
                            children: [
                              Text(
                                _formatDuration(_position),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: _primeBlue,
                                    inactiveTrackColor: Colors.white30,
                                    thumbColor: _primeBlue,
                                    trackHeight: 3.5,
                                  ),
                                  child: Slider(
                                    min: 0,
                                    max: _duration.inMilliseconds > 0
                                        ? _duration.inMilliseconds.toDouble()
                                        : 1,
                                    value: _position.inMilliseconds
                                        .clamp(
                                          0,
                                          _duration.inMilliseconds > 0
                                              ? _duration.inMilliseconds
                                              : 1,
                                        )
                                        .toDouble(),
                                    onChanged: (val) {
                                      _player.seek(
                                        Duration(milliseconds: val.toInt()),
                                      );
                                      _resetHideTimer();
                                    },
                                  ),
                                ),
                              ),
                              Text(
                                _formatDuration(_duration),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}