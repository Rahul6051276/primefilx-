import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_settings_service.dart';
import 'stalker_service.dart';
import 'tmdb_service.dart';

class StreamLink {
  final String providerName;
  final String title;
  final String url;
  final String quality;
  final bool isHindi;
  final Map headers;
  final String stalkerEndpoint;
  final String stalkerCmd;
  final String stalkerMediaType;
  final int stalkerEpisode;

  StreamLink({
    required this.providerName,
    required this.title,
    required this.url,
    this.quality = 'HD',
    this.isHindi = false,
    this.headers = const {},
    this.stalkerEndpoint = '',
    this.stalkerCmd = '',
    this.stalkerMediaType = 'vod',
    this.stalkerEpisode = 0,
  });

  Map toPlayerMap() {
    return {
      'server': providerName,
      'title': title,
      'url': url,
      'quality': quality,
      'isHindi': isHindi,
      'headers': headers,
      'stalkerEndpoint': stalkerEndpoint,
      'stalkerCmd': stalkerCmd,
      'stalkerMediaType': stalkerMediaType,
      'stalkerEpisode': stalkerEpisode,
    };
  }
}

class StreamService {
  static List _cachedProviders = [];
  static final Map _xtreamVodCache = {};
  static final Map _xtreamSeriesCache = {};

  static const Map<String, String> _iptvHeaders = {
    'User-Agent': 'IPTVSmartersPro',
    'Accept': '*/*',
  };

  static Future saveAndConnectGistUrl(String rawUrl) async {
    await AppSettingsService.setGistUrl(rawUrl);
    _cachedProviders = [];
    _xtreamVodCache.clear();
    _xtreamSeriesCache.clear();
    final providers = await loadProviders(forceRefresh: true);
    return providers.length;
  }

  static Future loadProviders({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedProviders.isNotEmpty) {
      return _cachedProviders;
    }

    final List combined = [];

    final directXtream = await AppSettingsService.getDirectXtream();
    if ((directXtream['url'] ?? '').isNotEmpty &&
        (directXtream['username'] ?? '').isNotEmpty &&
        (directXtream['password'] ?? '').isNotEmpty) {
      combined.add({
        'name': 'Xtream IPTV (Direct)',
        'type': 'xtream',
        'xc_host': directXtream['url'],
        'xc_username': directXtream['username'],
        'xc_password': directXtream['password'],
      });
    }

    final directStalker = await AppSettingsService.getDirectStalker();
    if ((directStalker['url'] ?? '').isNotEmpty &&
        (directStalker['mac'] ?? '').isNotEmpty) {
      combined.add({
        'name': 'Stalker Portal (Direct)',
        'type': 'stalker',
        'portal_url': directStalker['url'],
        'mac': directStalker['mac'],
        'device_id1': directStalker['device_id1'] ?? '',
        'device_id2': directStalker['device_id2'] ?? '',
      });
    }

    final gistUrl = await AppSettingsService.getGistUrl();
    if (gistUrl.isNotEmpty) {
      try {
        final sep = gistUrl.contains('?') ? '&' : '?';
        final uri =
            Uri.parse('$gistUrl${sep}t=${DateTime.now().millisecondsSinceEpoch}');
        final res = await http.get(uri).timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final decoded = json.decode(res.body);
          List rawList = [];
          if (decoded is List) {
            rawList = decoded;
          } else if (decoded is Map) {
            rawList =
                (decoded['active_providers'] ?? decoded['providers'] ?? []) as List;
          }

          for (final e in rawList) {
            if (e is Map) {
              combined.add(Map<String, dynamic>.from(e));
            }
          }
        }
      } catch (_) {}
    }

