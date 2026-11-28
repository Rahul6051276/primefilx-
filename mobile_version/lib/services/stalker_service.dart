import 'dart:convert';
import 'package:http/http.dart' as http;

class StalkerService {
  static String _normalizePortalUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    url = url.replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/c')) {
      return '$url/../portal.php';
    }
    if (!url.endsWith('.php')) {
      return '$url/portal.php';
    }
    return url;
  }

  static List<String> _candidateEndpoints(String rawPortal) {
    var base = rawPortal.trim();
    if (base.isEmpty) return [];
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      base = 'http://$base';
    }
    base = base.replaceAll(RegExp(r'/+$'), '');

    final List<String> list = [];
    if (base.endsWith('.php')) {
      list.add(base);
    } else if (base.endsWith('/c')) {
      final root = base.substring(0, base.length - 2);
      list.add('$root/portal.php');
      list.add('$root/server/load.php');
    } else {
      list.add('$base/portal.php');
      list.add('$base/server/load.php');
      list.add('$base/stalker_portal/server/load.php');
    }
    return list;
  }

  static Map<String, String> _buildHeaders({
    required String mac,
    String? token,
    String deviceId1 = '',
    String deviceId2 = '',
  }) {
    final encodedMac = Uri.encodeComponent(mac.trim().toUpperCase());
    final cookieParts = [
      'mac=$encodedMac',
      'stb_lang=en',
      'timezone=Asia%2FKolkata',
    ];
    if (deviceId1.trim().isNotEmpty) {
      cookieParts.add('device_id=${Uri.encodeComponent(deviceId1.trim())}');
    }
    if (deviceId2.trim().isNotEmpty) {
      cookieParts.add('device_id2=${Uri.encodeComponent(deviceId2.trim())}');
    }

    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3',
      'X-User-Agent': 'Model: MAG250; Link: WiFi',
      'Cookie': cookieParts.join('; '),
      'Accept': '*/*',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static Future authenticate({
    required String portalUrl,
    required String mac,
    String deviceId1 = '',
    String deviceId2 = '',
  }) async {
    final cleanMac = mac.trim().toUpperCase();
    if (portalUrl.trim().isEmpty || cleanMac.isEmpty) return null;

    for (final endpoint in _candidateEndpoints(portalUrl)) {
      try {
        final handshakeUri = Uri.parse(
          '$endpoint?type=stb&action=handshake&token=&prehash=&JsHttpRequest=1-xml',
        );
        final headers = _buildHeaders(
          mac: cleanMac,
          deviceId1: deviceId1,
          deviceId2: deviceId2,
        );
        final res =
            await http.get(handshakeUri, headers: headers).timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) continue;

        final decoded = jsonDecode(res.body);
        final token = (decoded is Map ? decoded['js']?['token'] : null)?.toString() ?? '';
        if (token.isEmpty) continue;

        // Profile call with Device ID 1 & 2
        final authHeaders = _buildHeaders(
          mac: cleanMac,
          token: token,
          deviceId1: deviceId1,
          deviceId2: deviceId2,
        );
        final profileUri = Uri.parse(
          '$endpoint?type=stb&action=get_profile&hd=1'
          '&device_id=${Uri.encodeQueryComponent(deviceId1.trim())}'
          '&device_id2=${Uri.encodeQueryComponent(deviceId2.trim())}'
          '&JsHttpRequest=1-xml',
        );
        await http.get(profileUri, headers: authHeaders).timeout(const Duration(seconds: 8));

        return {
          'endpoint': endpoint,
          'token': token,
          'headers': authHeaders,
        };
      } catch (_) {}
    }
    return null;
  }

  static Future<List> searchAndResolve({
    required String providerName,
    required String portalUrl,
    required String mac,
    String deviceId1 = '',
    String deviceId2 = '',
    required String title,
    required bool isTv,
    int? season,
    int? episode,
  }) async {
    final auth = await authenticate(
      portalUrl: portalUrl,
      mac: mac,
      deviceId1: deviceId1,
      deviceId2: deviceId2,
    );
    if (auth == null) return [];

    final endpoint = auth['endpoint'] as String;
    final headers = Map<String, String>.from(auth['headers'] as Map);
    final query = Uri.encodeQueryComponent(title.trim());
    final mediaType = isTv ? 'series' : 'vod';

    try {
      final listUri = Uri.parse(
        '$endpoint?type=$mediaType&action=get_ordered_list'
        '&search=$query&sortby=added&p=1&JsHttpRequest=1-xml',
      );
      final res = await http.get(listUri, headers: headers).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return [];

      final decoded = jsonDecode(res.body);
      final items = decoded is Map ? (decoded['js']?['data'] as List? ?? []) : [];
      if (items.isEmpty) return [];

      final targetNorm = _normalize(title);
      final List results = [];

      for (final raw in items) {
        if (raw is! Map) continue;
        final itemName = (raw['name'] ?? raw['o_name'] ?? '').toString();
        if (!_isMatch(_normalize(itemName), targetNorm)) continue;

        String cmd = (raw['cmd'] ?? '').toString().trim();
        final itemId = (raw['id'] ?? '').toString().trim();

        // Series ke liye season/episode cmd nikalna
        if (isTv && itemId.isNotEmpty) {
          final seasonCmd = await _findSeriesEpisodeCmd(
            endpoint: endpoint,
            headers: headers,
            seriesId: itemId,
            season: season ?? 1,
            episode: episode ?? 1,
          );
          if (seasonCmd != null && seasonCmd.isNotEmpty) {
            cmd = seasonCmd;
          }
        }

        if (cmd.isEmpty) continue;

        final playUrl = await _createPlayableLink(
          endpoint: endpoint,
          headers: headers,
          mediaType: mediaType,
          cmd: cmd,
          episode: isTv ? (episode ?? 1) : null,
        );

        if (playUrl.isNotEmpty && playUrl.startsWith('http')) {
          results.add({
            'providerName': providerName,
            'title': isTv
                ? '$itemName • S${season ?? 1}E${episode ?? 1}'
                : itemName,
            'url': playUrl,
            'headers': headers,
          });
          if (results.length >= 4) break;
        }
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  static Future<String?> _findSeriesEpisodeCmd({
    required String endpoint,
    required Map<String, String> headers,
    required String seriesId,
    required int season,
    required int episode,
  }) async {
    try {
      final seasonUri = Uri.parse(
        '$endpoint?type=series&action=get_ordered_list'
        '&movie_id=${Uri.encodeQueryComponent(seriesId)}&p=1&JsHttpRequest=1-xml',
      );
      final res =
          await http.get(seasonUri, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;

      final decoded = jsonDecode(res.body);
      final seasons = decoded is Map ? (decoded['js']?['data'] as List? ?? []) : [];

      for (final s in seasons) {
        if (s is! Map) continue;
        final sName = (s['name'] ?? '').toString().toLowerCase();
        final sNum = int.tryParse((s['season_number'] ?? '').toString()) ??
            int.tryParse(RegExp(r'\d+').firstMatch(sName)?.group(0) ?? '');
        if (sNum == season || seasons.length == 1) {
          final seasonId = (s['id'] ?? '').toString();
          final sCmd = (s['cmd'] ?? '').toString();
          if (seasonId.isNotEmpty) {
            final epUri = Uri.parse(
              '$endpoint?type=series&action=get_ordered_list'
              '&movie_id=${Uri.encodeQueryComponent(seriesId)}'
              '&season_id=${Uri.encodeQueryComponent(seasonId)}&p=1&JsHttpRequest=1-xml',
            );
            final epRes =
                await http.get(epUri, headers: headers).timeout(const Duration(seconds: 10));
            if (epRes.statusCode == 200) {
              final epDecoded = jsonDecode(epRes.body);
              final eps =
                  epDecoded is Map ? (epDecoded['js']?['data'] as List? ?? []) : [];
              for (final ep in eps) {
                if (ep is! Map) continue;
                final eNum = int.tryParse((ep['episode_number'] ?? '').toString()) ??
                    int.tryParse(
                        RegExp(r'\d+').firstMatch((ep['name'] ?? '').toString())?.group(0) ??
                            '');
                if (eNum == episode) {
                  final epCmd = (ep['cmd'] ?? '').toString().trim();
                  if (epCmd.isNotEmpty) return epCmd;
                }
              }
            }
          }
          if (sCmd.isNotEmpty) return sCmd;
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<String> _createPlayableLink({
    required String endpoint,
    required Map<String, String> headers,
    required String mediaType,
    required String cmd,
    int? episode,
  }) async {
    try {
      final epParam = episode != null ? '&series=$episode' : '';
      final linkUri = Uri.parse(
        '$endpoint?type=$mediaType&action=create_link'
        '&cmd=${Uri.encodeQueryComponent(cmd)}'
        '$epParam&JsHttpRequest=1-xml',
      );
      final res =
          await http.get(linkUri, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return '';

      final decoded = jsonDecode(res.body);
      var rawCmd = (decoded is Map ? decoded['js']?['cmd'] : null)?.toString().trim() ?? '';
      if (rawCmd.startsWith('ffmpeg ')) {
        rawCmd = rawCmd.substring(7).trim();
      }
      return rawCmd;
    } catch (_) {
      return '';
    }
  }

  static String _normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'\(\d{4}\)'), '')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isMatch(String candidate, String target) {
    if (candidate.isEmpty || target.isEmpty) return false;
    return candidate == target ||
        candidate.contains(target) ||
        (candidate.length > 4 && target.contains(candidate));
  }
}