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

  final FocusNode _rootFocus = FocusNode();
  final FocusNode _playBtnFocus = FocusNode();
  final FocusNode _sliderFocus = FocusNode();

  final List<StreamLink> _servers = [];
  StreamSubscription<StreamLink>? _streamSub;
  int _activeServerIndex = -1;
  bool _isSearchingServers = true;
  bool _showControls = true;
  bool _isSliderFocused = false;
  Timer? _hideTimer;
  BoxFit _videoFit = BoxFit.contain;

  bool _isPlaying = false;
  bool _isBuffering = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Brightness & Volume (up to 200% Boost) Swipe State
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

    // 200% software volume boost enable karne ke liye
    if (_player.platform is NativePlayer) {
      (_player.platform as NativePlayer).setProperty('volume-max', '200');
    }

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
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
        _rootFocus.requestFocus();
      }
    });
  }

  void _showControlsAndFocus() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() => _showControls = true);
    _resetHideTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showControls) {
        _playBtnFocus.requestFocus();
      }
    });
  }

  void _toggleControls() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    final next = !_showControls;
    setState(() => _showControls = next);
    if (next) {
      _resetHideTimer();
    } else {
      _rootFocus.requestFocus();
    }
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
      final newVal = (_volume + (delta * 200)).clamp(0.0, 200.0);
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

  KeyEventResult _handleRootKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.mediaPlayPause) {
      _player.playOrPause();
      _showControlsAndFocus();
      return KeyEventResult.handled;
    }

    // Jab controls hidden hon tab TV remote direct seek aur controls open kare
    if (!_showControls) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _seekRelative(-10);
        _showControlsAndFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _seekRelative(10);
        _showControlsAndFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.space) {
        _player.playOrPause();
        _showControlsAndFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        _showControlsAndFocus();
        return KeyEventResult.handled;
      }
    } else {
      // Controls open hain: har remote press par auto-hide timer reset karo
      // aur normal D-pad navigation ko buttons par move hone do
      _resetHideTimer();
    }

    return KeyEventResult.ignored;
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
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _servers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final s = _servers[i];
                          final isActive = i == _activeServerIndex;
                          final shouldAutofocus =
                              _activeServerIndex >= 0
                                  ? i == _activeServerIndex
                                  : i == 0;
                          return _TvFocusableListItem(
                            autofocus: shouldAutofocus,
                            isActive: isActive,
                            quality: s.quality,
                            title: s.providerName,
                            subtitle: s.title,
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
                                  autofocus: selected,
                                  focusColor: _primeBlue.withOpacity(0.45),
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
                            focusColor: _primeBlue.withOpacity(0.45),
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
    _rootFocus.dispose();
    _playBtnFocus.dispose();
    _sliderFocus.dispose();
    _player.dispose();
    _exitFullscreen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayTitle = widget.isTv
        ? '${widget.title} • S${widget.season ?? 1}E${widget.episode ?? 1}'
        : widget.title;

    final isBoosted = _isDraggingVolume && _volume > 100.0;
    final indicatorColor = isBoosted ? Colors.orangeAccent : _primeBlue;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _rootFocus,
        autofocus: true,
        onKeyEvent: _handleRootKeyEvent,
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

              // Brightness / Volume (200% Boost) Swipe Indicator
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
                        color: indicatorColor.withOpacity(0.7),
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
                          color: indicatorColor,
                          size: 26,
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 110,
                          child: LinearProgressIndicator(
                            value: _isDraggingBrightness
                                ? _brightness
                                : (_volume / 200.0).clamp(0.0, 1.0),
                            backgroundColor: Colors.white24,
                            color: indicatorColor,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isDraggingBrightness
                              ? '${(_brightness * 100).round()}%'
                              : '${_volume.round()}%',
                          style: TextStyle(
                            color:
                                isBoosted ? Colors.orangeAccent : Colors.white,
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
                        autofocus: true,
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

              // PrimeFlix Controls Overlay (TV Remote + Touch Friendly)
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
                              _TvPlayerIconButton(
                                icon: Icons.arrow_back,
                                onPressed: () => Navigator.pop(context),
                              ),
                              const SizedBox(width: 8),
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
                              _TvPlayerTextButton(
                                icon: Icons.dns,
                                label: 'Servers (${_servers.length})',
                                onPressed: _showServersSheet,
                              ),
                              const SizedBox(width: 6),
                              _TvPlayerIconButton(
                                icon: Icons.subtitles,
                                onPressed: _showTracksSheet,
                              ),
                              const SizedBox(width: 6),
                              _TvPlayerIconButton(
                                icon: _videoFit == BoxFit.contain
                                    ? Icons.fit_screen
                                    : Icons.zoom_out_map,
                                onPressed: () {
                                  setState(() {
                                    _videoFit = _videoFit == BoxFit.contain
                                        ? BoxFit.cover
                                        : BoxFit.contain;
                                  });
                                  _resetHideTimer();
                                },
                              ),
                            ],
                          ),

                          // Center Play/Pause & Seek
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _TvPlayerIconButton(
                                icon: Icons.replay_10,
                                iconSize: 38,
                                onPressed: () => _seekRelative(-10),
                              ),
                              const SizedBox(width: 36),
                              _TvPlayerIconButton(
                                focusNode: _playBtnFocus,
                                autofocus: true,
                                icon: _isPlaying
                                    ? Icons.pause_circle_filled
                                    : Icons.play_circle_filled,
                                iconSize: 58,
                                iconColor: _primeBlue,
                                onPressed: () {
                                  _player.playOrPause();
                                  _resetHideTimer();
                                },
                              ),
                              const SizedBox(width: 36),
                              _TvPlayerIconButton(
                                icon: Icons.forward_10,
                                iconSize: 38,
                                onPressed: () => _seekRelative(10),
                              ),
                            ],
                          ),

                          // Bottom Progress Bar (TV Remote Left/Right Seek)
                          Focus(
                            focusNode: _sliderFocus,
                            onFocusChange: (f) {
                              if (mounted) {
                                setState(() => _isSliderFocused = f);
                              }
                            },
                            onKeyEvent: (node, event) {
                              if (event is KeyDownEvent ||
                                  event is KeyRepeatEvent) {
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowLeft) {
                                  _seekRelative(-15);
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowRight) {
                                  _seekRelative(15);
                                  return KeyEventResult.handled;
                                }
                              }
                              return KeyEventResult.ignored;
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _isSliderFocused
                                    ? _primeBlue.withOpacity(0.18)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _isSliderFocused
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    _formatDuration(_position),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Expanded(
                                    child: ExcludeFocus(
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          activeTrackColor: _primeBlue,
                                          inactiveTrackColor: Colors.white30,
                                          thumbColor: _isSliderFocused
                                              ? Colors.white
                                              : _primeBlue,
                                          trackHeight:
                                              _isSliderFocused ? 5.5 : 3.5,
                                        ),
                                        child: Slider(
                                          min: 0,
                                          max: _duration.inMilliseconds > 0
                                              ? _duration.inMilliseconds
                                                  .toDouble()
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
                                              Duration(
                                                milliseconds: val.toInt(),
                                              ),
                                            );
                                            _resetHideTimer();
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _formatDuration(_duration),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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

class _TvPlayerIconButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final Color iconColor;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool autofocus;

  const _TvPlayerIconButton({
    required this.icon,
    required this.onPressed,
    this.iconSize = 26,
    this.iconColor = Colors.white,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<_TvPlayerIconButton> createState() => _TvPlayerIconButtonState();
}

class _TvPlayerIconButtonState extends State<_TvPlayerIconButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        if (mounted) setState(() => _focused = f);
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(40),
        onTap: widget.onPressed,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _focused ? Colors.white.withOpacity(0.22) : Colors.transparent,
            border: Border.all(
              color: _focused ? Colors.white : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: widget.iconColor,
          ),
        ),
      ),
    );
  }
}

