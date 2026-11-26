import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
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
  late final Player _player;
  late final VideoController _controller;

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

  @override
  void initState() {
    super.initState();
    _enterFullscreen();

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

    _startFetchingStreams();
    _resetHideTimer();
  }

  void _enterFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _exitFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
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
        // Pehla link milte hi turant auto-play
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
    setState(() => _showControls = !_showControls);
    if (_showControls) _resetHideTimer();
  }

  void _seekRelative(int seconds) {
    final target = _position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration && _duration > Duration.zero ? _duration : target);
    _player.seek(clamped);
    _resetHideTimer();
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
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
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
                            color: Color(0xFFE50914),
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
                                tileColor: isActive
                                    ? const Color(0xFFE50914).withOpacity(0.18)
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
                                    color: const Color(0xFFE50914),
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
                                        color: Color(0xFFE50914),
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
      backgroundColor: const Color(0xFF141414),
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
                                  title: Text(
                                    t.title ?? t.language ?? 'Track ${t.id}',
                                    style: TextStyle(
                                      color: selected
                                          ? const Color(0xFFE50914)
                                          : Colors.white,
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
                            title: Text(
                              t.id == 'no'
                                  ? 'Off'
                                  : (t.title ?? t.language ?? 'Sub ${t.id}'),
                              style: TextStyle(
                                color: selected
                                    ? const Color(0xFFE50914)
                                    : Colors.white,
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
    _streamSub?.cancel();
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
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Native HD Video Surface
            Video(
              controller: _controller,
              fit: _videoFit,
              controls: NoVideoControls,
            ),

            // Loading / No Server State
            if (_servers.isEmpty && _isSearchingServers)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFFE50914)),
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
                        color: Color(0xFFE50914), size: 48),
                    const SizedBox(height: 10),
                    const Text(
                      'No working stream found from your Gist providers.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE50914),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Go Back'),
                    ),
                  ],
                ),
              )
            else if (_isBuffering)
              const Center(
                child: CircularProgressIndicator(color: Color(0xFFE50914)),
              ),

            // Netflix-Style Controls Overlay
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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top Bar
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
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
                                  color: Colors.white, size: 18),
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
                              color: Colors.white,
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
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
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
                                  activeTrackColor: const Color(0xFFE50914),
                                  inactiveTrackColor: Colors.white30,
                                  thumbColor: const Color(0xFFE50914),
                                  trackHeight: 3,
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
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}