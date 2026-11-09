import 'dart:convert';
import 'package:http/http.dart' as http;
import 'tmdb_service.dart';

class MobileStreamService {
  // ==========================================
  // 1. CONFIGURATIONS & API ENDPOINTS
  // ==========================================
  static const String renderApiBase = 'https://tmdb-embed-api-4.onrender.com';
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

  // ==========================================
  // 2. GIST CONFIG HELPER FOR XTREAM IPTV
  // ==========================================
  static Future> _fetchXtreamConfig() async {
    try {
      final res = await http.get(Uri.parse(gistUrl)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return {
          'host': data['xc_host'] ?? 'http://line.portal4k.love',
          'username': data['xc_username'] ?? 'f4:fe:fb:81:9e:e0',
          'password': data['xc_password'] ?? 'C9DLMNMLDR',
        };
      }
    } catch (_) {}
    
    return {
      'host': 'http://line.portal4k.love',
      'username': 'f4:fe:fb:81:9e:e0',
      'password': 'C9DLMNMLDR',
    };
  }

  // ==========================================
  // 3. MAIN AGGREGATOR (BOTH RENDER + XTREAM)
  // ==========================================
  static Future<List<dynamic>> getDirectStreams({
    required dynamic item,
    required dynamic providers,
    int? season,
    int? episode,
  }) async {
    var resolved = [];
    final targetTmdbId = item['tmdb_id']?.toString() ?? '';
    final isTv = item['isTv'] == true;
    final movieTitle = (item['title'] ?? '').toString().toLowerCase();
    final targetSeason = season ?? 1;
    final targetEpisode = episode ?? 1;

    // ------------------------------------------
    // PART A: RENDER CLOUD API FETCHING LOGIC
    // ------------------------------------------
    if (targetTmdbId.isNotEmpty) {
      try {
        final mediaType = isTv ? 'series' : 'movie';
        final apiUrl = isTv
            ? '$renderApiBase/api/streams/$mediaType/$targetTmdbId?season=$targetSeason&episode=$targetEpisode'
            : '$renderApiBase/api/streams/$mediaType/$targetTmdbId';

        final res = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 8));
        
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

    // ------------------------------------------
    // PART B: XTREAM CODES IPTV FETCHING LOGIC
    // ------------------------------------------
    try {
      final config = await _fetchXtreamConfig();
      final xcHost = config['host']!;
      final xcUser = config['username']!;
      final xcPass = config['password']!;

      if (!isTv) {
        // --- IPTV Movie / VOD Search ---
        final vodUrl = '$xcHost/player_api.php?username=$xcUser&password=$xcPass&action=get_vod_streams';
        final vodRes = await http.get(Uri.parse(vodUrl)).timeout(const Duration(seconds: 8));
        
        if (vodRes.statusCode == 200) {
          final vodData = jsonDecode(vodRes.body);
          if (vodData is List) {
            final matches = vodData.where((m) {
              final name = (m['name'] ?? '').toString().toLowerCase();
              return movieTitle.isNotEmpty && name.contains(movieTitle);
            });

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
      } else {
        // --- IPTV TV Series / Episodes Search ---
        final seriesUrl = '$xcHost/player_api.php?username=$xcUser&password=$xcPass&action=get_series';
        final seriesRes = await http.get(Uri.parse(seriesUrl)).timeout(const Duration(seconds: 8));

        if (seriesRes.statusCode == 200) {
          final seriesData = jsonDecode(seriesRes.body);
          if (seriesData is List) {
            final matchedSeries = seriesData.firstWhere(
              (s) => (s['name'] ?? '').toString().toLowerCase().contains(movieTitle),
              orElse: () => null,
            );

            if (matchedSeries != null) {
              final seriesId = matchedSeries['series_id'];
              final infoUrl = '$xcHost/player_api.php?username=$xcUser&password=$xcPass&action=get_series_info&series_id=$seriesId';
              final infoRes = await http.get(Uri.parse(infoUrl)).timeout(const Duration(seconds: 8));

              if (infoRes.statusCode == 200) {
                final infoData = jsonDecode(infoRes.body);
                if (infoData != null && infoData['episodes'] != null) {
                  final episodesMap = infoData['episodes'];
                  final seasonEpisodes = episodesMap[targetSeason.toString()];

                  if (seasonEpisodes is List) {
                    final targetEp = seasonEpisodes.firstWhere(
                      (e) => e['episode_num'].toString() == targetEpisode.toString(),
                      orElse: () => null,
                    );

                    if (targetEp != null) {
                      final epId = targetEp['id'];
                      final container = targetEp['container_extension'] ?? 'mp4';
                      final epTitle = targetEp['title'] ?? 'S${targetSeason}E${targetEpisode}';
                      final epUrl = '$xcHost/series/$xcUser/$xcPass/$epId.$container';
                      final isHindi = isHindiStream(epTitle);

                      resolved.add({
                        'server': 'Xtream - IPTV Series',
                        'title': isHindi ? '📺 $epTitle [Hindi Dubbed]' : '📺 $epTitle [Original]',
                        'url': epUrl,
                        'isHindi': isHindi,
                      });
                    }
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    // ------------------------------------------
    // PART C: FALLBACK (IF NO STREAMS FOUND)
    // ------------------------------------------
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

    // ------------------------------------------
    // PART D: SORTING (HINDI FIRST PRIORITY)
    // ------------------------------------------
    resolved.sort((a, b) => (b['isHindi'] == true ? 1 : 0).compareTo(a['isHindi'] == true ? 1 : 0));

    return resolved;
  }
}
