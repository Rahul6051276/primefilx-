import 'dart:convert';
import 'package:http/http.dart' as http;

class TmdbService {
  static const String apiKey = String.fromEnvironment(
    'TMDB_API_KEY',
    defaultValue: '',
  );

  static const String _baseUrl = 'https://api.themoviedb.org/3';
  static const String imageBaseUrl = 'https://image.tmdb.org/t/p/w500';
  static const String backdropBaseUrl = 'https://image.tmdb.org/t/p/w1280';

  static String getPosterUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    return '$imageBaseUrl$path';
  }

  static String getBackdropUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    return '$backdropBaseUrl$path';
  }

  static Future<List>> _fetchList(
    String endpoint, {
    String? forcedMediaType,
  }) async {
    if (apiKey.isEmpty) return [];
    try {
      final separator = endpoint.contains('?') ? '&' : '?';
      final url = Uri.parse('$_baseUrl$endpoint${separator}api_key=$apiKey');
      final res = await http.get(url).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final results = (data['results'] as List? ?? []);
        return results.map>((item) {
          final map = Map<String, dynamic>.from(item);
          if (forcedMediaType != null) {
            map['media_type'] = forcedMediaType;
          }
          return map;
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List>> getTrendingMovies() =>
      _fetchList('/trending/movie/week', forcedMediaType: 'movie');

  static Future<List>> getPopularMovies() =>
      _fetchList('/movie/popular', forcedMediaType: 'movie');

  static Future<List>> getTopRatedMovies() =>
      _fetchList('/movie/top_rated', forcedMediaType: 'movie');

  static Future<List>> getTrendingTv() =>
      _fetchList('/trending/tv/week', forcedMediaType: 'tv');

  static Future<List>> getPopularTv() =>
      _fetchList('/tv/popular', forcedMediaType: 'tv');

  static Future<List>> searchMulti(String query) async {
    if (query.trim().isEmpty) return [];
    final encoded = Uri.encodeQueryComponent(query.trim());
    final list = await _fetchList('/search/multi?query=$encoded');
    return list
        .where((e) => e['media_type'] == 'movie' || e['media_type'] == 'tv')
        .toList();
  }

  static Future<String?> getImdbId(int tmdbId, bool isTv) async {
    if (apiKey.isEmpty) return null;
    try {
      final type = isTv ? 'tv' : 'movie';
      final url = Uri.parse(
        '$_baseUrl/$type/$tmdbId/external_ids?api_key=$apiKey',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return data['imdb_id'] as String?;
      }
    } catch (_) {}
    return null;
  }

  static Future<List>> getTvSeasons(int tvId) async {
    if (apiKey.isEmpty) return [];
    try {
      final url = Uri.parse('$_baseUrl/tv/$tvId?api_key=$apiKey');
      final res = await http.get(url).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final seasons = (data['seasons'] as List? ?? []);
        return seasons
            .map>((s) => Map<String, dynamic>.from(s))
            .where((s) => (s['season_number'] ?? 0) > 0)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List>> getSeasonEpisodes(
    int tvId,
    int seasonNumber,
  ) async {
    if (apiKey.isEmpty) return [];
    try {
      final url = Uri.parse(
        '$_baseUrl/tv/$tvId/season/$seasonNumber?api_key=$apiKey',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final episodes = (data['episodes'] as List? ?? []);
        return episodes
            .map>((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }
}