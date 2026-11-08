import 'dart:convert';
import 'package:http/http.dart' as http;
import 'tmdb_service.dart';

class MobileStreamService {
  // Permanent stable Gist raw URL for robust fallback & provider loading
  static const String gistUrl = 'https://gist.githubusercontent.com/Rahul6051276/239654d65b2124bffd0ea21b5251dc02/raw/providers.json';

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

  // --- FETCH ACTIVE PROVIDERS DIRECTLY FROM GIST ---
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

  // --- RENDER TMDB EMBED API WITH GIST PROVIDERS & FALLBACK SUPPORT ---
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

    // 1. Try fetching streams from Render TMDB Embed API
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
                final provName = (s['provider'] ?? 'Cloud API').toString();
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

    // 2. Fallback: If Render API doesn't return streams, load active providers dynamically
    if (resolved.isEmpty) {
      var activeProvList = providers;
      if (activeProvList == null || (activeProvList is List && activeProvList.isEmpty)) {
        activeProvList = await fetchProvidersFromGist();
      }

      if (activeProvList is List && activeProvList.isNotEmpty) {
        for (var p in activeProvList) {
          resolved.add({
            'server': p['name'] ?? 'Primeflix Server',
            'title': '$movieTitle (Official Stream)',
            'url': p['url'] ?? '',
            'isHindi': true,
          });
        }
      }
    }

    // Sort by Hindi preference
    resolved.sort((a, b) => (b['isHindi'] == true ? 1 : 0).compareTo(a['isHindi'] == true ? 1 : 0));

    return resolved;
  }

  static Future getSportsChannels(dynamic providers) async {
    return [
      {'name': 'Star Sports 1 Hindi', 'isHindi': true, 'url': ''},
      {'name': 'Sony Ten 1 HD', 'isHindi': false, 'url': ''},
    ];
  }

  static Future getLiveChannelUrl(dynamic channel) async {
    return channel['url']?.toString();
  }
}
