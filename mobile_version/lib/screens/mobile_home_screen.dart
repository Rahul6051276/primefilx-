import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tmdb_service.dart';
import '../services/stream_service.dart';
import '../widgets/mobile_stream_modal.dart';
import '../internal_player.dart';
import 'search_screen.dart';
import 'my_list_screen.dart';

class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  var activeProviders = [];
  var continueWatchingList = [];

  var heroBanners = [];
  var bollywoodLatest = [];
  var hollywoodHindiDubbed = [];
  var hindiWebSeries = [];

  // Deep Catalogs (Lazy loaded in background)
  List allBollywood200 = [];
  List allHollywood200 = [];
  List allHindiSeries200 = [];
  List allEnglishSeries200 = [];

  String _selectedTab = 'Recommend';

  // Banner Carousel Controller
  final PageController _bannerController = PageController();
  int _currentBannerIndex = 0;
  Timer? _carouselTimer;

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFastInitialData();
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

  // --- FAST INITIAL LOAD (Instant UI Rendering) ---
  Future _loadFastInitialData() async {
    // 1. Load local cache / providers / main banner data concurrently for ultra-fast startup
    await Future.wait([
      _fetchProviders(),
      _loadContinueWatching(),
      _fetchMainHomeContent(),
    ]);

    if (mounted) {
      setState(() => isLoading = false);
      final total = heroBanners.isNotEmpty ? heroBanners.length : 1;
      _startCarouselTimer(total);
    }

    // 2. Load heavy deep catalogs silently in background so UI is never blocked
    _fetchDeepCatalogsInBackground();
  }

  Future _loadContinueWatching() async {
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

  Future _fetchProviders() async {
    try {
      final res = await http.get(Uri.parse(MobileStreamService.gistUrl)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        activeProviders = data['active_providers'] ?? [];
      }
    } catch (_) {}
  }

  // Fetch only essential above-the-fold content first for instant loading
  Future _fetchMainHomeContent() async {
    try {
      final responses = await Future.wait([
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=hi&sort_by=popularity.desc&vote_count.gte=10')).timeout(const Duration(seconds: 5)),
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_original_language=hi&without_genres=10766&sort_by=vote_count.desc&vote_count.gte=10')).timeout(const Duration(seconds: 5)),
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=en&sort_by=popularity.desc&vote_count.gte=100')).timeout(const Duration(seconds: 5)),
      ]);

      // Parse Bollywood Latest & Banners
      if (responses[0].statusCode == 200) {
        bollywoodLatest = _parseResults(jsonDecode(responses[0].body)['results']);
        if (bollywoodLatest.isNotEmpty) {
          heroBanners = bollywoodLatest.take(6).toList();
        }
      }

      // Parse Hindi Web Series
      if (responses[1].statusCode == 200) {
        final rawList = jsonDecode(responses[1].body)['results'] ?? [];
        hindiWebSeries = _parseResults(rawList, isTv: true)
            .where((item) => !isDailySoapTitle(item['title'] ?? ''))
            .toList();
      }

      // Parse Hollywood Dubbed
      if (responses[2].statusCode == 200) {
        hollywoodHindiDubbed = _parseResults(jsonDecode(responses[2].body)['results']);
      }
    } catch (_) {}
  }

  void _fetchDeepCatalogsInBackground() async {
    try {
      final bollyRes = await http.get(Uri.parse('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=hi&sort_by=popularity.desc&vote_count.gte=10&page=1')).timeout(const Duration(seconds: 5));
      if (bollyRes.statusCode == 200 && mounted) {
        setState(() => allBollywood200 = _parseResults(jsonDecode(bollyRes.body)['results']));
      }

      final hollyRes = await http.get(Uri.parse('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=en&sort_by=popularity.desc&vote_count.gte=50&page=1')).timeout(const Duration(seconds: 5));
      if (hollyRes.statusCode == 200 && mounted) {
        setState(() => allHollywood200 = _parseResults(jsonDecode(hollyRes.body)['results']));
      }
    } catch (_) {}
  }

  dynamic _parseResults(dynamic list, {bool isTv = false}) {
    var res = [];
    final currentYear = DateTime.now().year.toString();
    for (var m in (list ?? [])) {
      if (m['poster_path'] == null && m['backdrop_path'] == null) continue;
      res.add({
        'tmdb_id': m['id'],
        'title': m['title'] ?? m['name'] ?? 'Untitled',
        'year': (m['release_date'] ?? m['first_air_date'] ?? currentYear)
            .toString()
            .split('-')[0],
        'rating': m['vote_average']?.toString() ?? '7.8',
        'backdrop': m['backdrop_path'] != null
            ? AppConfig.backdropBase + m['backdrop_path'].toString()
            : AppConfig.imgBase + m['poster_path'].toString(),
        'poster': m['poster_path'] != null
            ? AppConfig.imgBase + m['poster_path'].toString()
            : AppConfig.backdropBase + m['backdrop_path'].toString(),
        'isTv': isTv,
      });
    }
    return res;
  }

  void _onItemTapped(dynamic item) {
    _showQualitySheet(item);
  }

  void _showQualitySheet(dynamic item, {int? season, int? episode}) {
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
          season: season,
          episode: episode,
          providers: activeProviders,
          onPlaySaved: () => _loadContinueWatching(),
        );
      },
    );
  }

  void _openProviderCatalog(String providerName) {
    List targetList = allBollywood200.isNotEmpty ? allBollywood200 : bollywoodLatest;
    if (providerName == 'Netflix') {
      targetList = allEnglishSeries200.isNotEmpty ? allEnglishSeries200 : bollywoodLatest;
    } else if (providerName == 'Prime Video') {
      targetList = allHollywood200.isNotEmpty ? allHollywood200 : bollywoodLatest;
    } else if (providerName == 'JioHotstar') {
      targetList = allHindiSeries200.isNotEmpty ? allHindiSeries200 : hindiWebSeries;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MobileCategoryGridScreen(
          title: '$providerName Catalog',
          rawItems: targetList,
          onItemTapped: _onItemTapped,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
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
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0072D2)))
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Top Category Tabs ('Recommend', 'Movies', 'TV Shows', '18+')[span_0](start_span)[span_0](end_span)
                  _buildCategoryTabs(),
                  const SizedBox(height: 6),
                  
                  // 2. Sliding Featured Banner Carousel[span_1](start_span)[span_1](end_span)
                  _buildTopFeaturedCarousel(),
                  const SizedBox(height: 16),

                  // 3. Streaming Section Title & Providers Row[span_2](start_span)[span_2](end_span)
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

                  // 4. Content Rows (Trending Now / Bollywood Latest, etc.)[span_3](start_span)[span_3](end_span)
                  _buildHorizontalMovieList('Trending Now', bollywoodLatest),
                  const SizedBox(height: 16),
                  _buildHorizontalMovieList('Hollywood Movies (Hindi Dubbed)', hollywoodHindiDubbed),
                  const SizedBox(height: 16),
                  _buildHorizontalMovieList('Hindi Web Series', hindiWebSeries),
                  const SizedBox(height: 24),
                ],
              ),
            ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF0F1014),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF0072D2),
        unselectedItemColor: Colors.white54,
        currentIndex: 0,
        onTap: (index) {
          if (index == 3) {
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
            icon: Icon(Icons.sort_rounded),
            label: 'Sort',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_fire_department_rounded),
            label: 'Ranking',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bookmark_added_rounded),
            label: 'My List',
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs() {
    final tabs = ['Recommend', 'Movies', 'TV Shows', '18+'];
    return Container(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: tabs.length,
        itemBuilder: (ctx, i) {
          final tab = tabs[i];
          final isSelected = _selectedTab == tab;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedTab = tab;
              });
            },
            child: Container(
              alignment: Alignment.center,
              margin: const EdgeInsets.only(right: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tab,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white54,
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (isSelected)
                    Container(
                      height: 2,
                      width: 22,
                      color: const Color(0xFF0072D2),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopFeaturedCarousel() {
    if (heroBanners.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 210,
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
                    colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
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
                    fontSize: 18,
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
    ];

    return Container(
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
              width: 125,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                providerName.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHorizontalMovieList(String title, List items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            itemBuilder: (ctx, index) {
              final item = items[index];
              return GestureDetector(
                onTap: () => _onItemTapped(item),
                child: Container(
                  width: 110,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            item['poster'] ?? '',
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey[850],
                              child: const Icon(Icons.broken_image, color: Colors.white24),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item['title'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MobileCategoryGridScreen extends StatelessWidget {
  final String title;
  final List rawItems;
  final Function(dynamic) onItemTapped;

  const _MobileCategoryGridScreen({
    required this.title,
    required this.rawItems,
    required this.onItemTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1014),
      appBar: AppBar(
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18)),
        backgroundColor: const Color(0xFF16181F),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: rawItems.isEmpty
          ? const Center(
              child: Text(
                'No items found in this catalog.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.65,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: rawItems.length,
              itemBuilder: (ctx, index) {
                final item = rawItems[index];
                return GestureDetector(
                  onTap: () => onItemTapped(item),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                            child: Image.network(
                              item['poster'] ?? '',
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.grey[850],
                                child: const Icon(Icons.broken_image, color: Colors.white24),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(6.0),
                          child: Text(
                            item['title'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
