import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tmdb_service.dart';
import '../services/stream_service.dart';
import '../services/catalog_service.dart';
import '../widgets/mobile_stream_modal.dart';
import 'search_screen.dart';
import 'my_list_screen.dart';
import 'player_screen.dart';

class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  var activeProviders = [];
  var continueWatchingList = [];

  var heroBanners = [];
  var bollywoodLatest = [];
  var hollywoodHindiDubbed = [];
  var hindiWebSeries = [];
  var englishWebSeries = [];
  var southMovies = [];

  List netflixCatalog = [];
  List primeCatalog = [];
  List hotstarCatalog = [];
  List zee5Catalog = [];
  List sonylivCatalog = [];

  // Xtream IPTV Credentials & Caches
  String? _xtreamServer;
  String? _xtreamUser;
  String? _xtreamPass;
  List<dynamic>? _cachedVodStreams;
  List<dynamic>? _cachedSeriesStreams;

  final PageController _bannerController = PageController();
  int _currentBannerIndex = 0;
  Timer? _carouselTimer;

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllDataLightningFast();
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _bannerController.dispose();
    super.dispose();
  }

  void _startCarouselTimer(int totalSlides) {
    _carouselTimer?.cancel();
    if (totalSlides <= 1) return;
    _carouselTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_bannerController.hasClients) {
        int nextPage = _currentBannerIndex + 1;
        if (nextPage >= totalSlides) nextPage = 0;
        _bannerController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _loadAllDataLightningFast() async {
    if (mounted) setState(() => isLoading = true);

    await _fetchProvidersAndHomeContent();
    await _loadContinueWatching();

    if (mounted) {
      setState(() => isLoading = false);
    }

    _fetchCatalogsInBackground();
    _preloadXtreamVodInBackground();
  }

  Future<void> _loadContinueWatching() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString('continue_watching_mobile');
      if (raw != null && raw.isNotEmpty && mounted) {
        setState(() {
          continueWatchingList = jsonDecode(raw);
        });
      }
    } catch (_) {}
  }

  // Gist JSON se Xtream server, username aur password extract karna
  void _parseXtreamCredentials(dynamic data) {
    if (data is! Map) return;

    if (data['xtream'] != null && data['xtream'] is Map) {
      _xtreamServer = data['xtream']['server'] ?? data['xtream']['url'];
      _xtreamUser = data['xtream']['username'] ?? data['xtream']['user'];
      _xtreamPass = data['xtream']['password'] ?? data['xtream']['pass'];
    } else if (data['iptv'] != null && data['iptv'] is Map) {
      _xtreamServer = data['iptv']['server'] ?? data['iptv']['url'];
      _xtreamUser = data['iptv']['username'] ?? data['iptv']['user'];
      _xtreamPass = data['iptv']['password'] ?? data['iptv']['pass'];
    } else {
      _xtreamServer = data['server'] ?? data['url'] ?? data['xtream_server'] ?? data['iptv_server'];
      _xtreamUser = data['username'] ?? data['user'] ?? data['xtream_user'];
      _xtreamPass = data['password'] ?? data['pass'] ?? data['xtream_pass'];
    }

    if (_xtreamServer != null) {
      _xtreamServer = _xtreamServer!.trim().replaceAll(RegExp(r'/+$'), '');
    }
  }

  // Background me Xtream VOD list fetch karna taaki click karte hi instant chale
  void _preloadXtreamVodInBackground() async {
    if (_xtreamServer == null || _xtreamUser == null || _xtreamPass == null) return;
    try {
      final url = Uri.parse('$_xtreamServer/player_api.php?username=$_xtreamUser&password=$_xtreamPass&action=get_vod_streams');
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        _cachedVodStreams = jsonDecode(res.body);
      }
    } catch (_) {}
  }

  Future<void> _fetchProvidersAndHomeContent() async {
    try {
      final res = await http.get(Uri.parse(AppConfig.gistUrl)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        activeProviders = data['active_providers'] ?? [];
        _parseXtreamCredentials(data);
      }
    } catch (_) {}

    if (activeProviders.isEmpty) {
      activeProviders = [{'name': 'Render Cloud', 'url': 'https://vidsrc.me'}];
    }

    try {
      final res = await http.get(Uri.parse('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=hi&sort_by=popularity.desc')).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        bollywoodLatest = CatalogService.parseResults(jsonDecode(res.body)['results']);
        if (bollywoodLatest.isNotEmpty) {
          heroBanners = bollywoodLatest.take(6).toList();
          _startCarouselTimer(heroBanners.length);
        }
      }
    } catch (_) {}

    try {
      final res = await http.get(Uri.parse('${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_original_language=hi&sort_by=popularity.desc')).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        hindiWebSeries = CatalogService.parseResults(jsonDecode(res.body)['results'], isTv: true);
      }
    } catch (_) {}

    try {
      final res = await http.get(Uri.parse('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=en&sort_by=popularity.desc')).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        hollywoodHindiDubbed = CatalogService.parseResults(jsonDecode(res.body)['results']);
      }
    } catch (_) {}

    try {
      final res = await http.get(Uri.parse('${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_original_language=en&sort_by=popularity.desc')).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        englishWebSeries = CatalogService.parseResults(jsonDecode(res.body)['results'], isTv: true);
      }
    } catch (_) {}

    try {
      final res = await http.get(Uri.parse('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=te&sort_by=popularity.desc')).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        southMovies = CatalogService.parseResults(jsonDecode(res.body)['results']);
      }
    } catch (_) {}

    if (bollywoodLatest.isEmpty) bollywoodListFallback();
  }

  void bollywoodListFallback() {
    bollywoodLatest = [
      {'tmdb_id': 1, 'title': 'Popular Movie 1', 'poster': 'https://via.placeholder.com/300', 'backdrop': 'https://via.placeholder.com/600', 'year': '2026', 'rating': '8.5'}
    ];
    heroBanners = bollywoodLatest;
  }

  void _fetchCatalogsInBackground() async {
    final catalogs = await CatalogService.fetchMassiveCatalogs();
    if (mounted) {
      setState(() {
        netflixCatalog = (catalogs['netflix'] as List?)?.isNotEmpty == true ? catalogs['netflix']! : bollywoodLatest;
        primeCatalog = (catalogs['prime'] as List?)?.isNotEmpty == true ? catalogs['prime']! : hollywoodHindiDubbed;
        hotstarCatalog = (catalogs['hotstar'] as List?)?.isNotEmpty == true ? catalogs['hotstar']! : hindiWebSeries;
        zee5Catalog = (catalogs['zee5'] as List?)?.isNotEmpty == true ? catalogs['zee5']! : bollywoodLatest;
        sonylivCatalog = bollywoodLatest;
      });
    }
  }

  // Title matching cleaner (tags aur brackets remove karta hai)
  String _cleanTitle(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'\[.*?\]|\(.*?\)|fhd|1080p|720p|4k|hindi|dubbed|telugu|tamil|eng'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .trim();
  }

  bool _isTitleMatch(String vodName, String cleanQuery) {
    final cleanVod = _cleanTitle(vodName);
    if (cleanVod.isEmpty || cleanQuery.isEmpty) return false;
    return cleanVod.contains(cleanQuery) || cleanQuery.contains(cleanVod);
  }

  // TMDB Title se Xtream Movie Playable Stream URL nikalna
  Future<String?> _getXtreamMovieUrl({required String title, String? tmdbId}) async {
    if (_xtreamServer == null || _xtreamUser == null || _xtreamPass == null) {
      try {
        final res = await http.get(Uri.parse(AppConfig.gistUrl)).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          _parseXtreamCredentials(jsonDecode(res.body));
        }
      } catch (_) {}
    }

    if (_xtreamServer == null || _xtreamUser == null || _xtreamPass == null) {
      return null;
    }

    if (_cachedVodStreams == null) {
      try {
        final url = Uri.parse('$_xtreamServer/player_api.php?username=$_xtreamUser&password=$_xtreamPass&action=get_vod_streams');
        final res = await http.get(url).timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          _cachedVodStreams = jsonDecode(res.body);
        }
      } catch (_) {
        return null;
      }
    }

    if (_cachedVodStreams == null) return null;

    // 1. Pehle TMDB ID se match try karein
    if (tmdbId != null && tmdbId.isNotEmpty) {
      for (var vod in _cachedVodStreams!) {
        if (vod['tmdb_id']?.toString() == tmdbId) {
          final streamId = vod['stream_id'];
          final ext = vod['container_extension'] ?? 'mp4';
          return '$_xtreamServer/movie/$_xtreamUser/$_xtreamPass/$streamId.$ext';
        }
      }
    }

    // 2. Agar TMDB ID na mile to Title se match karein
    final cleanQuery = _cleanTitle(title);
    for (var vod in _cachedVodStreams!) {
      final vodName = vod['name']?.toString() ?? '';
      if (_isTitleMatch(vodName, cleanQuery)) {
        final streamId = vod['stream_id'];
        final ext = vod['container_extension'] ?? 'mp4';
        return '$_xtreamServer/movie/$_xtreamUser/$_xtreamPass/$streamId.$ext';
      }
    }

    return null;
  }

  // Movie click hone par Xtream se direct link play karna
  Future<void> _playMovieWithXtream(dynamic item) async {
    final title = item['title'] ?? item['name'] ?? 'Movie';
    final tmdbId = item['tmdb_id']?.toString() ?? item['id']?.toString();

    // Loader Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          color: Color(0xFF16181F),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF0072D2)),
                SizedBox(height: 16),
                Text(
                  'Connecting to Xtream Server...',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final streamUrl = await _getXtreamMovieUrl(title: title, tmdbId: tmdbId);

    if (mounted) Navigator.pop(context); // Close loader

    if (streamUrl != null) {
      _saveContinueWatching(item);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(
              videoUrl: streamUrl,
              title: title,
            ),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$title" Xtream server par nahi mili!'),
            backgroundColor: Colors.redAccent,
            action: SnackBarAction(
              label: 'Other Providers',
              textColor: Colors.white,
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: const Color(0xFF16181F),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (ctx) {
                    return MobileQualitySelectorSheet(
                      item: Map<String, dynamic>.from(item),
                      providers: activeProviders,
                      onPlaySaved: () => _loadContinueWatching(),
                    );
                  },
                );
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _saveContinueWatching(dynamic item) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List list = List.from(continueWatchingList);
      list.removeWhere((e) => e['tmdb_id'].toString() == item['tmdb_id'].toString());
      list.insert(0, item);
      if (list.length > 20) list = list.take(20).toList();
      await prefs.setString('continue_watching_mobile', jsonEncode(list));
      _loadContinueWatching();
    } catch (_) {}
  }

  void _onItemTapped(dynamic item) {
    bool isTv = item['isTv'] == true;

    if (isTv) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF16181F),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return _MobileSeasonEpisodeSelectorSheet(
            item: Map<String, dynamic>.from(item),
            activeProviders: activeProviders,
            xtreamServer: _xtreamServer,
            xtreamUser: _xtreamUser,
            xtreamPass: _xtreamPass,
            onPlayEpisode: (videoUrl, episodeTitle) {
              _saveContinueWatching(item);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VideoPlayerScreen(
                    videoUrl: videoUrl,
                    title: episodeTitle,
                  ),
                ),
              );
            },
          );
        },
      );
    } else {
      // Movies direct Xtream se fetch hokar play hongi
      _playMovieWithXtream(item);
    }
  }

  Future<void> _addToMyList(dynamic item) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('my_list_mobile') ?? '[]';
      List list = jsonDecode(raw);

      bool exists = list.any((element) => element['tmdb_id'].toString() == item['tmdb_id'].toString());
      if (!exists) {
        list.add(item);
        await prefs.setString('my_list_mobile', jsonEncode(list));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${item['title']} added to My List'),
              duration: const Duration(seconds: 2),
              backgroundColor: const Color(0xFF0072D2),
            ),
          );
        }
      }
    } catch (_) {}
  }

  void _openProviderCatalog(String providerName) {
    List targetList = bollywoodLatest;
    if (providerName == 'Netflix') {
      targetList = netflixCatalog.isNotEmpty ? netflixCatalog : bollywoodLatest;
    } else if (providerName == 'Prime Video') {
      targetList = primeCatalog.isNotEmpty ? primeCatalog : hollywoodHindiDubbed;
    } else if (providerName == 'JioHotstar') {
      targetList = hotstarCatalog.isNotEmpty ? hotstarCatalog : hindiWebSeries;
    } else if (providerName == 'ZEE5') {
      targetList = zee5Catalog.isNotEmpty ? zee5Catalog : bollywoodLatest;
    } else if (providerName == 'SonyLIV') {
      targetList = sonylivCatalog.isNotEmpty ? sonylivCatalog : bollywoodLatest;
    }

    if (targetList.isEmpty) {
      targetList = bollywoodLatest;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MobileCategoryGridScreen(
          title: '$providerName Catalog (${targetList.length}+ Titles)',
          rawItems: targetList,
          onItemTapped: _onItemTapped,
          onItemLongPressed: _addToMyList,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1014),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: AppBar(
          backgroundColor: const Color(0xFF0F1014),
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text(
            'Primeflix',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 22,
              color: Colors.white,
              letterSpacing: 0.8,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.search_rounded, color: Colors.white, size: 26),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchScreen()),
                );
              },
            ),
          ],
        ),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0072D2)),
            )
          : RefreshIndicator(
              color: const Color(0xFF0072D2),
              backgroundColor: const Color(0xFF16181F),
              onRefresh: _loadAllDataLightningFast,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopFeaturedCarousel(),
                    const SizedBox(height: 16),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Streaming',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildStreamingProvidersRow(),
                    const SizedBox(height: 16),
                    _buildHorizontalMovieList('Latest Bollywood Releases', bollywoodLatest),
                    const SizedBox(height: 16),
                    _buildHorizontalMovieList('Latest South Indian Movies', southMovies),
                    const SizedBox(height: 16),
                    _buildHorizontalMovieList('Latest English Web Series', englishWebSeries),
                    const SizedBox(height: 16),
                    _buildHorizontalMovieList('Latest Hollywood Movies', hollywoodHindiDubbed),
                    const SizedBox(height: 16),
                    _buildHorizontalMovieList('Latest Hindi Web Series', hindiWebSeries),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF0F1014),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF0072D2),
        unselectedItemColor: Colors.white54,
        currentIndex: 0,
        onTap: (index) {
          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyListScreen()),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_filled),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bookmark_added_rounded),
            label: 'My List',
          ),
        ],
      ),
    );
  }

  Widget _buildTopFeaturedCarousel() {
    if (heroBanners.isEmpty) {
      return Container(
        height: 220,
        margin: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: const Text('No featured content', style: TextStyle(color: Colors.white54)),
      );
    }

    return SizedBox(
      height: 220,
      child: PageView.builder(
        controller: _bannerController,
        onPageChanged: (index) {
          setState(() {
            _currentBannerIndex = index;
          });
        },
        itemCount: heroBanners.length,
        itemBuilder: (context, index) {
          final item = heroBanners[index];
          return GestureDetector(
            onTap: () => _onItemTapped(item),
            onLongPress: () => _addToMyList(item),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                image: DecorationImage(
                  image: NetworkImage(item['backdrop'] ?? ''),
                  fit: BoxFit.cover,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                padding: const EdgeInsets.all(16),
                alignment: Alignment.bottomCenter,
                child: Text(
                  item['title'] ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStreamingProvidersRow() {
    final providers = [
      {'name': 'Netflix', 'color': const Color(0xFFE50914)},
      {'name': 'JioHotstar', 'color': const Color(0xFF0072D2)},
      {'name': 'Prime Video', 'color': const Color(0xFF00A8E1)},
      {'name': 'ZEE5', 'color': const Color(0xFF8C1159)},
      {'name': 'SonyLIV', 'color': const Color(0xFFFC4C02)},
    ];

    return SizedBox(
      height: 55,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: providers.length,
        itemBuilder: (ctx, i) {
          final p = providers[i];
          final providerName = p['name'] as String;
          final color = p['color'] as Color;

          return GestureDetector(
            onTap: () => _openProviderCatalog(providerName),
            child: Container(
              width: 115,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
