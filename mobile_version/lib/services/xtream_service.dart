import 'dart:convert';
import 'package:http/http.dart' as http;
import 'tmdb_service.dart';

class XtreamCredentials {
  final String name;
  final String host;
  final String username;
  final String password;

  const XtreamCredentials({
    required this.name,
    required this.host,
    required this.username,
    required this.password,
  });

  bool get isValid => host.isNotEmpty && username.isNotEmpty && password.isNotEmpty;
}

class XtreamService {
  final String gistRawUrl;
  final Map<String, String> headers;

  List<XtreamCredentials> _accounts = [];
  final Map<String, List<dynamic>> _vodCache = {};
  final Map<String, List<dynamic>> _seriesCache = {};

  XtreamService({
    String? gistRawUrl,
    Map<String, String>? headers,
  })  : gistRawUrl = (gistRawUrl ?? AppConfig.gistUrl).trim(),
        headers = headers ?? const {
          'User-Agent': 'IPTVSmartersPro/1.0.0 (Linux; Android 12)',
          'Accept': '*/*',
        };

  List<XtreamCredentials> get accounts => List.unmodifiable(_accounts);

  Future<bool> initFromGist({bool forceRefresh = false}) async {
    final targetGist = gistRawUrl.isNotEmpty ? gistRawUrl : AppConfig.gistUrl.trim();
    if (targetGist.isEmpty) return false;

    if (!forceRefresh && _accounts.isNotEmpty) {
      return true;
    }

    try {
      final sep = targetGist.contains('?') ? '&' : '?';
      final uri = Uri.parse('$targetGist${sep}t=${DateTime.now().millisecondsSinceEpoch}');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return false;

      final decoded = jsonDecode(res.body);
      final parsed = <XtreamCredentials>[];

      void extractFromProvider(dynamic entry) {
        if (entry is! Map) return;
        final type = (entry['type'] ?? '').toString().toLowerCase();
        final hasXtreamKey = entry['xc_host'] != null ||
            entry['xc_username'] != null ||
            entry['host'] != null;
        if (type != 'xtream' && !hasXtreamKey) return;

        final host = (entry['xc_host'] ?? entry['host'] ?? entry['server'] ?? entry['url'] ?? '')
            .toString()
            .trim()
            .replaceAll(RegExp(r'/+$'), '');
        final user = (entry['xc_username'] ?? entry['username'] ?? '').toString().trim();
        final pass = (entry['xc_password'] ?? entry['password'] ?? '').toString().trim();
        final name = (entry['name'] ?? 'Xtream IPTV').toString().trim();

        final cred = XtreamCredentials(
          name: name.isEmpty ? 'Xtream IPTV' : name,
          host: host,
          username: user,
          password: pass,
        );
        if (cred.isValid) {
          parsed.add(cred);
        }
      }

      if (decoded is Map) {
        final providers = decoded['active_providers'] ?? decoded['providers'];
        if (providers is List) {
          for (final p in providers) {
            extractFromProvider(p);
          }
        }
        extractFromProvider(decoded);
      } else if (decoded is List) {
        for (final p in decoded) {
          extractFromProvider(p);
        }
      }

      if (forceRefresh) {
        _vodCache.clear();
        _seriesCache.clear();
      }
      _accounts = parsed;
      return _accounts.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  String _sanitizeTitle(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'\(\d{4}\)|\[.*?\]'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .trim();
  }

  bool _isHindi(String text) {
    final l = text.toLowerCase();
    return l.contains('hindi') ||
        l.contains('dubbed') ||
        l.contains('dual') ||
        l.contains('multi') ||
        l.contains('hin');
  }

  Future<List<dynamic>> _loadVodList(XtreamCredentials acc) async {
    if (_vodCache.containsKey(acc.host)) return _vodCache[acc.host]!;
    final uri = Uri.parse('${acc.host}/player_api.php').replace(
      queryParameters: {
        'username': acc.username,
        'password': acc.password,
        'action': 'get_vod_streams',
      },
    );
    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      if (decoded is List) {
        _vodCache[acc.host] = decoded;
        return decoded;
      }
    }
    return const [];
  }

  Future<List<dynamic>> _loadSeriesList(XtreamCredentials acc) async {
    if (_seriesCache.containsKey(acc.host)) return _seriesCache[acc.host]!;
    final uri = Uri.parse('${acc.host}/player_api.php').replace(
      queryParameters: {
        'username': acc.username,
        'password': acc.password,
        'action': 'get_series',
      },
    );
    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      if (decoded is List) {
        _seriesCache[acc.host] = decoded;
        return decoded;
      }
    }
    return const [];
  }

