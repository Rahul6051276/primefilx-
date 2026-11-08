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
  var southHindiDubbed = [];
  var hindiWebSeries = [];
  var hollywoodHindiSeries = [];
  var netflixSeries = [];
  var amazonSeries = [];

  // Deep Catalogs (200+ Titles each)
  List allBollywood200 = [];
  List allSouth200 = [];
  List allHollywood200 = [];
  List allHindiSeries200 = [];
  List allEnglishSeries200 = [];

  // Live Sports Banner State
  dynamic topLiveChannel;
  bool isLiveSportsLoading = true;

  // Banner Carousel Controller
  final PageController _bannerController = PageController();
  int _currentBannerIndex = 0;
  Timer? _carouselTimer;

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllData();
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
    _carouselTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
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

  Future _loadAllData() async {
    await _fetchProviders();
    await _loadContinueWatching();
    await _fetchTmdbContent();
    await _fetchTopLiveChannel();

    if (mounted) {
      setState(() => isLoading = false);
      final total = (topLiveChannel != null ? 1 : 0) + heroBanners.length;
      _startCarouselTimer(total);
    }

    _fetchDeepCatalogs();
  }

  Future _fetchTopLiveChannel() async {
    try {
      final channels = await MobileStreamService.getSportsChannels(activeProviders);
      if (channels is List && channels.isNotEmpty) {
        final hindi = channels.firstWhere(
          (c) => c['isHindi'] == true,
          orElse: () => channels.first,
        );
        if (mounted) {
          setState(() {
            topLiveChannel = hindi;
            isLiveSportsLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => isLiveSportsLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => isLiveSportsLoading = false);
    }
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
      final res = await http.get(Uri.parse(AppConfig.gistUrl)).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        activeProviders = data['active_providers'] ?? [];
      }
    } catch (_) {}
  }

  Future _fetchTmdbContent() async {
    try {
      final bollyRes = await http.get(Uri.parse(
          '${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=hi&sort_by=popularity.desc&vote_count.gte=10')).timeout(const Duration(seconds: 8));
      if (bollyRes.statusCode == 200) {
        bollywoodLatest = _parseResults(jsonDecode(bollyRes.body)['results']);
        if (bollywoodLatest.isNotEmpty) heroBanners = bollywoodLatest.take(6).toList();
      }

      final hindiTvRes = await http.get(Uri.parse(
          '${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_original_language=hi&without_genres=10766&sort_by=vote_count.desc&vote_count.gte=10')).timeout(const Duration(seconds: 8));
      if (hindiTvRes.statusCode == 200) {
        final rawList = jsonDecode(hindiTvRes.body)['results'] ?? [];
        hindiWebSeries = _parseResults(rawList, isTv: true)
            .where((item) => !isDailySoapTitle(item['title'] ?? ''))
            .toList();
      }

      final hollyRes = await http.get(Uri.parse(
          '${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=en&sort_by=popularity.desc&vote_count.gte=100')).timeout(const Duration(seconds: 8));
      if (hollyRes.statusCode == 200) {
        hollywoodHindiDubbed = _parseResults(jsonDecode(hollyRes.body)['results']);
      }

      final southRes = await http.get(Uri.parse(
          '${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=te%7Cta%7Cml%7Ckn&sort_by=popularity.desc&vote_count.gte=20')).timeout(const Duration(seconds: 8));
      if (southRes.statusCode == 200) {
        southHindiDubbed = _parseResults(jsonDecode(southRes.body)['results']);
      }

      final netflixRes = await http.get(Uri.parse(
          '${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_networks=213&sort_by=popularity.desc&vote_count.gte=20')).timeout(const Duration(seconds: 8));
      if (netflixRes.statusCode == 200) {
        netflixSeries = _parseResults(jsonDecode(netflixRes.body)['results'], isTv: true);
      }

      final amazonRes = await http.get(Uri.parse(
          '${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_networks=1024&sort_by=popularity.desc&vote_count.gte=20')).timeout(const Duration(seconds: 8));
      if (amazonRes.statusCode == 200) {
        amazonSeries = _parseResults(jsonDecode(amazonRes.body)['results'], isTv: true);
      }
    } catch (_) {}
  }

  Future<List> _fetchMultiPages(String urlTemplate, {bool isTv = false}) async {
    List collected = [];
    for (int p = 1; p <= 5; p++) {
      try {
        final res = await http.get(Uri.parse('$urlTemplate&page=$p')).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final results = jsonDecode(res.body)['results'];
          if (results is List && results.isNotEmpty) {
            collected.addAll(_parseResults(results, isTv: isTv));
          } else {
            break;
          }
        }
      } catch (_) {}
    }
    return collected;
  }

  void _fetchDeepCatalogs() async {
    _fetchMultiPages('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=hi&sort_by=popularity.desc&vote_count.gte=10')
        .then((list) {
      if (list.isNotEmpty && mounted) setState(() => allBollywood200 = list);
    });

    _fetchMultiPages('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=te%7Cta%7Cml%7Ckn&sort_by=popularity.desc&vote_count.gte=15')
        .then((list) {
      if (list.isNotEmpty && mounted) setState(() => allSouth200 = list);
    });

    _fetchMultiPages('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=en&sort_by=popularity.desc&vote_count.gte=50')
        .then((list) {
      if (list.isNotEmpty && mounted) setState(() => allHollywood200 = list);
    });

    _fetchMultiPages('${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_original_language=hi&without_genres=10766&sort_by=vote_count.desc&vote_count.gte=8', isTv: true)
        .then((list) {
      if (list.isNotEmpty && mounted) {
        setState(() => allHindiSeries200 = list.where((i) => !isDailySoapTitle(i['title'] ?? '')).toList());
      }
    });

    _fetchMultiPages('${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_original_language=en&sort_by=vote_count.desc&vote_count.gte=30', isTv: true)
        .then((list) {
      if (list.isNotEmpty && mounted) setState(() => allEnglishSeries200 = list);
    });
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

  void _playLiveChannel(dynamic channel) async {
    final playUrl = await MobileStreamService.getLiveChannelUrl(channel);
    if (playUrl != null && playUrl.toString().isNotEmpty && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InternalPlayerScreen(
            videoUrl: playUrl.toString(),
            title: channel['name'] ?? 'Live Sports Broadcast',
          ),
        ),
      );
    }
  }

  // Provider Click Catalog Handler
  void _openProviderCatalog(String providerName) {
    List targetList = [];

    if (providerName == 'Netflix') {
      targetList = netflixSeries.isNotEmpty ? netflixSeries : allEnglishSeries200;
    } else if (providerName == 'Prime Video') {
      targetList = amazonSeries.isNotEmpty ? amazonSeries : allHollywood200;
    } else if (providerName == 'JioHotstar') {
      targetList = hindiWebSeries.isNotEmpty ? hindiWebSeries : allHindiSeries200;
    } else {
      targetList = allBollywood200;
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
                  // Colorful Gradient Streaming Providers Row
                  _buildStreamingProvidersRow(),
                  const SizedBox(height: 12),
                  // Bollywood Latest Section
                  _buildHorizontalMovieList('Bollywood Latest Movies', bollywoodLatest),
                  const SizedBox(height: 16),
                  // Hollywood Dubbed Section
                  _buildHorizontalMovieList('Hollywood Movies (Hindi Dubbed)', hollywoodHindiDubbed),
                  const SizedBox(height: 16),
                  // Hindi Web Series Section
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

  Widget _buildStreamingProvidersRow() {
    final providers = [
      {
        'name': 'Netflix',
        'colors': [const Color(0xFFE50914), const Color(0xFF83050C)],
      },
      {
        'name': 'JioHotstar',
        'colors': [const Color(0xFF0072D2), const Color(0xFF0A2540)],
      },
      {
        'name': 'Prime Video',
        'colors': [const Color(0xFF00A8E1), const Color(0xFF003F63)],
      },
      {
        'name': 'ZEE5',
        'colors': [const Color(0xFF8C1159), const Color(0xFF450529)],
      },
      {
        'name': 'SonyLIV',
        'colors': [const Color(0xFFFC4C02), const Color(0xFF802201)],
      },
    ];

    return Container(
      height: 65,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: providers.length,
        itemBuilder: (ctx, i) {
          final p = providers[i];
          final colors = p['colors'] as List<Color>;
          final providerName = p['name'] as String;

          return GestureDetector(
            onTap: () => _openProviderCatalog(providerName),
            child: Container(
              width: 120,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: colors[0].withOpacity(0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                providerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 0.5,
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