    _cachedProviders = combined;
    return _cachedProviders;
  }

  static Stream fetchStreams({
    required int tmdbId,
    required String title,
    required bool isTv,
    int? season,
    int? episode,
  }) {
    final controller = StreamController();

    () async {
      try {
        final providers = await loadProviders();
        if (providers.isEmpty) {
          await controller.close();
          return;
        }

        String? imdbId;
        try {
          imdbId = await TmdbService.getImdbId(tmdbId, isTv)
              .timeout(const Duration(seconds: 6));
        } catch (_) {}

        final tasks = [Future.value()];
        tasks.clear();

        for (final p in providers) {
          final provider = Map<String, dynamic>.from(p as Map);
          final type = (provider['type'] ?? '').toString().toLowerCase();
          if (type == 'stremio' && imdbId != null && imdbId.isNotEmpty) {
            tasks.add(_fetchFromStremio(
              provider: provider,
              imdbId: imdbId,
              isTv: isTv,
              season: season,
              episode: episode,
              onFound: (link) {
                if (!controller.isClosed) controller.add(link);
              },
            ));
          } else if (type == 'xtream') {
            tasks.add(_fetchFromXtream(
              provider: provider,
              title: title,
              tmdbId: tmdbId.toString(),
              isTv: isTv,
              season: season,
              episode: episode,
              onFound: (link) {
                if (!controller.isClosed) controller.add(link);
              },
            ));
          } else if (type == 'stalker') {
            tasks.add(_fetchFromStalker(
              provider: provider,
              title: title,
              isTv: isTv,
              season: season,
              episode: episode,
              onFound: (link) {
                if (!controller.isClosed) controller.add(link);
              },
            ));
          }
        }

        await Future.wait(tasks);
      } catch (_) {} finally {
        if (!controller.isClosed) {
          await controller.close();
        }
      }
    }();

    return controller.stream;
  }

  static Future _fetchFromStremio({
    required Map provider,
    required String imdbId,
    required bool isTv,
    int? season,
    int? episode,
    required void Function(StreamLink) onFound,
  }) async {
    try {
      final name = (provider['name'] ?? 'Stremio').toString();
      final manifestUrl = (provider['url'] ?? '').toString().trim();
      if (manifestUrl.isEmpty) return;

      final baseUrl = manifestUrl.replaceAll(RegExp(r'/manifest\.json$'), '');
      final streamPath = isTv
          ? 'series/$imdbId:${season ?? 1}:${episode ?? 1}.json'
          : 'movie/$imdbId.json';

      final uri = Uri.parse('$baseUrl/stream/$streamPath');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final streams = (data['streams'] as List? ?? []);

        for (final s in streams) {
          if (s is! Map) continue;
          final streamUrl = (s['url'] ?? '').toString().trim();
          if (streamUrl.isEmpty || !streamUrl.startsWith('http')) continue;

          final rawTitle =
              (s['title'] ?? s['description'] ?? s['name'] ?? 'HD Stream')
                  .toString()
                  .replaceAll('\n', ' • ');

          final Map headers = {};
          final proxyHeaders = s['behaviorHints']?['proxyHeaders']?['request'];
          if (proxyHeaders is Map) {
            proxyHeaders.forEach((k, v) {
              headers[k.toString()] = v.toString();
            });
          }

          onFound(StreamLink(
            providerName: name,
            title: rawTitle,
            url: streamUrl,
            quality: _extractQuality(rawTitle),
            isHindi: _isHindi('$name $rawTitle'),
            headers: headers,
          ));
        }
      }
    } catch (_) {}
  }

  static Future _fetchFromXtream({
    required Map provider,
    required String title,
    required String tmdbId,
    required bool isTv,
    int? season,
    int? episode,
    required void Function(StreamLink) onFound,
  }) async {
    try {
      final name = (provider['name'] ?? 'Xtream').toString();
      String host = (provider['xc_host'] ?? provider['host'] ?? provider['url'] ?? '')
          .toString()
          .trim();
      final user =
          (provider['xc_username'] ?? provider['username'] ?? '').toString().trim();
      final pass =
          (provider['xc_password'] ?? provider['password'] ?? '').toString().trim();

      if (host.isEmpty || user.isEmpty || pass.isEmpty) return;
      if (!host.startsWith('http://') && !host.startsWith('https://')) {
        host = 'http://$host';
      }
      host = host.replaceAll(RegExp(r'/+$'), '');

      final cacheKey = '$host|$user';
      final target = _normalize(title);

      if (!isTv) {
        List vodList;
        if (_xtreamVodCache.containsKey(cacheKey)) {
          vodList = _xtreamVodCache[cacheKey]!;
        } else {
          final uri = Uri.parse(
            '$host/player_api.php?username=${Uri.encodeQueryComponent(user)}'
            '&password=${Uri.encodeQueryComponent(pass)}&action=get_vod_streams',
          );
          final res = await http
              .get(uri, headers: _iptvHeaders)
              .timeout(const Duration(seconds: 35));
          if (res.statusCode != 200) return;
          final decoded = json.decode(res.body);
          vodList = decoded is List ? decoded : [];
          if (vodList.isNotEmpty) {
            _xtreamVodCache[cacheKey] = vodList;
          }
        }

        int matched = 0;
        for (final item in vodList) {
          if (item is! Map) continue;
          final itemName = (item['name'] ?? '').toString();
          final itemTmdb = (item['tmdb_id'] ?? item['tmdb'] ?? '').toString().trim();
          final idMatch = tmdbId.isNotEmpty && itemTmdb == tmdbId;
          if (idMatch || _isMatch(_normalize(itemName), target)) {
            final streamId = item['stream_id'];
            final ext = (item['container_extension'] ?? 'mp4').toString().trim();
            final safeExt = ext.isEmpty ? 'mp4' : ext;
            if (streamId != null) {
              onFound(StreamLink(
                providerName: name,
                title: itemName,
                url: '$host/movie/$user/$pass/$streamId.$safeExt',
                quality: _extractQuality(itemName),
                isHindi: _isHindi('$itemName ${item['category_name'] ?? ''}'),
                headers: _iptvHeaders,
              ));
              matched++;
              if (matched >= 6) break;
            }
          }
        }
      } else {
        List seriesList;
        if (_xtreamSeriesCache.containsKey(cacheKey)) {
          seriesList = _xtreamSeriesCache[cacheKey]!;
        } else {
          final uri = Uri.parse(
            '$host/player_api.php?username=${Uri.encodeQueryComponent(user)}'
            '&password=${Uri.encodeQueryComponent(pass)}&action=get_series',
          );
          final res = await http
              .get(uri, headers: _iptvHeaders)
              .timeout(const Duration(seconds: 35));
          if (res.statusCode != 200) return;
          final decoded = json.decode(res.body);
          seriesList = decoded is List ? decoded : [];
          if (seriesList.isNotEmpty) {
            _xtreamSeriesCache[cacheKey] = seriesList;
          }
        }

        for (final item in seriesList) {
          if (item is! Map) continue;
          final itemName = (item['name'] ?? '').toString();
          final itemTmdb = (item['tmdb_id'] ?? item['tmdb'] ?? '').toString().trim();
          final idMatch = tmdbId.isNotEmpty && itemTmdb == tmdbId;
          if (!idMatch && !_isMatch(_normalize(itemName), target)) continue;

          final seriesId = item['series_id'];
          if (seriesId == null) continue;

          final infoUri = Uri.parse(
            '$host/player_api.php?username=${Uri.encodeQueryComponent(user)}'
            '&password=${Uri.encodeQueryComponent(pass)}'
            '&action=get_series_info&series_id=$seriesId',
          );
          final infoRes = await http
              .get(infoUri, headers: _iptvHeaders)
              .timeout(const Duration(seconds: 20));
          if (infoRes.statusCode != 200) continue;

          final infoData = json.decode(infoRes.body);
          final episodesMap = infoData is Map ? infoData['episodes'] : null;
          if (episodesMap is Map) {
            final seasonKey = (season ?? 1).toString();
            final epList = (episodesMap[seasonKey] as List? ?? []);
            for (final ep in epList) {
              if (ep is! Map) continue;
              final epNum = int.tryParse(ep['episode_num'].toString()) ?? -1;
              if (epNum == (episode ?? 1)) {
                final epId = ep['id'];
                final ext = (ep['container_extension'] ?? 'mp4').toString().trim();
                final safeExt = ext.isEmpty ? 'mp4' : ext;
                if (epId != null) {
                  onFound(StreamLink(
                    providerName: name,
                    title: '$itemName • S${season ?? 1}E${episode ?? 1}',
                    url: '$host/series/$user/$pass/$epId.$safeExt',
                    quality: _extractQuality(itemName),
                    isHindi: _isHindi('$itemName ${item['category_name'] ?? ''}'),
                    headers: _iptvHeaders,
                  ));
                  return;
                }
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  static Future _fetchFromStalker({
    required Map provider,
    required String title,
    required bool isTv,
    int? season,
    int? episode,
    required void Function(StreamLink) onFound,
  }) async {
    try {
      final name = (provider['name'] ?? 'Stalker Portal').toString();
      final portalUrl =
          (provider['portal_url'] ?? provider['url'] ?? provider['host'] ?? '')
              .toString()
              .trim();
      final mac = (provider['mac'] ?? '').toString().trim();
      final dev1 = (provider['device_id1'] ?? provider['device_id'] ?? '')
          .toString()
          .trim();
      final dev2 = (provider['device_id2'] ?? '').toString().trim();

      if (portalUrl.isEmpty || mac.isEmpty) return;

      final items = await StalkerService.searchAndResolve(
        providerName: name,
        portalUrl: portalUrl,
        mac: mac,
        deviceId1: dev1,
        deviceId2: dev2,
        title: title,
        isTv: isTv,
        season: season,
        episode: episode,
      );

      for (final raw in items) {
        if (raw is! Map) continue;
        final streamTitle = (raw['title'] ?? title).toString();
        final streamUrl = (raw['url'] ?? '').toString();
        final headers = raw['headers'] is Map ? raw['headers'] as Map : const {};
        if (streamUrl.isNotEmpty) {
          onFound(StreamLink(
            providerName: name,
            title: streamTitle,
            url: streamUrl,
            quality: _extractQuality(streamTitle),
            isHindi: _isHindi('$name $streamTitle'),
            headers: headers,
            stalkerEndpoint: (raw['stalkerEndpoint'] ?? '').toString(),
            stalkerCmd: (raw['stalkerCmd'] ?? '').toString(),
            stalkerMediaType: (raw['stalkerMediaType'] ?? 'vod').toString(),
            stalkerEpisode: (raw['stalkerEpisode'] is int)
                ? raw['stalkerEpisode'] as int
                : 0,
          ));
        }
      }
    } catch (_) {}
  }

  static bool _isHindi(String text) {
    final l = text.toLowerCase();
    return l.contains('hindi') ||
        l.contains('dubbed') ||
        l.contains('dual') ||
        l.contains('multi') ||
        l.contains('hin');
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

  static String _extractQuality(String text) {
    final upper = text.toUpperCase();
    if (upper.contains('4K') || upper.contains('2160')) return '4K';
    if (upper.contains('1080')) return '1080p';
    if (upper.contains('720')) return '720p';
    return 'HD';
  }
}