  Future<List>> getMovieStreams({
    required String movieTitle,
    String? tmdbId,
  }) async {
    final ready = await initFromGist();
    if (!ready) return const [];

    final cleanQuery = _sanitizeTitle(movieTitle);
    final cleanTmdb = (tmdbId ?? '').trim();
    final matches = >[];

    for (final acc in _accounts) {
      try {
        final vodList = await _loadVodList(acc);
        for (final vod in vodList) {
          if (vod is! Map) continue;
          final vodName = (vod['name'] ?? '').toString();
          final vodTmdb = (vod['tmdb_id'] ?? vod['tmdb'] ?? '').toString().trim();
          final sanVod = _sanitizeTitle(vodName);

          final idMatch = cleanTmdb.isNotEmpty && vodTmdb == cleanTmdb;
          final titleMatch = cleanQuery.length >= 2 &&
              sanVod.isNotEmpty &&
              (sanVod == cleanQuery ||
                  sanVod.contains(cleanQuery) ||
                  (sanVod.length >= 3 && cleanQuery.contains(sanVod)));

          if (idMatch || titleMatch) {
            final streamId = (vod['stream_id'] ?? '').toString().trim();
            if (streamId.isEmpty) continue;
            final ext = (vod['container_extension'] ?? 'mp4').toString().trim().ifEmpty('mp4');
            final url = '${acc.host}/movie/${acc.username}/${acc.password}/$streamId.$ext';
            final hindi = _isHindi('$vodName ${vod['category_name'] ?? ''}');

            matches.add({
              'server': acc.name,
              'title': vodName.isEmpty ? movieTitle : vodName,
              'url': url,
              'isHindi': hindi,
              'isXtream': true,
            });
          }
        }
      } catch (_) {}
    }

    matches.sort((a, b) {
      final aH = a['isHindi'] == true ? 1 : 0;
      final bH = b['isHindi'] == true ? 1 : 0;
      return bH.compareTo(aH);
    });

    return matches;
  }

  Future<String?> getMovieStreamUrl({
    required String movieTitle,
    String? tmdbId,
  }) async {
    final streams = await getMovieStreams(movieTitle: movieTitle, tmdbId: tmdbId);
    if (streams.isEmpty) return null;
    return streams.first['url'] as String?;
  }

  Future<List>> getSeriesEpisodeStreams({
    required String seriesTitle,
    required int seasonNumber,
    required int episodeNumber,
    String? tmdbId,
  }) async {
    final ready = await initFromGist();
    if (!ready) return const [];

    final cleanQuery = _sanitizeTitle(seriesTitle);
    final cleanTmdb = (tmdbId ?? '').trim();
    final results = >[];

    for (final acc in _accounts) {
      try {
        final seriesList = await _loadSeriesList(acc);
        for (final s in seriesList) {
          if (s is! Map) continue;
          final sName = (s['name'] ?? '').toString();
          final sTmdb = (s['tmdb_id'] ?? s['tmdb'] ?? '').toString().trim();
          final sanSeries = _sanitizeTitle(sName);

          final idMatch = cleanTmdb.isNotEmpty && sTmdb == cleanTmdb;
          final titleMatch = cleanQuery.length >= 2 &&
              sanSeries.isNotEmpty &&
              (sanSeries == cleanQuery ||
                  sanSeries.contains(cleanQuery) ||
                  (sanSeries.length >= 3 && cleanQuery.contains(sanSeries)));

          if (!idMatch && !titleMatch) continue;

          final seriesId = (s['series_id'] ?? '').toString().trim();
          if (seriesId.isEmpty) continue;

          final infoUri = Uri.parse('${acc.host}/player_api.php').replace(
            queryParameters: {
              'username': acc.username,
              'password': acc.password,
              'action': 'get_series_info',
              'series_id': seriesId,
            },
          );
          final infoRes = await http.get(infoUri, headers: headers).timeout(const Duration(seconds: 15));
          if (infoRes.statusCode != 200) continue;

          final infoData = jsonDecode(infoRes.body);
          if (infoData is! Map) continue;
          final episodesMap = infoData['episodes'];
          if (episodesMap is! Map) continue;

          final seasonEps = episodesMap[seasonNumber.toString()];
          if (seasonEps is! List) continue;

          for (final ep in seasonEps) {
            if (ep is! Map) continue;
            final epNumStr = (ep['episode_num'] ?? '').toString().trim();
            if (epNumStr != episodeNumber.toString()) continue;

            final epId = (ep['id'] ?? '').toString().trim();
            if (epId.isEmpty) continue;
            final ext = (ep['container_extension'] ?? 'mp4').toString().trim().ifEmpty('mp4');
            final epTitle = (ep['title'] ?? '').toString().trim();
            final label = epTitle.isNotEmpty
                ? '$sName • S${seasonNumber}E$episodeNumber - $epTitle'
                : '$sName • S${seasonNumber}E$episodeNumber';
            final hindi = _isHindi('$sName $epTitle ${s['category_name'] ?? ''}');

            results.add({
              'server': acc.name,
              'title': label,
              'url': '${acc.host}/series/${acc.username}/${acc.password}/$epId.$ext',
              'isHindi': hindi,
              'isXtream': true,
            });
          }
        }
      } catch (_) {}
    }

    results.sort((a, b) {
      final aH = a['isHindi'] == true ? 1 : 0;
      final bH = b['isHindi'] == true ? 1 : 0;
      return bH.compareTo(aH);
    });

    return results;
  }

  Future<String?> getSeriesEpisodeUrl({
    required String seriesTitle,
    required int seasonNumber,
    required int episodeNumber,
    String? tmdbId,
  }) async {
    final streams = await getSeriesEpisodeStreams(
      seriesTitle: seriesTitle,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      tmdbId: tmdbId,
    );
    if (streams.isEmpty) return null;
    return streams.first['url'] as String?;
  }
}

extension _NonEmptyStringExtension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}