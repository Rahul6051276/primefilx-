import 'dart:convert';
import 'package:http/http.dart' as http;
import 'tmdb_service.dart';

class MobileStreamService {
  static const String renderApiBase = 'https://tmdb-embed-api-4.onrender.com';
  
  static Future<Map<String, String>> _fetchXtreamConfig() async {
    try {
      final res = await http.get(Uri.parse(AppConfig.gistUrl)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return {
          'host': (data['xc_host'] ?? data['host'] ?? 'http://line.portal4k.love').toString().trim(),
          'username': (data['xc_username'] ?? data['username'] ?? 'f4:fe:fb:81:9e:e0').toString().trim(),
          'password': (data['xc_password'] ?? data['password'] ?? 'C9DLMNMLDR').toString().trim(),
        };
      }
    } catch (_) {}
    
    return {
      'host': 'http://line.portal4k.love',
      'username': 'f4:fe:fb:81:9e:e0',
      'password': 'C9DLMNMLDR',
    };
  }

  static bool isHindiStream(String title, {String category = ''}) {
    final lower = '$title $category'.toLowerCase();
    return lower.contains('hindi') ||
        lower.contains('dual') ||
        lower.contains('multi') ||
        lower.contains('dubbed') ||
        lower.contains('hin') ||
        lower.contains('dub');
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
      } catch (_) {}
    }

    // 2. Xtream IPTV VOD & Series Matching
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
      } else {
        // Series handling
        final seriesUrl = '$xcHost/player_api.php?username=$xcUser&password=$xcPass&action=get_series';
        final seriesRes = await http.get(Uri.parse(seriesUrl)).timeout(const Duration(seconds: 10));

        if (seriesRes.statusCode == 200) {
          final seriesJson = jsonDecode(seriesRes.body);
          if (seriesJson is List) {
            final matchedSeries = seriesJson.firstWhere(
              (s) => (s['name'] ?? '').toString().toLowerCase().contains(cleanTitle),
              orElse: () => null,
            );

            if (matchedSeries != null) {
              final seriesId = matchedSeries['series_id'];
              final infoUrl = '$xcHost/player_api.php?username=$xcUser&password=$xcPass&action=get_series_info&series_id=$seriesId';
              final infoRes = await http.get(Uri.parse(infoUrl)).timeout(const Duration(seconds: 10));

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
                      final isHindi = isHindiStream(epTitle) || isHindiStream(matchedSeries['name'] ?? '');

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
