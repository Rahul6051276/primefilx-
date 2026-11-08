import 'dart:convert';
import 'package:http/http.dart' as http;

class TmdbService {
  static const String apiKey = 'YOUR_TMDB_API_KEY'; // Apni key yahan check kar lena
  static const String baseUrl = 'https://api.themoviedb.org/3';

  static Future<List<dynamic>> fetchTrending() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/trending/all/day?api_key=$apiKey'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['results'] ?? [];
      }
    } catch (e) {
      print('TMDB Trending Error: $e');
    }
    return [];
  }

  static Future<List<dynamic>> searchMovies(String query) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/search/multi?api_key=$apiKey&query=$query'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['results'] ?? [];
      }
    } catch (e) {
      print('TMDB Search Error: $e');
    }
    return [];
  }

  static Future?> fetchMovieDetails(int tmdbId, String mediaType) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/$mediaType/$tmdbId?api_key=$apiKey'),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('TMDB Details Error: $e');
    }
    return null;
  }
}
