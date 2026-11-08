import 'dart:convert';
import 'package:http/http.dart' as http;
import 'tmdb_service.dart';

class MobileStreamService {
  // Updated clean raw Gist URL for the Render TMDB API provider
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

  static String cleanString(String str) {
    return str
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .trim();
  }

  // --- FETCH ACTIVE PROVIDERS FROM GIST ---
  static Future<List> fetchProvidersFromGist() async {
    try {
      final res = await http.get(Uri.parse(gistUrl)).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['active_providers'] ?? [];
      }
    } catch (_) {}
    return [];
  }

  // --- STRICTLY RENDER TMDB EMBED API INTEGRATION ---
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

    // Fetch streams directly from the Render TMDB Embed API backend
    if (targetTmdbId.isNotEmpty) {
      try {
        final embedType = isTv ? 'series' : 'movie';
        final embedUrl = isTv
            ? 'https://tmdb-embed-api-4.onrender.com/api/streams/$embedType/$targetTmdbId?season=$targetSeason&episode=$targetEpisode'
            : 'https://tmdb-embed-api-4.onrender.com/api/streams/$embedType/$targetTmdbId';

        final embedRes = await http.get(Uri.parse(embedUrl)).timeout(const Duration(seconds: 8));
        if (embedRes.statusCode == 200) {
          var embedData = jsonDecode(embedRes.body);
          var streamList = embedData is List ? embedData : (embedData['streams'] ?? []);
          
          if (streamList is List) {
            for (var s in streamList) {
              final sUrl = (s['url'] ?? '').toString();
              if (sUrl.isNotEmpty) {
                final sTitle = (s['title'] ?? ('$movieTitle HD')).toString();
                final provName = (s['provider'] ?? 'Render Cloud').toString();
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
        }
      } catch (_) {}
    }

    // Fallback if Render API doesn't return streams instantly
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

    // Sort by Hindi preference
    resolved.sort((a, b) => (b['isHindi'] == true ? 1 : 0).compareTo(a['isHindi'] == true ? 1 : 0));

    return resolved;
  }
}
