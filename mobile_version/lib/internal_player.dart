import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/app_settings_service.dart';
import 'services/stream_service.dart';

class InternalPlayer extends StatefulWidget {
  final int tmdbId;
  final String title;
  final bool isTv;
  final int? season;
  final int? episode;
  final String? directUrl;

  const InternalPlayer({
    super.key,
    required this.tmdbId,
    required this.title,
    required this.isTv,
    this.season,
    this.episode,
    this.directUrl,
  });

  @override
  State<InternalPlayer> createState() => _InternalPlayerState();
}

class _InternalPlayerState extends State<InternalPlayer> {
  static const Color _primeBlue = Color(0xFF00A8E1);
  static const MethodChannel _playerChannel = MethodChannel('com.primeflix/player');

  final List<StreamLink> _servers = [];
  StreamSubscription<StreamLink>? _streamSub;
  bool _isSearching = true;
  bool _launchedNative = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _startPlayerFlow();
  }

  String get _displayTitle {
    if (widget.isTv) {
      return '${widget.title} • S${widget.season ?? 1}E${widget.episode ?? 1}';
    }
    return widget.title;
  }

  Future<void> _launchCinemaPlayer({
    String url = '',
    List> sources = const [],
  }) async {
    if (_launchedNative || !mounted) return;
    _launchedNative = true;

    final gistUrl = await AppSettingsService.getGistUrl();
    final tmdbKey = await AppSettingsService.getTmdbApiKey();
    final seekSeconds = await AppSettingsService.getSeekSeconds();

    try {
      await _playerChannel.invokeMethod<bool>('playVideo', {
        'url': url,
        'title': _displayTitle,
        'tmdbId': widget.tmdbId > 0 ? widget.tmdbId.toString() : '',
        'tmdbKey': tmdbKey,
        'gistUrl': gistUrl,
        'isTv': widget.isTv,
        'season': widget.season ?? 1,
        'episode': widget.episode ?? 1,
        'seekSeconds': seekSeconds,
        'sourcesJson': sources.isNotEmpty ? jsonEncode(sources) : '',
        'activeIndex': 0,
        'isTvDevice': false,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _launchedNative = false;
        _isSearching = false;
        _statusMessage = 'Native player launch error: $e';
      });
      return;
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _startPlayerFlow() async {
    final direct = (widget.directUrl ?? '').trim();
    if (direct.isNotEmpty) {
      await _launchCinemaPlayer(url: direct);
      return;
    }

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
          await _launchCinemaPlayer(
            url: _servers.first.url,
            sources: _servers.map((e) => e.toPlayerMap()).toList(),
          );
        }
      },
      onDone: () async {
        if (!mounted) return;
        setState(() => _isSearching = false);
        if (!_launchedNative && _servers.isNotEmpty) {
          await _launchCinemaPlayer(
            url: _servers.first.url,
            sources: _servers.map((e) => e.toPlayerMap()).toList(),
          );
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
                    _displayTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _statusMessage ?? 'Connecting stream for Cinema Player...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: _primeBlue, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'No stream found. Settings mein Gist URL / TMDB API Key check karein.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
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
              ),
      ),
    );
  }
}