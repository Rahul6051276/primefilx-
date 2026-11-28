import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsService {
  static const String _gistUrlKey = 'primeflix_gist_raw_url';
  static const String _tmdbKeyPref = 'primeflix_tmdb_api_key';
  static const String _seekSecKey = 'primeflix_seek_seconds';

  // Direct Xtream IPTV Keys
  static const String _xtreamUrlKey = 'primeflix_direct_xtream_url';
  static const String _xtreamUserKey = 'primeflix_direct_xtream_user';
  static const String _xtreamPassKey = 'primeflix_direct_xtream_pass';

  // Direct Stalker Portal Keys
  static const String _stalkerUrlKey = 'primeflix_direct_stalker_url';
  static const String _stalkerMacKey = 'primeflix_direct_stalker_mac';
  static const String _stalkerDev1Key = 'primeflix_direct_stalker_dev1';
  static const String _stalkerDev2Key = 'primeflix_direct_stalker_dev2';

  static const String _envTmdbKey = String.fromEnvironment(
    'TMDB_API_KEY',
    defaultValue: '',
  );
  static const String _envGistUrl = String.fromEnvironment(
    'GIST_RAW_URL',
    defaultValue: '',
  );

  static Future getGistUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString(_gistUrlKey) ?? '').trim();
    if (saved.isNotEmpty) return saved;
    return _envGistUrl.trim();
  }

  static Future setGistUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_gistUrlKey, url.trim());
  }

  static Future getTmdbApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString(_tmdbKeyPref) ?? '').trim();
    if (saved.isNotEmpty) return saved;
    return _envTmdbKey.trim();
  }

  static Future setTmdbApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tmdbKeyPref, apiKey.trim());
  }

  static Future getSeekSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_seekSecKey) ?? 15).clamp(5, 60);
  }

  static Future setSeekSeconds(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seekSecKey, seconds.clamp(5, 60));
  }

  // Direct Xtream IPTV Getters & Setters
  static Future getDirectXtream() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'url': (prefs.getString(_xtreamUrlKey) ?? '').trim(),
      'username': (prefs.getString(_xtreamUserKey) ?? '').trim(),
      'password': (prefs.getString(_xtreamPassKey) ?? '').trim(),
    };
  }

  static Future setDirectXtream({
    required String url,
    required String username,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_xtreamUrlKey, url.trim());
    await prefs.setString(_xtreamUserKey, username.trim());
    await prefs.setString(_xtreamPassKey, password.trim());
  }

  // Direct Stalker Portal Getters & Setters
  static Future getDirectStalker() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'url': (prefs.getString(_stalkerUrlKey) ?? '').trim(),
      'mac': (prefs.getString(_stalkerMacKey) ?? '').trim(),
      'device_id1': (prefs.getString(_stalkerDev1Key) ?? '').trim(),
      'device_id2': (prefs.getString(_stalkerDev2Key) ?? '').trim(),
    };
  }

  static Future setDirectStalker({
    required String url,
    required String mac,
    required String deviceId1,
    required String deviceId2,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stalkerUrlKey, url.trim());
    await prefs.setString(_stalkerMacKey, mac.trim().toUpperCase());
    await prefs.setString(_stalkerDev1Key, deviceId1.trim());
    await prefs.setString(_stalkerDev2Key, deviceId2.trim());
  }
}