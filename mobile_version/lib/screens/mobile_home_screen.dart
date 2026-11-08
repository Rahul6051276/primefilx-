import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tmdb_service.dart';
import '../services/stream_service.dart';
import '../widgets/mobile_stream_modal.dart';
import '../widgets/home_drawer.dart';
import '../widgets/category_grid_screen.dart';
import '../internal_player.dart';
import 'my_list_screen.dart'; // My List screen import kiya hai

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

  List allBollywood200 = [];
  List allSouth200 = [];
  List allHollywood200 = [];
  List allHindiSeries200 = [];
  List allEnglishSeries200 = [];

  dynamic topLiveChannel;
  bool isLiveSportsLoading = true;

  // Primeflix Top Tabs State ('Recommend', 'Movies', 'TV Shows', '18+')
  String _selectedTab = 'Recommend';

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
      try {
        final bollyRes = await http.get(Uri.parse(
            '${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=hi&sort_by=popularity.desc&vote_count.gte=10')).timeout(const Duration(seconds: 8));
        if (bollyRes.statusCode == 200) {
          bollywoodLatest = _parseResults(jsonDecode(bollyRes.body)['results']);
          if (bollywoodLatest.isNotEmpty) heroBanners = bollywoodLatest.take(6).toList();
        }
      } catch (_) {}

      try {
        final hindiTvRes = await http.get(Uri.parse(
            '${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_original_language=hi&without_genres=10766&sort_by=vote_count.desc&vote_count.gte=10')).timeout(const Duration(seconds: 8));
        if (hindiTvRes.statusCode == 200) {
          final rawList = jsonDecode(hindiTvRes.body)['results'] ?? [];
          hindiWebSeries = _parseResults(rawList, isTv: true)
              .where((item) => !isDailySoapTitle(item['title'] ?? ''))
              .toList();
        }
      } catch (_) {}

      try {
        final hollyRes = await http.get(Uri.parse(
            '${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=en&sort_by=popularity.desc&vote_count.gte=100')).timeout(const Duration(seconds: 8));
        if (hollyRes.statusCode == 200) {
          hollywoodHindiDubbed = _parseResults(jsonDecode(hollyRes.body)['results']);
        }
      } catch (_) {}

      try {
        final southRes = await http.get(Uri.parse(
            '${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=te%7Cta%7Cml%7Ckn&sort_by=popularity.desc&vote_count.gte=20')).timeout(const Duration(seconds: 8));
        if (southRes.statusCode == 200) {
          southHindiDubbed = _parseResults(jsonDecode(southRes.body)['results']);
        }
      } catch (_) {}

      try {
        final hollySeriesRes = await http.get(Uri.parse(
            '${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_original_language=en&sort_by=popularity.desc&vote_count.gte=30')).timeout(const Duration(seconds: 8));
        if (hollySeriesRes.statusCode == 200) {
          hollywoodHindiSeries = _parseResults(jsonDecode(hollySeriesRes.body)['results'], isTv: true);
        }
      } catch (_) {}

      try {
        final netflixRes = await http.get(Uri.parse(
            '${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_networks=213&sort_by=popularity.desc&vote_count.gte=20')).timeout(const Duration(seconds: 8));
        if (netflixRes.statusCode == 200) {
          netflixSeries = _parseResults(jsonDecode(netflixRes.body)['results'], isTv: true);
        }
      } catch (_) {}

      try {
        final amazonRes = await http.get(Uri.parse(
            '${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_networks=1024&sort_by=popularity.desc&vote_count.gte=20')).timeout(const Duration(seconds: 8));
        if (amazonRes.statusCode == 200) {
          amazonSeries = _parseResults(jsonDecode(amazonRes.body)['results'], isTv: true);
        }
      } catch (_) {}
    } catch (_) {}
  }

  Future<List> _fetchMultiPages(String urlTemplate, {bool isTv = false}) async {
    List collected = [];
    for (int p = 1; p <= 10; p++) {
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
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
            url: playUrl.toString(),
            title: channel['name'] ?? 'Live Sports Broadcast',
          ),
        ),
      );
    }
  }

  void _openSportsListSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return FutureBuilder(
          future: MobileStreamService.getSportsChannels(activeProviders),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 250,
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFE50914)),
                ),
              );
            }

            final channels = (snapshot.data is List) ? (snapshot.data as List) : [];
            if (channels.isEmpty) {
              return const SizedBox(
                height: 200,
                child: Center(
                  child: Text('Live Sports Server Offline / No Channels Found',
                      style: TextStyle(color: Colors.white70)),
                ),
              );
            }

            return Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              height: MediaQuery.of(context).size.height * 0.65,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text(
                      'Live Sports & Cricket Channels',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Divider(color: Colors.white12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: channels.length,
                      separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                      itemBuilder: (context, index) {
                        final ch = channels[index];
                        final isHindi = ch['isHindi'] == true;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF222222),
                            child: Icon(
                              Icons.tv,
                              color: isHindi ? const Color(0xFF10B981) : const Color(0xFFE50914),
                            ),
                          ),
                          title: Text(ch['name'] ?? 'Sports Channel', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            isHindi ? 'Hindi Live Audio' : 'Live Stream',
                            style: TextStyle(color: isHindi ? const Color(0xFF10B981) : Colors.white38, fontSize: 12),
                          ),
                          trailing: const Icon(Icons.play_circle_fill, color: Color(0xFFE50914), size: 28),
                          onTap: () {
                            Navigator.pop(ctx);
                            _playLiveChannel(ch);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- PRIMEFLIX TOP TABS WIDGET (Recommend, Movies, TV Shows, 18+) ---
  Widget _buildCategoryTabs() {
    final tabs = ['Recommend', 'Movies', 'TV Shows', '18+'];
    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(vertical: 4),
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
              margin: const EdgeInsets.only(right: 18),
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
                      width: 24,
                      color: const Color(0xFFE50914),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --- STREAMING PROVIDERS LOGO ROW ---
  Widget _buildStreamingProvidersRow() {
    final providers = [
      {'name': 'Netflix', 'color': const Color(0xFFE50914)},
      {'name': 'JioHotstar', 'color': const Color(0xFF0072D2)},
      {'name': 'Prime Video', 'color': const Color(0xFF00A8E1)},
      {'name': 'ZEE5', 'color': const Color(0xFF8C1159)},
    ];

    return Container(
      height: 60,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: providers.length,
        itemBuilder: (ctx, i) {
          final p = providers[i];
          return Container(
            width: 110,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF16181F),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            alignment: Alignment.center,
            child: Text(
              p['name'] as String,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopFeaturedCarousel() {
    final List<Widget> slides = [];

    if (topLiveChannel != null) {
      final chName = topLiveChannel['name'] ?? 'Live Match Broadcast';
      final isHindi = topLiveChannel['isHindi'] == true;

      slides.add(
        GestureDetector(
          onTap: () => _playLiveChannel(topLiveChannel),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFF2B090C), Color(0xFF5A1217)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE50914).withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  right: -20,
                  bottom: -20,
                  child: Icon(
                    Icons.sports_cricket_rounded,
                    size: 160,
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE50914),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(radius: 3, backgroundColor: Colors.white),
                                SizedBox(width: 5),
                                Text(
                                  'LIVE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isHindi) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                              ),
                              child: const Text(
                                'Hindi Feed',
                                style: TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'WATCH LIVE MATCH',
                                  style: TextStyle(
                                    color: Color(0xFFFF4D4D),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  chName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFE50914), Color(0xFFB20710)],
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                                SizedBox(width: 4),
                                Text(
                                  'Play',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    for (var m in heroBanners) {
      slides.add(
        GestureDetector(
          onTap: () => _onItemTapped(m),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: const Color(0xFF1E2029),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    m['backdrop'],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1E2029)),
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black45,
                          Colors.black87,
                        ],
                        stops: [0.3, 0.65, 1.0],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                m['rating'] ?? '7.8',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Text(
                                m['title'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.play_arrow_rounded, color: Colors.black, size: 20),
                                  SizedBox(width: 4),
                                  Text(
                                    'Watch',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (slides.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 195,
          child: PageView(
            controller: _bannerController,
            onPageChanged: (i) => setState(() => _currentBannerIndex = i),
            children: slides,
          ),
        ),
        if (slides.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              slides.length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                width: _currentBannerIndex == index ? 16 : 6,
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: _currentBannerIndex == index
                      ? const Color(0xFFE50914)
                      : Colors.white24,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _openCategoryPage(String type, String title) {
    List initialList = [];
    if (type == 'bollywood') {
      initialList = allBollywood200.isNotEmpty ? allBollywood200 : bollywoodLatest;
    } else if (type == 'south') {
      initialList = allSouth200.isNotEmpty ? allSouth200 : southHindiDubbed;
    } else if (type == 'hollywood_movies') {
      initialList = allHollywood200.isNotEmpty ? allHollywood200 : hollywoodHindiDubbed;
    } else if (type == 'hindi_series') {
      initialList = allHindiSeries200.isNotEmpty ? allHindiSeries200 : hindiWebSeries;
    } else if (type == 'english_series') {
      initialList = allEnglishSeries200.isNotEmpty ? allEnglishSeries200 : hollywoodHindiSeries;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MobileCategoryGridScreen(
          title: title,
          rawItems: initialList,
          onItemTapped: _onItemTapped,
        ),
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildHorizontalRow(dynamic items) {
    final list = items is List ? items : [];
    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: list.length,
        itemBuilder: (ctx, i) {
          final item = list[i];
          return GestureDetector(
            onTap: () => _onItemTapped(item),
            child: Container(
              width: 175,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: const Color(0xFF1E2029),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      item['backdrop'],
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: const Color(0xFF1E2029)),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        color: Colors.black87,
                        child: Text(
                          item['title'],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0F1014),
      drawer: HomeDrawer(
        onSelectCategory: (type, title) => _openCategoryPage(type, title),
        onOpenSports: () => _openSportsListSheet(),
      ),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: AppBar(
          backgroundColor: const Color(0xFF0F1014).withOpacity(0.95),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 28),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          title: Row(
            children: [
              const Text(
                'PRIME',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE50914), Color(0xFFB20710)],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'FLX',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFE50914)),
            )
          : RefreshIndicator(
              color: const Color(0xFFE50914),
              backgroundColor: const Color(0xFF16181F),
              onRefresh: _loadAllData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Primeflix Top Tabs (Recommend, Movies, TV Shows, 18+)
                    _buildCategoryTabs(),
                    const SizedBox(height: 4),

                    // 2. Top Featured Slider / Banner
                    _buildTopFeaturedCarousel(),
                    const SizedBox(height: 6),

                    // 3. Streaming Providers Row (Netflix, Hotstar, Amazon)
                    _buildStreamingProvidersRow(),
                    const SizedBox(height: 8),

                    if (continueWatchingList.isNotEmpty) ...[
                      _buildHeader('Continue Watching'),
                      _buildHorizontalRow(continueWatchingList),
                      const SizedBox(height: 12),
                    ],

                    _buildHeader('Bollywood Latest Movies'),
                    _buildHorizontalRow(bollywoodLatest),
                    const SizedBox(height: 12),

                    _buildHeader('Hollywood Movies (Hindi Dubbed)'),
                    _buildHorizontalRow(hollywoodHindiDubbed),
                    const SizedBox(height: 12),

                    _buildHeader('Hindi Web Series'),
                    _buildHorizontalRow(hindiWebSeries),
                    const SizedBox(height: 12),

                    _buildHeader('South Indian Movies (Hindi Dubbed)'),
                    _buildHorizontalRow(southHindiDubbed),
                    const SizedBox(height: 12),

                    _buildHeader('Netflix Originals'),
                    _buildHorizontalRow(netflixSeries),
                    const SizedBox(height: 12),

                    _buildHeader('Amazon Prime Series'),
                    _buildHorizontalRow(amazonSeries),
                    const SizedBox(height: 12),

                    _buildHeader('Hollywood English Series'),
                    _buildHorizontalRow(hollywoodHindiSeries),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
      // --- BOTTOM NAVIGATION BAR AS SHOWN IN SCREENSHOT ---
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF0F1014),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFE50914), // Primeflix Red
        unselectedItemColor: Colors.white54,
        currentIndex: 0,
        onTap: (index) {
          if (index == 3) {
            // My List screen open karega
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
            icon: Icon(Icons.swap_vert_rounded),
            label: 'Sort',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.trending_up_rounded),
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
}
