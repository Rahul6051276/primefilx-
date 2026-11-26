import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/native_media3_player.dart';
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

  final List<StreamLink> _servers = [];
  StreamSubscription<StreamLink>? _streamSub;
  bool _isSearching = true;
  bool _launchedNative = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _fetchAndLaunchNative();
  }

  List> _serializeServers() {
    return _servers
        .map(
          (s) => {
            'url': s.url,
            'title': s.title,
            'providerName': s.providerName,
            'quality': s.quality,
            'headers': s.headers,
          },
        )
        .toList();
  }

  Future<void> _openNativeWithCurrentServers() async {
    if (_servers.isEmpty || _launchedNative || !mounted) return;
    _launchedNative = true;

    final displayTitle = widget.isTv
        ? '${widget.title} • S${widget.season ?? 1}E${widget.episode ?? 1}'
        : widget.title;

    final first = _servers.first;
    final ok = await NativeMedia3Player.play(
      url: first.url,
      title: displayTitle,
      headers: first.headers,
      servers: _serializeServers(),
    );

    if (!mounted) return;
    if (!ok) {
      setState(() {
        _launchedNative = false;
        _statusMessage = 'Native Media3 player start nahi ho saka.';
      });
      return;
    }

    Navigator.of(context).pop();
  }

  void _fetchAndLaunchNative() {
    setState(() {
      _isSearching = true;
      _statusMessage = null;
    });

    _streamSub = StreamService.fetchStreams(
      tmdbId: widget.tmdbId,
      title: widget.title,
      isTv: widget.isTv,
      season: widget.season,
      episode: widget.episode,
    ).listen(
      (link) async {
        if (!mounted) return;
        final exists = _servers.any((item) => item.url == link.url);
        if (!exists) {
          _servers.add(link);
        }
        if (!_launchedNative && _servers.isNotEmpty) {
          await _openNativeWithCurrentServers();
        }
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _isSearching = false);
        if (!_launchedNative && _servers.isNotEmpty) {
          _openNativeWithCurrentServers();
        }
      },
      onError: (_) {
        if (mounted) {
          setState(() => _isSearching = false);
        }
      },
    );
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayTitle = widget.isTv
        ? '${widget.title} • S${widget.season ?? 1}E${widget.episode ?? 1}'
        : widget.title;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _isSearching || _servers.isNotEmpty
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: _primeBlue),
                  const SizedBox(height: 16),
                  Text(
                    displayTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _statusMessage ?? 'Loading HD stream for Media3 Player...',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: _primeBlue,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No working stream found from your Gist providers.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
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
              ),
      ),
    );
  }
}