class _TvPlayerTextButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _TvPlayerTextButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  State<_TvPlayerTextButton> createState() => _TvPlayerTextButtonState();
}

class _TvPlayerTextButtonState extends State<_TvPlayerTextButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) {
        if (mounted) setState(() => _focused = f);
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: widget.onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _focused
                ? const Color(0xFF00A8E1)
                : Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                color: _focused ? Colors.white : const Color(0xFF00A8E1),
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
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
    );
  }
}

class _TvFocusableListItem extends StatefulWidget {
  final bool autofocus;
  final bool isActive;
  final String quality;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _TvFocusableListItem({
    required this.autofocus,
    required this.isActive,
    required this.quality,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_TvFocusableListItem> createState() => _TvFocusableListItemState();
}

class _TvFocusableListItemState extends State<_TvFocusableListItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        if (mounted) setState(() => _focused = f);
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _focused
                ? const Color(0xFF00A8E1).withOpacity(0.3)
                : (widget.isActive
                    ? const Color(0xFF00A8E1).withOpacity(0.14)
                    : const Color(0xFF1A242F)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A8E1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.quality,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                widget.isActive ? Icons.check_circle : Icons.play_arrow,
                color: widget.isActive
                    ? const Color(0xFF00A8E1)
                    : Colors.white70,
              ),
            ],
          ),
        ),
      ),
    );
  }
}