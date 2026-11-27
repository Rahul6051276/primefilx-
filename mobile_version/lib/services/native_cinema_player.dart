import 'dart:convert';
import 'package:flutter/services.dart';

class NativeCinemaPlayer {
  static const MethodChannel _channel = MethodChannel('com.primeflix/player');

  static Future<bool> playVideo({
    String url = '',
    required String title,
    String tmdbId = '',
    String tmdbKey = '',
    String gistUrl = '',
    bool isTv = false,
    int season = 1,
    int episode = 1,
    String userAgent = 'VLC/3.0.18 LibVLC/3.0.18 (Linux; Android 13)',
    int seekSeconds = 15,
    List> sources = const [],
    int activeIndex = 0,
  }) async {
    final bool? result = await _channel.invokeMethod<bool>('playVideo', {
      'url': url,
      'title': title,
      'tmdbId': tmdbId,
      'tmdbKey': tmdbKey,
      'gistUrl': gistUrl,
      'isTv': isTv,
      'season': season,
      'episode': episode,
      'userAgent': userAgent,
      'seekSeconds': seekSeconds,
      'sourcesJson': sources.isNotEmpty ? jsonEncode(sources) : '',
      'activeIndex': activeIndex,
      'isTvDevice': false,
    });
    return result ?? false;
  }
}
