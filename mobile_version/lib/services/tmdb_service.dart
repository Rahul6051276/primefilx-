import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_settings_service.dart';

class TmdbService {
  static const String _baseUrl = 'https://api.themoviedb.org/3';
  static const String imageBaseUrl = 'https://image.tmdb.org/t/p/w500';
  static const String backdropBaseUrl = 'https://image.tmdb.org/t/p/w1280';

  static String getPosterUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '$imageBaseUrl$path';
  }

  static String getBackdropUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '$backdropBaseUrl$path';
  }

  static String _todayDate() {
    final now = DateTime.now();
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _monthsAgoDate(int months) {
    final dt = DateTime.now().subtract(Duration(days: months * 30));
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static Future<List>> _fetchList(
    String endpoint, {
    String? forcedMediaType,
  }) async {
    final apiKey = await AppSettingsService.getTmdbApiKey();
    if (apiKey.isEmpty) return [];

    try {
      final separator = endpoint.contains('?') ? '&' : '?';
      final url = Uri.parse('$_baseUrl$endpoint${separator}api_key=$apiKey');
      final res = await http.get(url).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final results = (data['results'] as List? ?? []);
        return results.map>((item) {
          final map = Map<String, dynamic>.from(item as Map);
          if (forcedMediaType != null) {
            map['media_type'] = forcedMediaType;
          }
          return map;
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List>> getLatestBollywoodMovies() {
    final today = _todayDate();
    final recent = _monthsAgoDate(12);
    return _fetchList(
      '/discover/movie?with_original_language=hi&region=IN&sort_by=primary_release_date.desc&primary_release_date.gte=$recent&primary_release_date.lte=$today&vote_count.gte=5',
      forcedMediaType: 'movie',
    );
  }

  static Future<List>> getLatestSouthMovies() {
    final today = _todayDate();
    final recent = _monthsAgoDate(12);
    return _fetchList(
      '/discover/movie?with_original_language=te|ta|ml|kn&region=IN&sort_by=primary_release_date.desc&primary_release_date.gte=$recent&primary_release_date.lte=$today&vote_count.gte=5',
      forcedMediaType: 'movie',
    );
  }

  static Future<List>> getLatestHollywoodMovies() {
    final today = _todayDate();
    final recent = _monthsAgoDate(8);
    return _fetchList(
      '/discover/movie?with_original_language=en&sort_by=popularity.desc&primary_release_date.gte=$recent&primary_release_date.lte=$today&vote_count.gte=50',
      forcedMediaType: 'movie',
    );
  }

  static Future<List>> getLatestHindiWebSeries() {
    final today = _todayDate();
    return _fetchList(
      '/discover/tv?with_original_language=hi&without_genres=10766,10767,10763,10764&with_watch_providers=8|119|122|237|232|220&watch_region=IN&sort_by=first_air_date.desc&first_air_date.lte=$today&vote_count.gte=3',
      forcedMediaType: 'tv',
    );
  }

  static Future<List>> getLatestNetflixWebSeries() {
    final today = _todayDate();
    return _fetchList(
      '/discover/tv?with_networks=213&without_genres=10766,10767,10763,10764&sort_by=popularity.desc&first_air_date.lte=$today',
      forcedMediaType: 'tv',
    );
  }

  static Future<List>> getLatestAmazonWebSeries() {
    final today = _todayDate();
    return _fetchList(
      '/discover/tv?with_networks=1024&without_genres=10766,10767,10763,10764&sort_by=popularity.desc&first_air_date.lte=$today',
      forcedMediaType: 'tv',
    );
  }

  static Future<List>> searchMulti(String query) async {
    if (query.trim().isEmpty) return [];
    final encoded = Uri.encodeQueryComponent(query.trim());
    final list = await _fetchList('/search/multi?query=$encoded');
    return list
        .where((e) => e['media_type'] == 'movie' || e['media_type'] == 'tv')
        .toList();
  }

  static Future<String?> getImdbId(int tmdbId, bool isTv) async {
    final apiKey = await AppSettingsService.getTmdbApiKey();
    if (apiKey.isEmpty) return null;
    try {
      final type = isTv ? 'tv' : 'movie';
      final url = Uri.parse('$_baseUrl/$type/$tmdbId/external_ids?api_key=$apiKey');
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return data['imdb_id'] as String?;
      }
    } catch (_) {}
    return null;
  }

  static Future<List>> getTvSeasons(int tvId) async {
    final apiKey = await AppSettingsService.getTmdbApiKey();
    if (apiKey.isEmpty) return [];
    try {
      final url = Uri.parse('$_baseUrl/tv/$tvId?api_key=$apiKey');
      final res = await http.get(url).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final seasons = (data['seasons'] as List? ?? []);
        return seasons
            .map>((s) => Map<String, dynamic>.from(s as Map))
            .where((s) => ((s['season_number'] as num?)?.toInt() ?? 0) > 0)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List>> getSeasonEpisodes(
    int tvId,
    int seasonNumber,
  ) async {
    final apiKey = await AppSettingsService.getTmdbApiKey();
    if (apiKey.isEmpty) return [];
    try {
      final url = Uri.parse('$_baseUrl/tv/$tvId/season/$seasonNumber?api_key=$apiKey');
      final res = await http.get(url).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final episodes = (data['episodes'] as List? ?? []);
        return episodes
            .map>((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
    return [];
  }
}