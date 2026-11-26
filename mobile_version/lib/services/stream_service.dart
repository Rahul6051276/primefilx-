import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'tmdb_service.dart';

class MobileStreamService {
  static const String renderApiBase =
      'https://tmdb-embed-api-4.onrender.com';

  static Future> _fetchXtreamConfig() async {
    String endpoint = AppConfig.gistUrl.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      final customUrl = (prefs.getString('custom_gist_url') ?? '').trim();
      if (customUrl.isNotEmpty) {
        endpoint = customUrl;
      }
    } catch (_) {}

    if (endpoint.isNotEmpty) {
      try {
        final sep = endpoint.contains('?') ? '&' : '?';
        final res = await http
            .get(Uri.parse('$endpoint${sep}t=${DateTime.now().millisecondsSinceEpoch}'))
            .timeout(const Duration(seconds: 6));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is Map) {
            String host = (data['xc_host'] ?? data['host'] ?? '').toString().trim();
            String username = (data['xc_username'] ?? data['username'] ?? '').toString().trim();
            String password = (data['xc_password'] ?? data['password'] ?? '').toString().trim();

            final provs = data['active_providers'] ?? data['providers'];
            if ((host.isEmpty || username.isEmpty || password.isEmpty) && provs is List) {
              for (final p in provs) {
                if (p is Map && (p['type'] == 'xtream' || p['xc_host'] != null)) {
                  host = (p['xc_host'] ?? p['server'] ?? p['url'] ?? '').toString().trim();
                  username = (p['xc_username'] ?? p['username'] ?? '').toString().trim();
                  password = (p['xc_password'] ?? p['password'] ?? '').toString().trim();
                  if (host.isNotEmpty && username.isNotEmpty && password.isNotEmpty) break;
                }
              }
            }

            if (host.isNotEmpty && username.isNotEmpty && password.isNotEmpty) {
              return {
                'host': host.replaceAll(RegExp(r'/+$'), ''),
                'username': username,
                'password': password,
              };
            }
          }
        }
      } catch (_) {}
    }

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
    final List<dynamic> resolved = [];

    final targetTmdbId = (item['tmdb_id'] ?? item['id'] ?? '').toString().trim();
    final isTv = item['isTv'] == true || season != null;
    final movieTitle = (item['title'] ?? item['name'] ?? '').toString().toLowerCase();

    final cleanTitle =
        movieTitle.replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim();

    final targetSeason = season ?? 1;
    final targetEpisode = episode ?? 1;

    // 1. Render Cloud API Streams
    if (targetTmdbId.isNotEmpty) {
      try {
        final mediaType = isTv ? 'series' : 'movie';

        final apiUrl = isTv
            ? '$renderApiBase/api/streams/$mediaType/$targetTmdbId?season=$targetSeason&episode=$targetEpisode'
            : '$renderApiBase/api/streams/$mediaType/$targetTmdbId';

        final res = await http
            .get(Uri.parse(apiUrl))
            .timeout(const Duration(seconds: 6));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);

          final List<dynamic> streamList = [];

          if (data is List) {
            streamList.addAll(data);
          } else if (data is Map && data['streams'] is List) {
            streamList.addAll(data['streams']);
          } else if (data is Map) {
            data.forEach((key, value) {
              if (value is List) streamList.addAll(value);
            });
          }

          for (var s in streamList) {
            if (s is! Map) continue;
            final sUrl = (s['url'] ?? '').toString().trim();

            if (sUrl.isNotEmpty) {
              final sTitle =
                  (s['title'] ?? ('$movieTitle - ${s['name'] ?? 'HD'}'))
                      .toString();

              final provName =
                  (s['provider'] ?? s['name'] ?? 'Render Cloud').toString();

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

      final xcHost = (config['host'] ?? '').toString().replaceAll(RegExp(r'/+$'), '');
      final xcUser = (config['username'] ?? '').toString();
      final xcPass = (config['password'] ?? '').toString();

      if (xcHost.isNotEmpty && xcUser.isNotEmpty && xcPass.isNotEmpty) {
        if (!isTv) {
          final vodUrl =
              '$xcHost/player_api.php?username=$xcUser&password=$xcPass&action=get_vod_streams';

          final vodRes = await http
              .get(Uri.parse(vodUrl))
              .timeout(const Duration(seconds: 12));

          if (vodRes.statusCode == 200) {
            final vodData = jsonDecode(vodRes.body);

            if (vodData is List && vodData.isNotEmpty) {
              final matches = vodData.where((m) {
                if (m is! Map) return false;
                final name = (m['name'] ?? '').toString().toLowerCase();

                final cleanNameReplaced =
                    name.replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim();

                if (cleanTitle.isEmpty) return false;

                return cleanNameReplaced.contains(cleanTitle) ||
                    cleanTitle.contains(cleanNameReplaced);
              }).toList();

              for (var matched in matches) {
                final streamId = matched['stream_id'];
                final container = matched['container_extension'] ?? 'mp4';
                final rawName = matched['name'] ?? 'Xtream Movie';

                final streamUrl =
                    '$xcHost/movie/$xcUser/$xcPass/$streamId.$container';

                final isHindi = isHindiStream(rawName.toString());

                resolved.add({
                  'server': 'Xtream - IPTV',
                  'title': isHindi
                      ? '🎬 $rawName [Hindi Dubbed]'
                      : '🎬 $rawName [Original]',
                  'url': streamUrl,
                  'isHindi': isHindi,
                });
              }
            }
          }
        } else {
          final seriesUrl =
              '$xcHost/player_api.php?username=$xcUser&password=$xcPass&action=get_series';

          final seriesRes = await http
              .get(Uri.parse(seriesUrl))
              .timeout(const Duration(seconds: 10));

          if (seriesRes.statusCode == 200) {
            final seriesJson = jsonDecode(seriesRes.body);

            if (seriesJson is List) {
              dynamic matchedSeries;
              for (final s in seriesJson) {
                if (s is Map &&
                    cleanTitle.isNotEmpty &&
                    (s['name'] ?? '').toString().toLowerCase().contains(cleanTitle)) {
                  matchedSeries = s;
                  break;
                }
              }

              if (matchedSeries != null) {
                final seriesId = matchedSeries['series_id'];

                final infoUrl =
                    '$xcHost/player_api.php?username=$xcUser&password=$xcPass&action=get_series_info&series_id=$seriesId';

                final infoRes = await http
                    .get(Uri.parse(infoUrl))
                    .timeout(const Duration(seconds: 10));

                if (infoRes.statusCode == 200) {
                  final infoData = jsonDecode(infoRes.body);

                  if (infoData is Map && infoData['episodes'] != null) {
                    final episodesMap = infoData['episodes'];

                    final seasonEpisodes =
                        episodesMap is Map ? episodesMap[targetSeason.toString()] : null;

                    if (seasonEpisodes is List) {
                      dynamic targetEp;
                      for (final e in seasonEpisodes) {
                        if (e is Map &&
                            e['episode_num'].toString() == targetEpisode.toString()) {
                          targetEp = e;
                          break;
                        }
                      }

                      if (targetEp != null) {
                        final epId = targetEp['id'];

                        final container =
                            targetEp['container_extension'] ?? 'mp4';

                        final epTitle =
                            targetEp['title'] ?? 'S${targetSeason}E$targetEpisode';

                        final epUrl =
                            '$xcHost/series/$xcUser/$xcPass/$epId.$container';

                        final isHindi = isHindiStream(epTitle.toString()) ||
                            isHindiStream(
                                matchedSeries['name']?.toString() ?? '');

                        resolved.add({
                          'server': 'Xtream - IPTV Series',
                          'title': isHindi
                              ? '📺 $epTitle [Hindi Dubbed]'
                              : '📺 $epTitle [Original]',
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
      }
    } catch (_) {}

    // Fallback if empty
    if (resolved.isEmpty && targetTmdbId.isNotEmpty) {
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
    resolved.sort(
      (a, b) => (b['isHindi'] == true ? 1 : 0)
          .compareTo(a['isHindi'] == true ? 1 : 0),
    );

    return resolved;
  }
}