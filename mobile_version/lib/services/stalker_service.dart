import 'dart:convert';
import 'package:http/http.dart' as http;

class StalkerService {
  static final Map<String, String> _tokens = {};

  static String _getLoadUrl(String portalUrl) {
    var url = portalUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/c')) {
      url = url.substring(0, url.length - 2);
    }
    url = url.replaceAll(RegExp(r'/+$'), '');
    return '$url/server/load.php';
  }

  static Map<String, String> _getHeaders(String mac, [String? token]) {
    final headers = {
      'User-Agent': 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3',
      'Cookie': 'mac=$mac; stb_lang=en; timezone=Europe/Kiev;',
      'Accept': '*/*',
      'X-User-Agent': 'Model: MAG250; Link: WiFi',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // 1. Handshake & Profile Token
  static Future<String?> _getToken(String loadUrl, String mac, String? sn, String? devId) async {
    if (_tokens.containsKey(mac)) return _tokens[mac];

    try {
      // Step A: Handshake
      final hsUri = Uri.parse('$loadUrl?type=stb&action=handshake&token=&JsHttpRequest=1-xml');
      final hsRes = await http.get(hsUri, headers: _getHeaders(mac)).timeout(const Duration(seconds: 10));

      if (hsRes.statusCode == 200) {
        final hsData = jsonDecode(hsRes.body);
        final token = hsData['js']?['token']?.toString();
        if (token == null) return null;

        // Step B: Get Profile / Auth
        final serial = sn ?? 'DA39C1866AB2B';
        final device = devId ?? 'B2537302FBAC576AA0FF8CC0E1607B518690F3D0024ADE99C2D55E911FE68B94';

        final profUri = Uri.parse(
          '$loadUrl?type=stb&action=get_profile&hd=1&ver=ImageDescription&num_banks=2&sn=$serial&stb_type=MAG250&image_version=218&video_out=hdmi&device_id=$device&device_id2=$device&signature=&auth_second_step=0&hw_version=1.7-BD-00&not_valid_token=0&client_type=STB&JsHttpRequest=1-xml',
        );

        final profRes = await http.get(profUri, headers: _getHeaders(mac, token)).timeout(const Duration(seconds: 10));
        if (profRes.statusCode == 200) {
          _tokens[mac] = token;
          return token;
        }
      }
    } catch (_) {}
    return null;
  }

  // 2. Search VOD & Create Direct Stream Link
  static Future<List<Map<String, dynamic>>> searchStreams({
    required Map<String, dynamic> provider,
    required String title,
    int? season,
    int? episode,
  }) async {
    List<Map<String, dynamic>> results = [];

    final portalUrl = provider['portal_url']?.toString();
    final mac = provider['mac']?.toString();
    final serverName = provider['name']?.toString() ?? 'Stalker Portal';
    final sn = provider['serial_number']?.toString();
    final devId = provider['device_id']?.toString();

    if (portalUrl == null || mac == null || portalUrl.isEmpty || mac.isEmpty) return results;

    final loadUrl = _getLoadUrl(portalUrl);
    final token = await _getToken(loadUrl, mac, sn, devId);
    if (token == null) return results;

    try {
      final cleanTitle = title.trim();
      final isTv = season != null;
      final type = isTv ? 'series' : 'vod';

      // Direct Server-Side Search
      final searchUri = Uri.parse(
        '$loadUrl?type=$type&action=get_ordered_list&sortby=added&p=1&search=${Uri.encodeComponent(cleanTitle)}&JsHttpRequest=1-xml',
      );

      final searchRes = await http.get(searchUri, headers: _getHeaders(mac, token)).timeout(const Duration(seconds: 12));

      if (searchRes.statusCode == 200) {
        final data = jsonDecode(searchRes.body);
        final list = (data['js']?['data'] as List?) ?? [];

        if (list.isNotEmpty) {
          for (var item in list.take(3)) {
            final cmd = item['cmd']?.toString();
            final itemName = item['name']?.toString() ?? cleanTitle;
            if (cmd == null || cmd.isEmpty) continue;

            // Create Playable Stream Link
            final linkUri = Uri.parse(
              '$loadUrl?type=$type&action=create_link&cmd=${Uri.encodeComponent(cmd)}&JsHttpRequest=1-xml',
            );

            final linkRes = await http.get(linkUri, headers: _getHeaders(mac, token)).timeout(const Duration(seconds: 10));
            if (linkRes.statusCode == 200) {
              final linkData = jsonDecode(linkRes.body);
              String? rawCmd = linkData['js']?['cmd']?.toString();

              if (rawCmd != null && rawCmd.isNotEmpty) {
                // Remove ffmpeg wrapper if present
                final streamUrl = rawCmd.replaceFirst('ffmpeg ', '').trim();

                final bool isHindi = itemName.toLowerCase().contains('hindi') ||
                    itemName.toLowerCase().contains('dubbed') ||
                    serverName.toLowerCase().contains('hindi');

                results.add({
                  'title': itemName,
                  'server': serverName,
                  'url': streamUrl,
                  'isHindi': isHindi,
                  'isStalker': true,
                });
              }
            }
          }
        }
      }
    } catch (_) {}

    return results;
  }
}
