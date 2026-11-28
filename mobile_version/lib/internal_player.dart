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
  static const MethodChannel _playerChannel =
      MethodChannel('com.primeflix/player');

  final List _servers = [];
  StreamSubscription? _streamSub;
  Timer? _launchDelayTimer;
  Timer? _maxWaitTimer;
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

  Future _restorePortraitMode() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future _launchCinemaPlayer({
    String url = '',
    List sources = const [],
  }) async {
    if (_launchedNative || !mounted) return;
    _launchedNative = true;
    _launchDelayTimer?.cancel();
    _maxWaitTimer?.cancel();

    final gistUrl = await AppSettingsService.getGistUrl();
    final tmdbKey = await AppSettingsService.getTmdbApiKey();
    final seekSeconds = await AppSettingsService.getSeekSeconds();

    try {
      await _playerChannel.invokeMethod('playVideo', {
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
      await _restorePortraitMode();
    } catch (e) {
      await _restorePortraitMode();
      if (!mounted) return;
      setState(() {
        _launchedNative = false;
        _isSearching = false;
        _statusMessage = 'Native player launch error: $e';
      });
      return;
    }

    if (mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  void _openWithCollectedServers() {
    if (_launchedNative || !mounted) return;
    if (_servers.isNotEmpty) {
      // Hindi/Dubbed streams ko upar rakhein
      _servers.sort((a, b) {
        final aHi = (a.isHindi == true) ? 0 : 1;
        final bHi = (b.isHindi == true) ? 0 : 1;
        return aHi.compareTo(bHi);
      });
      final list = _servers.map((s) => s.toPlayerMap()).toList();
      _launchCinemaPlayer(
        url: _servers.first.url,
        sources: list,
      );
    } else {
      _launchCinemaPlayer();
    }
  }

  Future _startPlayerFlow() async {
    final direct = (widget.directUrl ?? '').trim();
    if (direct.isNotEmpty) {
      await _launchCinemaPlayer(url: direct);
      return;
    }

    setState(() {
      _isSearching = true;
      _statusMessage = 'Fetching streams from Stremio, Xtream & Stalker...';
    });

    // Maximum 16 second wait taaki player hang na ho
    _maxWaitTimer = Timer(const Duration(seconds: 16), () {
      _openWithCollectedServers();
    });

    _streamSub = StreamService.fetchStreams(
      tmdbId: widget.tmdbId,
      title: widget.title,
      isTv: widget.isTv,
      season: widget.season,
      episode: widget.episode,
    ).listen(
      (link) {
        if (!mounted) return;
        final exists = _servers.any((item) => item.url == link.url);
        if (!exists) {
          setState(() {
            _servers.add(link);
            _statusMessage =
                'Found ${_servers.length} sources (${link.providerName})...';
          });
        }

        // Pehla link milne ke 1.5s baad player kholein taaki baaki servers bhi list mein jud jayein
        if (!_launchedNative && _launchDelayTimer == null) {
          _launchDelayTimer = Timer(const Duration(milliseconds: 1500), () {
            _openWithCollectedServers();
          });
        }
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _isSearching = false);
        _openWithCollectedServers();
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _isSearching = false);
        _openWithCollectedServers();
      },
    );
  }

  @override
  void dispose() {
    _launchDelayTimer?.cancel();
    _maxWaitTimer?.cancel();
    _streamSub?.cancel();
    _restorePortraitMode();
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
                    _statusMessage ?? 'Opening Cinema Player...',
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
                    Text(
                      _statusMessage ??
                          'No stream found. Settings mein Gist URL / Xtream / Stalker check karein.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
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