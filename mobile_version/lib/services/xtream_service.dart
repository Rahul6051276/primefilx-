import 'dart:convert';
import 'package:http/http.dart' as http;

class XtreamService {
  // Gist URL jahan aapne JSON format me server, username, password rakha hai
  final String gistRawUrl;

  String? serverUrl;
  String? username;
  String? password;

  List<dynamic>? _cachedVodList;
  List<dynamic>? _cachedSeriesList;

  XtreamService({required this.gistRawUrl});

  // 1. GitHub Gist se credentials fetch karna
  Future<bool> initFromGist() async {
    try {
      final res = await http.get(Uri.parse(gistRawUrl));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        // Gist JSON format example:
        // {"server": "http://domain.com:8080", "username": "user", "password": "pass"}
        serverUrl = data['server']?.toString().replaceAll(RegExp(r'/+$'), '');
        username = data['username']?.toString();
        password = data['password']?.toString();
        return true;
      }
    } catch (e) {
      print('Gist fetch error: $e');
    }
    return false;
  }

  // 2. Title ko clean karna (taaki TMDB aur Xtream match ho sakein)
  String _sanitizeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .trim();
  }

  // 3. MOVIE STREAM LINK NIKALNA
  Future<String?> getMovieStreamUrl({required String movieTitle, String? tmdbId}) async {
    if (serverUrl == null) {
      final ok = await initFromGist();
      if (!ok) return null;
    }

    // VOD List load karna (agar pehle se cached nahi hai)
    if (_cachedVodList == null) {
      final url = Uri.parse('$serverUrl/player_api.php?username=$username&password=$password&action=get_vod_streams');
      try {
        final res = await http.get(url);
        if (res.statusCode == 200) {
          _cachedVodList = json.decode(res.body);
        }
      } catch (e) {
        print('VOD Load Error: $e');
        return null;
      }
    }

    if (_cachedVodList == null) return null;

    final cleanQuery = _sanitizeTitle(movieTitle);

    // Pehle TMDB ID se check karein (agar available ho)
    if (tmdbId != null && tmdbId.isNotEmpty) {
      final match = _cachedVodList!.firstWhere(
        (vod) => vod['tmdb_id']?.toString() == tmdbId,
        orElse: () => null,
      );
      if (match != null) {
        return '$serverUrl/movie/$username/$password/${match['stream_id']}.${match['container_extension'] ?? 'mp4'}';
      }
    }

    // Title se match karein
    for (var vod in _cachedVodList!) {
      final vodName = _sanitizeTitle(vod['name']?.toString() ?? '');
      if (vodName.contains(cleanQuery) || cleanQuery.contains(vodName)) {
        final streamId = vod['stream_id'];
        final ext = vod['container_extension'] ?? 'mp4';
        return '$serverUrl/movie/$username/$password/$streamId.$ext';
      }
    }

    return null;
  }

  // 4. WEB SERIES EPISODE LINK NIKALNA
  Future<String?> getSeriesEpisodeUrl({
    required String seriesTitle,
    required int seasonNumber,
    required int episodeNumber,
  }) async {
    if (serverUrl == null) {
      final ok = await initFromGist();
      if (!ok) return null;
    }

    // Series list load karna
    if (_cachedSeriesList == null) {
      final url = Uri.parse('$serverUrl/player_api.php?username=$username&password=$password&action=get_series');
      try {
        final res = await http.get(url);
        if (res.statusCode == 200) {
          _cachedSeriesList = json.decode(res.body);
        }
      } catch (e) {
        print('Series Load Error: $e');
        return null;
      }
    }

    if (_cachedSeriesList == null) return null;

    final cleanQuery = _sanitizeTitle(seriesTitle);
    dynamic targetSeries;

    for (var s in _cachedSeriesList!) {
      final sName = _sanitizeTitle(s['name']?.toString() ?? '');
      if (sName.contains(cleanQuery) || cleanQuery.contains(sName)) {
        targetSeries = s;
        break;
      }
    }

    if (targetSeries == null) return null;

    final seriesId = targetSeries['series_id'];

    // Series Info & Episodes fetch karna
    final infoUrl = Uri.parse('$serverUrl/player_api.php?username=$username&password=$password&action=get_series_info&series_id=$seriesId');
    try {
      final infoRes = await http.get(infoUrl);
      if (infoRes.statusCode == 200) {
        final infoData = json.decode(infoRes.body);
        final episodes = infoData['episodes'];
        if (episodes != null && episodes[seasonNumber.toString()] != null) {
          final seasonEps = episodes[seasonNumber.toString()] as List;
          final ep = seasonEps.firstWhere(
            (e) => e['episode_num'].toString() == episodeNumber.toString(),
            orElse: () => null,
          );
          if (ep != null) {
            final epId = ep['id'];
            final ext = ep['container_extension'] ?? 'mp4';
            return '$serverUrl/series/$username/$password/$epId.$ext';
          }
        }
      }
    } catch (e) {
      print('Episode Fetch Error: $e');
    }

    return null;
  }
}
