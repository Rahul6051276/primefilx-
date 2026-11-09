import 'dart:convert';
import 'package:http/http.dart' as http;
import '../app_config.dart'; // Aapke AppConfig ka import
import 'tmdb_service.dart';

class MobileStreamService {
  static const String renderApiBase = 'https://tmdb-embed-api-4.onrender.com';

  static bool isHindiStream(String title, {String category = ''}) {
    final lower = '$title $category'.toLowerCase();
    return lower.contains('hindi') ||
        lower.contains('dual') ||
        lower.contains('multi') ||
        lower.contains('dubbed') ||
        lower.contains('hin') ||
        lower.contains('dub');
  }

  // AppConfig se providers.json / gist fetch karna
  static Future> _fetchXtreamConfig() async {
    try {
      final res = await http.get(Uri.parse(AppConfig.gistUrl)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        // Agar providers.json ke andar Xtream ki keys hain toh unhe uthao, warna defaults do
        return {
          'host': (data['xc_host'] ?? data['host'] ?? 'http://line.portal4k.love').toString().trim(),
          'username': (data['xc_username'] ?? data['username'] ?? 'f4:fe:fb:81:9e:e0').toString().trim(),
          'password': (data['xc_password'] ?? data['password'] ?? 'C9DLMNMLDR').toString().trim(),
        };
      }
    } catch (e) {
      print('Config fetch error: $e');
    }
    
    return {
      'host': 'http://line.portal4k.love',
      'username': 'f4:fe:fb:81:9e:e0',
      'password': 'C9DLMNMLDR',
    };
  }

  static Future<List<dynamic>> getDirectStreams({
    required dynamic item,
    required dynamic providers,
    int? season,
    int? episode,
  }) async {
    List<dynamic> resolved = [];
    final targetTmdbId = item['tmdb_id']?.toString() ?? '';
    final isTv = item['isTv'] == true;
    final movieTitle = (item['title'] ?? '').toString().toLowerCase();
    final cleanTitle = movieTitle.replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim();
    final targetSeason = season ?? 1;
    final targetEpisode = episode ?? 1;

    // 1. Render Cloud API Streams
    if (targetTmdbId.isNotEmpty) {
      try {
        final mediaType = isTv ? 'series' : 'movie';
        final apiUrl = isTv
            ? '$renderApiBase/api/streams/$mediaType/$targetTmdbId?season=$targetSeason&episode=$targetEpisode'
            : '$renderApiBase/api/streams/$mediaType/$targetTmdbId';

        final res = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 6));
        
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          List streamList = [];
          if (data is List) {
            streamList = data;
          } else if (data is Map && data['streams'] != null) {
            streamList = data['streams'];
          } else if (data is Map) {
            data.forEach((key, value) {
              if (value is List) streamList.addAll(value);
            });
          }

          for (var s in streamList) {
            final sUrl = (s['url'] ?? '').toString();
            if (sUrl.isNotEmpty) {
              final sTitle = (s['title'] ?? ('$movieTitle - ' + (s['name'] ?? 'HD'))).toString();
              final provName = (s['provider'] ?? s['name'] ?? 'Render Cloud').toString();
              final isHindi = isHindiStream(sTitle);

              resolved.add({
                'server': 'Cloud - $provName',
                'title': sTitle,
                'url': sUrl,
                'isHindi': isHindi,
              });
            }
          }
        }
      } catch (e) {
        print('Render API error: $e');
      }
    }

    // 2. Xtream IPTV VOD / Series Matching
    try {
      final config = await _fetchXtreamConfig();
      final xcHost = config['host']!;
      final xcUser = config['username']!;
      final xcPass = config['password']!;

      if (!isTv) {
        final vodUrl = '$xcHost/player_api.php?username=$xcUser&password=$xcPass&action=get_vod_streams';
        final vodRes = await http.get(Uri.parse(vodUrl)).timeout(const Duration(seconds: 12));
        
        if (vodRes.statusCode == 200) {
          final vodData = jsonDecode(vodRes.body);
          if (vodData is List && vodData.isNotEmpty) {
            final matches = vodData.where((m) {
              final name = (m['name'] ?? '').toString().toLowerCase();
              final cleanName = name.replaceAll(RegExp(r'[^a-z0-9\s]'), '');
              if (cleanTitle.isEmpty) return false;
              return cleanName.contains(cleanTitle) || cleanTitle.contains(cleanName);
            }).toList();

            for (var matched in matches) {
              final streamId = matched['stream_id'];
              final container = matched['container_extension'] ?? 'mp4';
              final rawName = matched['name'] ?? 'Xtream Movie';
              final streamUrl = '$xcHost/movie/$xcUser/$xcPass/$streamId.$container';
              final isHindi = isHindiStream(rawName);

              resolved.add({
                'server': 'Xtream - IPTV',
                'title': isHindi ? '🎬 $rawName [Hindi Dubbed]' : '🎬 $rawName [Original]',
                'url': streamUrl,
                'isHindi': isHindi,
              });
            }
          }
        }
      }
    } catch (e) {
      print('Xtream fetch error: $e');
    }

    // Fallback if empty
    if (resolved.isEmpty) {
      resolved.add({
        'server': 'Render Cloud Server',
        'title': '$movieTitle (Official Stream)',
        'url': isTv 
            ? 'https://vidsrc.me/embed/tv?tmdb=$targetTmdbId&season=$targetSeason&episode=$targetEpisode'
            : 'https://vidsrc.me/embed/movie?tmdb=$targetTmdbId',
        'isHindi': true,
      });
    }

    // Sort Hindi first priority
    resolved.sort((a, b) => (b['isHindi'] == true ? 1 : 0).compareTo(a['isHindi'] == true ? 1 : 0));

    return resolved;
  }
}
