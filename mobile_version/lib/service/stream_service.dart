import 'dart:convert';
import 'package:http/http.dart' as http;
import 'tmdb_service.dart';

class MobileStreamService {
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

  // DIRECT VOD (XTREAM + STREMIO HDHUB + RENDER EMBED API)
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

    String? imdbId;
    if (targetTmdbId.isNotEmpty) {
      try {
        final extType = isTv ? 'tv' : 'movie';
        final extUrl = AppConfig.tmdbBase + '/' + extType + '/' + targetTmdbId + '/external_ids?api_key=' + AppConfig.tmdbKey;
        final extRes = await http.get(Uri.parse(extUrl)).timeout(const Duration(seconds: 4));
        if (extRes.statusCode == 200) {
          imdbId = jsonDecode(extRes.body)['imdb_id'];
        }
      } catch (_) {}
    }

    final cleanTarget = cleanString(movieTitle);

    // ==========================================
    // 3. RENDER TMDB EMBED API (CASTLE, SHOWBOX, 4KHDHUB ETC.)
    // ==========================================
    if (targetTmdbId.isNotEmpty) {
      try {
        final embedType = isTv ? 'series' : 'movie';
        final embedUrl = isTv
            ? 'https://tmdb-embed-api-4.onrender.com/api/streams/' + embedType + '/' + targetTmdbId + '?season=' + targetSeason.toString() + '&episode=' + targetEpisode.toString()
            : 'https://tmdb-embed-api-4.onrender.com/api/streams/' + embedType + '/' + targetTmdbId;

        final embedRes = await http.get(Uri.parse(embedUrl)).timeout(const Duration(seconds: 8));
        if (embedRes.statusCode == 200) {
          var embedData = jsonDecode(embedRes.body);
          var streamList = embedData is List ? embedData : (embedData['streams'] ?? []);
          
          if (streamList is List) {
            for (var s in streamList) {
              final sUrl = (s['url'] ?? '').toString();
              if (sUrl.isNotEmpty) {
                final sTitle = (s['title'] ?? (movieTitle + ' HD')).toString();
                final provName = (s['provider'] ?? 'Cloud API').toString();
                final isHindi = isHindiStream(sTitle);

                resolved.add({
                  'server': 'Cloud - ' + provName,
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

    for (var prov in providers) {
      final type = prov['type'];

      // 1. XTREAM IPTV VOD
      if (type == 'xtream') {
        final host = (prov['host'] ?? '').toString().replaceAll(RegExp(r'/+$'), '');
        final user = prov['username'] ?? '';
        final pass = prov['password'] ?? '';

        if (host.isNotEmpty && user.isNotEmpty && pass.isNotEmpty) {
          try {
            if (isTv) {
              final searchApi = host + '/player_api.php?username=' + user + '&password=' + pass + '&action=get_series';
              final xtreamRes = await http.get(Uri.parse(searchApi)).timeout(const Duration(seconds: 6));
              if (xtreamRes.statusCode == 200) {
                var seriesList = jsonDecode(xtreamRes.body);
                var candidates = [];

                for (var s in seriesList) {
                  final sTmdb = (s['tmdb_id'] ?? s['tmdb'] ?? '').toString();
                  final rawName = (s['name'] ?? '').toString();
                  final categoryName = (s['category_name'] ?? '').toString();
                  final sClean = cleanString(rawName);

                  bool isMatch = false;
                  if (sTmdb.isNotEmpty && sTmdb == targetTmdbId) {
                    isMatch = true;
                  } else if (sClean.contains(cleanTarget) || cleanTarget.contains(sClean)) {
                    isMatch = true;
                  }

                  if (isMatch) {
                    s['is_hindi_detected'] = isHindiStream(rawName, category: categoryName);
                    candidates.add(s);
                  }
                }

                candidates.sort((a, b) {
                  final aH = a['is_hindi_detected'] == true ? 1 : 0;
                  final bH = b['is_hindi_detected'] == true ? 1 : 0;
                  return bH.compareTo(aH);
                });

                for (var bestSeries in candidates.take(2)) {
                  final seriesId = bestSeries['series_id'];
                  final infoApi = host + '/player_api.php?username=' + user + '&password=' + pass + '&action=get_series_info&series_id=' + seriesId.toString();
                  final infoRes = await http.get(Uri.parse(infoApi)).timeout(const Duration(seconds: 6));
                  if (infoRes.statusCode == 200) {
                    var infoData = jsonDecode(infoRes.body);
                    var episodesMap = infoData['episodes'] ?? {};
                    var epList = episodesMap[targetSeason.toString()] ?? [];

                    dynamic matchedEp;
                    if (epList is List && epList.isNotEmpty) {
                      matchedEp = epList.firstWhere(
                        (e) => (e['episode_num'] ?? 0) == targetEpisode,
                        orElse: () => null,
                      );
                    }

                    if (matchedEp != null) {
                      final epStreamId = matchedEp['id'];
                      final ext = matchedEp['container_extension'] ?? 'mp4';
                      final isHindi = bestSeries['is_hindi_detected'] == true;
                      resolved.add({
                        'server': prov['name'] ?? 'Xtream Series HD',
                        'title': isHindi
                            ? movieTitle + ' (Hindi Audio) S' + targetSeason.toString() + ':E' + targetEpisode.toString()
                            : movieTitle + ' S' + targetSeason.toString() + ':E' + targetEpisode.toString(),
                        'url': host + '/series/' + user + '/' + pass + '/' + epStreamId.toString() + '.' + ext.toString(),
                        'isHindi': isHindi,
                      });
                    }
                  }
                }
              }
            } else {
              final searchApi = host + '/player_api.php?username=' + user + '&password=' + pass + '&action=get_vod_streams';
              final xtreamRes = await http.get(Uri.parse(searchApi)).timeout(const Duration(seconds: 6));
              if (xtreamRes.statusCode == 200) {
                var streamList = jsonDecode(xtreamRes.body);
                var candidates = [];

                for (var m in streamList) {
                  final mTmdb = (m['tmdb_id'] ?? m['tmdb'] ?? '').toString();
                  final rawName = (m['name'] ?? '').toString();
                  final categoryName = (m['category_name'] ?? '').toString();
                  final mClean = cleanString(rawName);

                  bool isMatch = false;
                  if (mTmdb.isNotEmpty && mTmdb == targetTmdbId) {
                    isMatch = true;
                  } else if (mClean.contains(cleanTarget) || cleanTarget.contains(mClean)) {
                    isMatch = true;
                  }

                  if (isMatch) {
                    final isHindi = isHindiStream(rawName, category: categoryName);
                    candidates.add({
                      'data': m,
                      'isHindi': isHindi,
                      'name': rawName,
                    });
                  }
                }

                candidates.sort((a, b) {
                  final aH = a['isHindi'] == true ? 1 : 0;
                  final bH = b['isHindi'] == true ? 1 : 0;
                  return bH.compareTo(aH);
                });

                for (var cand in candidates.take(3)) {
                  var bestMovie = cand['data'];
                  final streamId = bestMovie['stream_id'];
                  final ext = bestMovie['container_extension'] ?? 'mp4';
                  final isHindi = cand['isHindi'] == true;

                  resolved.add({
                    'server': prov['name'] ?? 'Xtream Movies VIP',
                    'title': isHindi
                        ? movieTitle + ' (Hindi Audio / Dubbed)'
                        : movieTitle + ' (Direct HD)',
                    'url': host + '/movie/' + user + '/' + pass + '/' + streamId.toString() + '.' + ext.toString(),
                    'isHindi': isHindi,
                  });
                }
              }
            }
          } catch (_) {}
        }
      }

      // 2. STREMIO ADDON (HDHUB)
      if (type == 'stremio' && imdbId != null && imdbId.isNotEmpty) {
        final base = (prov['url'] ?? '').toString().replaceAll('/manifest.json', '');
        final streamPath = isTv
            ? base + '/stream/series/' + imdbId + ':' + targetSeason.toString() + ':' + targetEpisode.toString() + '.json'
            : base + '/stream/movie/' + imdbId + '.json';

        try {
          final res = await http.get(Uri.parse(streamPath)).timeout(const Duration(seconds: 4));
          if (res.statusCode == 200) {
            var data = jsonDecode(res.body);
            var streamEntries = data['streams'] ?? [];
            if (streamEntries is List) {
              for (var s in streamEntries) {
                final titleStr = (s['title'] ?? s['name'] ?? '').toString();
                if (titleStr.toLowerCase().contains('donation') ||
                    titleStr.toLowerCase().contains('discord') ||
                    titleStr.toLowerCase().contains('telegram')) {
                  continue;
                }

                final isHindi = isHindiStream(titleStr);
                resolved.add({
                  'server': prov['name'] ?? 'HdHub Server',
                  'title': titleStr,
                  'url': s['url'],
                  'isHindi': isHindi,
                });
              }
            }
          }
        } catch (_) {}
      }
    }

    resolved.sort((a, b) {
      final aHindi = a['isHindi'] == true ? 1 : 0;
      final bHindi = b['isHindi'] == true ? 1 : 0;
      if (aHindi != bHindi) return bHindi.compareTo(aHindi);

      final aIsXtream = (a['server'] ?? '').toString().contains('Xtream') ? 1 : 0;
      final bIsXtream = (b['server'] ?? '').toString().contains('Xtream') ? 1 : 0;
      return bIsXtream.compareTo(aIsXtream);
    });

    return resolved;
  }

  // ULTRA FAST LIVE SPORTS (DIRECT XTREAM MPEG-TS)
  static Future getSportsChannels(dynamic providers) async {
    var sports = [];
    final sportsKeywords = [
      'star sports',
      'sony ten',
      'sony six',
      'sony sports',
      'sports18',
      'cricket',
      'willow',
      'dd sports',
      'ptv sports',
      'astro cricket',
      'sky sports'
    ];

    if (providers is List) {
      for (var p in providers) {
        if (p['type'] == 'xtream') {
          final host = (p['host'] ?? '').toString().replaceAll(RegExp(r'/+$'), '');
          final user = p['username'] ?? '';
          final pass = p['password'] ?? '';
          if (host.isNotEmpty && user.isNotEmpty && pass.isNotEmpty) {
            try {
              final liveApi = host + '/player_api.php?username=' + user + '&password=' + pass + '&action=get_live_streams';
              final liveRes = await http.get(Uri.parse(liveApi)).timeout(const Duration(seconds: 6));
              if (liveRes.statusCode == 200) {
                var streamList = jsonDecode(liveRes.body);
                if (streamList is List) {
                  for (var c in streamList) {
                    final name = (c['name'] ?? '').toString();
                    final lower = name.toLowerCase();
                    if (sportsKeywords.any((k) => lower.contains(k))) {
                      final streamId = c['stream_id'];
                      sports.add({
                        'name': name,
                        'isDirectUrl': true,
                        'url': host + '/live/' + user + '/' + pass + '/' + streamId.toString() + '.ts',
                        'isHindi': lower.contains('hindi') || lower.contains('hin'),
                      });
                    }
                  }
                }
              }
            } catch (_) {}
          }
        }
      }
    }

    sports.sort((a, b) => (b['isHindi'] == true ? 1 : 0).compareTo(a['isHindi'] == true ? 1 : 0));
    return sports;
  }

  static Future getLiveChannelUrl(dynamic channel) async {
    return channel['url']?.toString();
  }
}
