import 'dart:convert';
import 'package:http/http.dart' as http;
import 'tmdb_service.dart';

class CatalogService {
  static bool isDailySoapTitle(String title) {
    final t = title.toLowerCase();
    const blockList = [
      'c.i.d.', 'cid', 'bhabiji', 'balika vadhu', 'kapil sharma', 'roadies',
      'pavitra rishta', 'kumkum bhagya', 'jhanak', 'kundali bhagya',
      'ye rishta', 'yrkkh', 'taarak mehta', 'tmkoc', 'kasautii', 'ishqbaaaz',
      'anupamaa', 'bigg boss', 'khatron ke khiladi', 'splitsvilla',
      'crime patrol', 'savdhaan india', 'diya aur baati', 'qubool hai',
      'jamai raja', 'tujhse hai raabta', 'radhakrishn', 'koffee with karan',
      'india\'s got', 'mangal lakshmi', 'pushpa impossible', 'may i come in',
      'parineetii', 'imlie', 'teri meri dooriyaan', 'udaariyaan', 'ghkkpm'
    ];
    return blockList.any((b) => t.contains(b));
  }

  static List parseResults(dynamic list, {bool isTv = false}) {
    var res = [];
    final currentYear = DateTime.now().year.toString();
    for (var m in (list ?? [])) {
      if (m['poster_path'] == null && m['backdrop_path'] == null) continue;
      final title = m['title'] ?? m['name'] ?? 'Untitled';
      
      if (isDailySoapTitle(title)) continue;

      res.add({
        'tmdb_id': m['id'],
        'title': title,
        'year': (m['release_date'] ?? m['first_air_date'] ?? currentYear).toString().split('-')[0],
        'rating': m['vote_average']?.toString() ?? '8.0',
        'backdrop': m['backdrop_path'] != null ? AppConfig.backdropBase + m['backdrop_path'] : AppConfig.imgBase + m['poster_path'],
        'poster': m['poster_path'] != null ? AppConfig.imgBase + m['poster_path'] : AppConfig.backdropBase + m['poster_path'],
        'isTv': isTv,
      });
    }
    return res;
  }

  // Multi-page pagination to fetch 40+ titles per catalog
  static Future fetchMassiveCatalogs() async {
    try {
      final responses = await Future.wait([
        // Netflix (Provider 8) - Pages 1 & 2
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_watch_providers=8&watch_region=IN&sort_by=popularity.desc&page=1')),
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_watch_providers=8&watch_region=IN&sort_by=popularity.desc&page=2')),
        
        // Prime Video (Provider 9) - Pages 1 & 2
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_watch_providers=9&watch_region=IN&sort_by=popularity.desc&page=1')),
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_watch_providers=9&watch_region=IN&sort_by=popularity.desc&page=2')),
        
        // JioHotstar / Disney+ (Provider 337/122) - Pages 1 & 2
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_watch_providers=337&watch_region=IN&sort_by=popularity.desc&page=1')),
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_watch_providers=337&watch_region=IN&sort_by=popularity.desc&page=2')),
        
        // ZEE5 (Provider 232) - Pages 1 & 2
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_watch_providers=232&watch_region=IN&sort_by=popularity.desc&page=1')),
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_watch_providers=232&watch_region=IN&sort_by=popularity.desc&page=2')),
      ]);

      var netflixList = [
        ...(responses[0].statusCode == 200 ? parseResults(jsonDecode(responses[0].body)['results'], isTv: true) : []),
        ...(responses[1].statusCode == 200 ? parseResults(jsonDecode(responses[1].body)['results'], isTv: true) : []),
      ];

      var primeList = [
        ...(responses[2].statusCode == 200 ? parseResults(jsonDecode(responses[2].body)['results'], isTv: true) : []),
        ...(responses[3].statusCode == 200 ? parseResults(jsonDecode(responses[3].body)['results'], isTv: true) : []),
      ];

      var hotstarList = [
        ...(responses[4].statusCode == 200 ? parseResults(jsonDecode(responses[4].body)['results'], isTv: true) : []),
        ...(responses[5].statusCode == 200 ? parseResults(jsonDecode(responses[5].body)['results'], isTv: true) : []),
      ];

      var zee5List = [
        ...(responses[6].statusCode == 200 ? parseResults(jsonDecode(responses[6].body)['results'], isTv: false) : []),
        ...(responses[7].statusCode == 200 ? parseResults(jsonDecode(responses[7].body)['results'], isTv: false) : []),
      ];

      return {
        'netflix': netflixList,
        'prime': primeList,
        'hotstar': hotstarList,
        'zee5': zee5List,
      };
    } catch (_) {
      return {};
    }
  }
}
