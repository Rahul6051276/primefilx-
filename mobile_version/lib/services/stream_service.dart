import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_settings_service.dart';
import 'tmdb_service.dart';

class StreamLink {
  final String providerName;
  final String title;
  final String url;
  final String quality;
  final bool isHindi;
  final Map<String, String> headers;

  StreamLink({
    required this.providerName,
    required this.title,
    required this.url,
    this.quality = 'HD',
    this.isHindi = false,
    this.headers = const {},
  });

  Map<String, dynamic> toPlayerMap() {
    return {
      'server': providerName,
      'title': title,
      'url': url,
      'quality': quality,
      'isHindi': isHindi,
    };
  }
}

class StreamService {
  static List> _cachedProviders = [];
  static final Map<String, List<dynamic>> _xtreamVodCache = {};
  static final Map<String, List<dynamic>> _xtreamSeriesCache = {};

  static Future<int> saveAndConnectGistUrl(String rawUrl) async {
    await AppSettingsService.setGistUrl(rawUrl);
    _cachedProviders = [];
    _xtreamVodCache.clear();
    _xtreamSeriesCache.clear();
    final providers = await loadProviders(forceRefresh: true);
    return providers.length;
  }

  static Future<List>> loadProviders({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedProviders.isNotEmpty) {
      return _cachedProviders;
    }

    final gistUrl = await AppSettingsService.getGistUrl();
    if (gistUrl.isEmpty) return [];

    try {
      final sep = gistUrl.contains('?') ? '&' : '?';
      final uri = Uri.parse('$gistUrl${sep}t=${DateTime.now().millisecondsSinceEpoch}');
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        final List<dynamic> rawList;
        if (decoded is List) {
          rawList = decoded;
        } else if (decoded is Map) {
          rawList = (decoded['active_providers'] ?? decoded['providers'] ?? []) as List;
        } else {
          rawList = const [];
        }

        _cachedProviders = rawList
            .whereType()
            .map>((e) => Map<String, dynamic>.from(e))
            .toList();
        return _cachedProviders;
      }
    } catch (_) {}
    return [];
  }

  static Stream<StreamLink> fetchStreams({
    required int tmdbId,
    required String title,
    required bool isTv,
    int? season,
    int? episode,
  }) {
    final controller = StreamController<StreamLink>();

    () async {
      try {
        final providers = await loadProviders();
        if (providers.isEmpty) {
          await controller.close();
          return;
        }

        final imdbId = await TmdbService.getImdbId(tmdbId, isTv);
        final List<Future<void>> tasks = [];

        for (final provider in providers) {
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

  static Future<void> _fetchFromStremio({
    required Map<String, dynamic> provider,
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

          final Map<String, String> headers = {};
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

  static Future<void> _fetchFromXtream({
    required Map<String, dynamic> provider,
    required String title,
    required String tmdbId,
    required bool isTv,
    int? season,
    int? episode,
    required void Function(StreamLink) onFound,
  }) async {
    try {
      final name = (provider['name'] ?? 'Xtream').toString();
      String host = (provider['xc_host'] ?? provider['host'] ?? '').toString().trim();
      final user = (provider['xc_username'] ?? provider['username'] ?? '').toString().trim();
      final pass = (provider['xc_password'] ?? provider['password'] ?? '').toString().trim();

      if (host.isEmpty || user.isEmpty || pass.isEmpty) return;
      host = host.replaceAll(RegExp(r'/+$'), '');

      final cacheKey = '$host|$user';
      final target = _normalize(title);

      if (!isTv) {
        List<dynamic> vodList;
        if (_xtreamVodCache.containsKey(cacheKey)) {
          vodList = _xtreamVodCache[cacheKey]!;
        } else {
          final uri = Uri.parse(
            '$host/player_api.php?username=$user&password=$pass&action=get_vod_streams',
          );
          final res = await http.get(uri).timeout(const Duration(seconds: 20));
          if (res.statusCode != 200) return;
          final decoded = json.decode(res.body);
          vodList = decoded is List ? decoded : const [];
          _xtreamVodCache[cacheKey] = vodList;
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
              ));
              matched++;
              if (matched >= 5) break;
            }
          }
        }
      } else {
        List<dynamic> seriesList;
        if (_xtreamSeriesCache.containsKey(cacheKey)) {
          seriesList = _xtreamSeriesCache[cacheKey]!;
        } else {
          final uri = Uri.parse(
            '$host/player_api.php?username=$user&password=$pass&action=get_series',
          );
          final res = await http.get(uri).timeout(const Duration(seconds: 20));
          if (res.statusCode != 200) return;
          final decoded = json.decode(res.body);
          seriesList = decoded is List ? decoded : const [];
          _xtreamSeriesCache[cacheKey] = seriesList;
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
            '$host/player_api.php?username=$user&password=$pass&action=get_series_info&series_id=$seriesId',
          );
          final infoRes = await http.get(infoUri).timeout(const Duration(seconds: 15));
          if (infoRes.statusCode != 200) continue;

          final infoData = json.decode(infoRes.body);
          final episodesMap = infoData is Map ? infoData['episodes'] : null;
          if (episodesMap is Map) {
            final seasonKey = (season ?? 1).toString();
            final epList = episodesMap[seasonKey] as List? ?? [];
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