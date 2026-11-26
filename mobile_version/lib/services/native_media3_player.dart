import 'package:flutter/services.dart';

class NativeMedia3Player {
  static const MethodChannel _channel = MethodChannel('com.primeflix/media3');

  static Future<bool> play({
    required String url,
    required String title,
    Map<String, String>? headers,
    List<dynamic>? servers,
  }) async {
    final cleanUrl = url.trim();
    final hasServers = servers != null && servers.isNotEmpty;
    if (cleanUrl.isEmpty && !hasServers) return false;

    try {
      final result = await _channel.invokeMethod<bool>('playMedia', {
        'url': cleanUrl,
        'title': title,
        'headers': headers ??
            const {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            },
        if (servers != null) 'servers': servers,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }
}