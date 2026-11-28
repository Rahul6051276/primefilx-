import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/app_settings_service.dart';

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
  static const MethodChannel _playerChannel =
      MethodChannel('com.primeflix/player');

  bool _launchedNative = false;
  String? _errorMessage;

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

    final gistUrl = await AppSettingsService.getGistUrl();
    final tmdbKey = await AppSettingsService.getTmdbApiKey();
    final seekSeconds = await AppSettingsService.getSeekSeconds();
    final directXtream = await AppSettingsService.getDirectXtream();
    final directStalker = await AppSettingsService.getDirectStalker();

    final List extraProviders = [];
    if ((directXtream['url'] ?? '').isNotEmpty &&
        (directXtream['username'] ?? '').isNotEmpty &&
        (directXtream['password'] ?? '').isNotEmpty) {
      extraProviders.add({
        'name': 'Xtream IPTV (Direct)',
        'type': 'xtream',
        'xc_host': directXtream['url'],
        'xc_username': directXtream['username'],
        'xc_password': directXtream['password'],
      });
    }
    if ((directStalker['url'] ?? '').isNotEmpty &&
        (directStalker['mac'] ?? '').isNotEmpty) {
      extraProviders.add({
        'name': 'Stalker Portal (Direct)',
        'type': 'stalker',
        'portal_url': directStalker['url'],
        'mac': directStalker['mac'],
        'device_id1': directStalker['device_id1'] ?? '',
        'device_id2': directStalker['device_id2'] ?? '',
      });
    }

    try {
      await _playerChannel.invokeMethod('playVideo', {
        'url': url,
        'title': _displayTitle,
        'rawTitle': widget.title,
        'tmdbId': widget.tmdbId > 0 ? widget.tmdbId.toString() : '',
        'tmdbKey': tmdbKey,
        'gistUrl': gistUrl,
        'extraProvidersJson':
            extraProviders.isNotEmpty ? jsonEncode(extraProviders) : '',
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
        _errorMessage = 'Player launch error: $e';
      });
      return;
    }

    if (mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  Future _startPlayerFlow() async {
    final direct = (widget.directUrl ?? '').trim();
    if (direct.isNotEmpty) {
      await _launchCinemaPlayer(url: direct);
      return;
    }

    if (widget.tmdbId > 0) {
      await _launchCinemaPlayer();
      return;
    }

    if (mounted) {
      setState(() {
        _errorMessage = 'Invalid title or stream URL.';
      });
    }
  }

  @override
  void dispose() {
    _restorePortraitMode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage == null) {
      return const Scaffold(backgroundColor: Colors.black);
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A8E1),
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