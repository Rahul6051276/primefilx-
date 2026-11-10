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
import '../internal_player.dart'; // Asli Internal Player (Landscape + Lock + Crop)

const String kGistPermanentRawUrl = "https://gist.githubusercontent.com/Rahul6051276/5b0a18b2cf69a99d1d3e06629fcbc70a/raw";

class XtreamAccount {
  final String name;
  final String host;
  final String username;
  final String password;
  List<dynamic>? cachedVod;
  List<dynamic>? cachedSeries;

  XtreamAccount({
    required this.name,
    required this.host,
    required this.username,
    required this.password,
  });
}

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

  final List<XtreamAccount> _xtreamAccounts = [];

  final PageController _bannerController = PageController();
  int _currentBannerIndex = 0;
  Timer? _carouselTimer;

  bool isLoading = true;

  final Map<String, String> _iptvHeaders = {
    'User-Agent': 'IPTVSmartersPro/1.0.0 (Linux; Android 12)',
    'Accept': '*/*',
  };

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

  void _parseXtreamCredentials(dynamic data) {
    _xtreamAccounts.clear();
    if (data is! Map) return;

    final providers = data['active_providers'];
    if (providers is List) {
      for (var p in providers) {
        if (p is Map && (p['type'] == 'xtream' || p['xc_host'] != null)) {
          final host = (p['xc_host'] ?? p['server'] ?? p['url'])?.toString().replaceAll(RegExp(r'/+$'), '');
          final user = (p['xc_username'] ?? p['username'])?.toString();
          final pass = (p['xc_password'] ?? p['password'])?.toString();
          final name = (p['name'] ?? 'Xtream Server').toString();

          if (host != null && user != null && pass != null && host.isNotEmpty) {
            _xtreamAccounts.add(XtreamAccount(
              name: name,
              host: host,
              username: user,
              password: pass,
            ));
          }
        }
      }
    }
  }

  Future<void> _fetchProvidersAndHomeContent() async {
    try {
      final freshGistUrl = "$kGistPermanentRawUrl?t=${DateTime.now().millisecondsSinceEpoch}";
      final res = await http.get(Uri.parse(freshGistUrl)).timeout(const Duration(seconds: 8));

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
            xtreamAccounts: _xtreamAccounts,
            iptvHeaders: _iptvHeaders,
            onPlayEpisode: (videoUrl, episodeTitle) {
              _saveContinueWatching(item);
              // Asli Internal Player me play hoga
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InternalPlayerScreen(
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

  void _openProviderCatalog(String providerName, Color providerColor) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MobileCategoryGridScreen(
          providerName: providerName,
          providerColor: providerColor,
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
            onTap: () => _openProviderCatalog(providerName, color),
            child: Container(
              width: 115,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
