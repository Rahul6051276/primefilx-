import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsService {
  static const String _gistUrlKey = 'primeflix_gist_raw_url';
  static const String _tmdbKeyPref = 'primeflix_tmdb_api_key';
  static const String _seekSecKey = 'primeflix_seek_seconds';

  static const String _envTmdbKey = String.fromEnvironment(
    'TMDB_API_KEY',
    defaultValue: '',
  );
  static const String _envGistUrl = String.fromEnvironment(
    'GIST_RAW_URL',
    defaultValue: '',
  );

  static Future<String> getGistUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString(_gistUrlKey) ?? '').trim();
    if (saved.isNotEmpty) return saved;
    return _envGistUrl.trim();
  }

  static Future<void> setGistUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_gistUrlKey, url.trim());
  }

  static Future<String> getTmdbApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString(_tmdbKeyPref) ?? '').trim();
    if (saved.isNotEmpty) return saved;
    return _envTmdbKey.trim();
  }

  static Future<void> setTmdbApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tmdbKeyPref, apiKey.trim());
  }

  static Future<int> getSeekSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_seekSecKey) ?? 15).clamp(5, 60);
  }

  static Future<void> setSeekSeconds(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seekSecKey, seconds.clamp(5, 60));
  }
}