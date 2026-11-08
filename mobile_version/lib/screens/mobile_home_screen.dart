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

  List netflixCatalog = [];
  List primeCatalog = [];
  List hotstarCatalog = [];
  List zee5Catalog = [];
  List sonylivCatalog = [];

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

    try {
      await Future.wait([
        _fetchProvidersAndHomeContent(),
        _loadContinueWatching(),
      ]);
    } catch (_) {}

    if (mounted) {
      setState(() => isLoading = false);
    }

    _fetchCatalogsInBackground();
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

  Future<void> _fetchProvidersAndHomeContent() async {
    try {
      final responses = await Future.wait([
        http.get(Uri.parse(MobileStreamService.gistUrl)).timeout(const Duration(seconds: 4)),
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=hi&sort_by=popularity.desc')).timeout(const Duration(seconds: 5)),
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_original_language=hi&sort_by=vote_count.desc')).timeout(const Duration(seconds: 5)),
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=en&sort_by=popularity.desc')).timeout(const Duration(seconds: 5)),
      ]);

      if (responses[0].statusCode == 200) {
        final data = jsonDecode(responses[0].body);
        activeProviders = data['active_providers'] ?? [];
      }

      if (responses[1].statusCode == 200) {
        bollywoodLatest = CatalogService.parseResults(jsonDecode(responses[1].body)['results']);
        if (bollywoodLatest.isNotEmpty) {
          heroBanners = bollywoodLatest.take(6).toList();
          _startCarouselTimer(heroBanners.length);
        }
      }

      if (responses[2].statusCode == 200) {
        hindiWebSeries = CatalogService.parseResults(jsonDecode(responses[2].body)['results'], isTv: true);
      }

      if (responses[3].statusCode == 200) {
        hollywoodHindiDubbed = CatalogService.parseResults(jsonDecode(responses[3].body)['results']);
      }
    } catch (_) {
      if (activeProviders.isEmpty) {
        activeProviders = [{'name': 'Render Cloud', 'url': 'https://vidsrc.me'}];
      }
    }
  }

  void _fetchCatalogsInBackground() async {
    final catalogs = await CatalogService.fetchMassiveCatalogs();
    if (mounted) {
      setState(() {
        netflixCatalog = catalogs['netflix']?.isNotEmpty == true ? catalogs['netflix']! : bollywoodLatest;
        primeCatalog = catalogs['prime']?.isNotEmpty == true ? catalogs['prime']! : hollywoodHindiDubbed;
        hotstarCatalog = catalogs['hotstar']?.isNotEmpty == true ? catalogs['hotstar']! : hindiWebSeries;
        zee5Catalog = catalogs['zee5']?.isNotEmpty == true ? catalogs['zee5']! : bollywoodLatest;
        sonylivCatalog = bollywoodLatest;
      });
    }
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
          return MobileSeasonEpisodeSelectorSheet(
            item: Map<String, dynamic>.from(item),
            activeProviders: activeProviders,
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
        builder: (_) => MobileCategoryGridScreen(
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
                    _buildHorizontalMovieList('Trending Now', bollywoodLatest),
                    const SizedBox(height: 16),
                    _buildHorizontalMovieList('Hollywood Movies (Hindi Dubbed)', hollywoodHindiDubbed),
                    const SizedBox(height: 16),
                    _buildHorizontalMovieList('Hindi Web Series', hindiWebSeries),
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
                  fontSize: 12,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHorizontalMovieList(String title, List items) {
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
          child: items.isEmpty
              ? const Center(
                  child: SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0072D2)),
                  ),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: items.length,
                  itemBuilder: (ctx, index) {
                    final item = items[index];
                    return GestureDetector(
                      onTap: () => _onItemTapped(item),
                      onLongPress: () => _addToMyList(item),
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
