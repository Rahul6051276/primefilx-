import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/tmdb_config.dart';

class TmdbService {
  static Future<List<dynamic>> fetchTrending() async {
    try {
      final url = Uri.parse('${MobileConfig.tmdbBase}/trending/all/day?api_key=${MobileConfig.tmdbKey}');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['results'] ?? [];
      }
    } catch (_) {}
    return [];
  }

  static Future<List<dynamic>> searchMovies(String query) async {
    try {
      final url = Uri.parse('${MobileConfig.tmdbBase}/search/multi?api_key=${MobileConfig.tmdbKey}&query=${Uri.encodeComponent(query)}');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['results'] ?? [];
      }
    } catch (_) {}
    return [];
  }

  static Future?> fetchMovieDetails(int tmdbId, String mediaType) async {
    try {
      final url = Uri.parse('${MobileConfig.tmdbBase}/$mediaType/$tmdbId?api_key=${MobileConfig.tmdbKey}&append_to_response=credits,external_ids');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (_) {}
    return null;
  }
}
