import 'dart:convert';
import 'package:http/http.dart' as http;

class MobileStreamService {
  static const String renderBaseUrl = 'https://your-render-backend-url.onrender.com';

  static Future<List>> getDirectStreams({required dynamic item}) async {
    final int id = item['id'] ?? item['tmdb_id'] ?? 0;
    final String mediaType = item['media_type'] ?? (item['title'] != null ? 'movie' : 'tv');
    
    try {
      final response = await http.get(
        Uri.parse('$renderBaseUrl/api/stream?id=$id&type=$mediaType'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<dynamic> rawStreams = data['streams'] ?? [];

        List> streams = rawStreams.map>((stream) {
          return {
            'source': stream['source'] ?? 'Render Stream',
            'quality': stream['quality'] ?? 'HD',
            'language': stream['language'] ?? 'Hindi', // Language detect karne ke liye
            'url': stream['url'] ?? '',
          };
        }).toList();

        // **Smart Sorting Logic for Hindi & 1080p/720p Priority**
        streams.sort((a, b) {
          String qA = a['quality'].toString().toUpperCase();
          String qB = b['quality'].toString().toUpperCase();
          String langA = a['language'].toString().toUpperCase();
          String langB = b['language'].toString().toUpperCase();

          // 1st Priority: Hindi Language
          bool isHindiA = langA.contains('HINDI') || langA.contains('MULTI');
          bool isHindiB = langB.contains('HINDI') || langB.contains('MULTI');
          if (isHindiA && !isHindiB) return -1;
          if (!isHindiA && isHindiB) return 1;

          // 2nd Priority: 1080p or 720p Quality
          bool isHd1080A = qA.contains('1080');
          bool isHd1080B = qB.contains('1080');
          if (isHd1080A && !isHd1080B) return -1;
          if (!isHd1080A && isHd1080B) return 1;

          bool isHd720A = qA.contains('720');
          bool isHd720B = qB.contains('720');
          if (isHd720A && !isHd720B) return -1;
          if (!isHd720A && isHd720B) return 1;

          return 0;
        });

        return streams;
      }
    } catch (e) {
      print('Render Stream Fetch Error: $e');
    }

    return [];
  }
}
