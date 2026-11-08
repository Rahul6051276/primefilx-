import 'dart:convert';
import 'package:http/http.dart' as http;
import 'tmdb_service.dart';

class MobileStreamService {
  // Aapka Render API Base URL
  static const String renderApiBase = 'https://tmdb-embed-api-4.onrender.com';
  
  // Gist URL backup/fallback ke liye
  static const String gistUrl = 'https://gist.githubusercontent.com/Rahul6051276/5b0a18b2cf69a99d1d3e06629fcbc70a/raw/1da5a456a2924114e041e47a6cd16b5f6b1e4be1/TMDB%2520API';

  static bool isHindiStream(String title, {String category = ''}) {
    final lower = '$title $category'.toLowerCase();
    return lower.contains('hindi') ||
        lower.contains('dual') ||
        lower.contains('multi') ||
        lower.contains('dubbed') ||
        lower.contains('hin') ||
        lower.contains('dub');
  }

  // --- RENDER TMDB EMBED API AGGREGATE ENDPOINT INTEGRATION ---
  static Future getDirectStreams({
    required dynamic item,
    required dynamic providers,
    int? season,
    int? episode,
  }) async {
    var resolved = [];
    final targetTmdbId = item['tmdb_id']?.toString() ?? '';
    final isTv = item['isTv'] == true;
    final movieTitle = (item['title'] ?? '').toString();
    final targetSeason = season ?? 1;
    final targetEpisode = episode ?? 1;

    if (targetTmdbId.isNotEmpty) {
      try {
        final mediaType = isTv ? 'series' : 'movie';
        final apiUrl = isTv
            ? '$renderApiBase/api/streams/$mediaType/$targetTmdbId?season=$targetSeason&episode=$targetEpisode'
            : '$renderApiBase/api/streams/$mediaType/$targetTmdbId';

        final res = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 10));
        
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
      } catch (_) {}
    }

    // Agar API se streams na milein tabhi fallback dikhao
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

    // Hindi streams ko sabse upar rakhne ke liye sort karna
    resolved.sort((a, b) => (b['isHindi'] == true ? 1 : 0).compareTo(a['isHindi'] == true ? 1 : 0));

    return resolved;
  }
}
