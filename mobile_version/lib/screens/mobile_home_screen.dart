import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tmdb_service.dart';
import '../services/stream_service.dart';
import '../services/catalog_service.dart';
import '../widgets/mobile_stream_modal.dart';
import 'search_screen.dart';
import 'my_list_screen.dart';
import '../internal_player.dart';

const String kGistPermanentRawUrl = "https://gist.githubusercontent.com/Rahul6051276/5b0a18b2cf69a99d1d3e06629fcbc70a/raw";

// ============================================================================
// ANDROID TV & GOOGLE TV D-PAD REMOTE FOCUSABLE WIDGET
// ============================================================================
class TvFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double scaleFactor;
  final BorderRadius? borderRadius;
  final Color focusColor;

  const TvFocusable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.scaleFactor = 1.06,
    this.borderRadius,
    this.focusColor = const Color(0xFF0072D2),
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // TV Remote OK / Center button handling
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA ||
              event.logicalKey == LogicalKeyboardKey.dpadCenter) {
            widget.onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        borderRadius: widget.borderRadius ?? BorderRadius.circular(10),
        child: AnimatedScale(
          scale: _isFocused ? widget.scaleFactor : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius ?? BorderRadius.circular(10),
              border: Border.all(
                color: _isFocused ? widget.focusColor : Colors.transparent,
                width: _isFocused ? 2.5 : 0,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: widget.focusColor.withOpacity(0.6),
                        blurRadius: 12,
                        spreadRadius: 2,
                      )
                    ]
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// XTREAM ACCOUNT MODEL
// ============================================================================
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
    _loadCachedDataInstantly();
    _fetchAllDataLightningFast();
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

  // 1. INSTANT LOCAL CACHE LOAD (0.05s ME POSTERS LOAD HONGE, NO GREY BOX)
  Future<void> _loadCachedDataInstantly() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final cBolly = prefs.getString('c_bollywood');
      final cSouth = prefs.getString('c_south');
      final cHolly = prefs.getString('c_hollywood');
      final cHindiTv = prefs.getString('c_hinditv');
      final cEngTv = prefs.getString('c_englishtv');

      if (cBolly != null && cBolly.isNotEmpty) {
        bollywoodLatest = jsonDecode(cBolly);
        heroBanners = bollywoodLatest.take(6).toList();
        _startCarouselTimer(heroBanners.length);
      }
      if (cSouth != null && cSouth.isNotEmpty) southMovies = jsonDecode(cSouth);
      if (cHolly != null && cHolly.isNotEmpty) hollywoodHindiDubbed = jsonDecode(cHolly);
      if (cHindiTv != null && cHindiTv.isNotEmpty) hindiWebSeries = jsonDecode(cHindiTv);
      if (cEngTv != null && cEngTv.isNotEmpty) englishWebSeries = jsonDecode(cEngTv);

      final rawCw = prefs.getString('continue_watching_mobile');
      if (rawCw != null && rawCw.isNotEmpty) {
        continueWatchingList = jsonDecode(rawCw);
      }

      if (bollywoodLatest.isNotEmpty && mounted) {
        setState(() => isLoading = false);
      }
    } catch (_) {}
  }

  // 2. PARALLEL BACKGROUND REFRESH (ALL CATEGORIES AT ONCE IN 2 SECONDS)
  Future<void> _fetchAllDataLightningFast() async {
    final prefs = await SharedPreferences.getInstance();

    // Fetch Gist
    try {
      final freshGistUrl = "$kGistPermanentRawUrl?t=${DateTime.now().millisecondsSinceEpoch}";
      final res = await http.get(Uri.parse(freshGistUrl)).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        activeProviders = data['active_providers'] ?? [];
        _parseXtreamCredentials(data);
      }
    } catch (_) {}

    if (activeProviders.isEmpty) {
      activeProviders = [{'name': 'Render Cloud', 'url': 'https://vidsrc.me'}];
    }

    // Filter helper to completely ban Anime and Daily Soaps
    bool isCleanItem(dynamic m) {
      final genres = (m['genre_ids'] as List?) ?? [];
      final origLang = m['original_language']?.toString().toLowerCase() ?? '';
      if (genres.contains(16) || origLang == 'ja') return false; // No Anime
      if (genres.contains(10766) || genres.contains(10764) || genres.contains(10762) || genres.contains(10763)) {
        return false; // No Soaps or Reality
      }
      return true;
    }

    // Parallel execution for all rows
    try {
      final futures = [
        // Bollywood
        http.get(Uri.parse(
          '${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=hi&primary_release_date.gte=2024-01-01&sort_by=popularity.desc&without_genres=16',
        )).timeout(const Duration(seconds: 6)),

        // South
        http.get(Uri.parse(
          '${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=te|ta|ml|kn&primary_release_date.gte=2024-01-01&sort_by=popularity.desc&without_genres=16',
        )).timeout(const Duration(seconds: 6)),

        // Hollywood
        http.get(Uri.parse(
          '${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=en&primary_release_date.gte=2024-01-01&sort_by=popularity.desc&without_genres=16',
        )).timeout(const Duration(seconds: 6)),

        // Hindi Web Series (Top OTT Networks Only)
        http.get(Uri.parse(
          '${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_networks=1024|213|3919|2893|2892|3671&with_original_language=hi&without_genres=16,10762,10764,10766,10767,10763&vote_count.gte=10&sort_by=popularity.desc',
        )).timeout(const Duration(seconds: 6)),

        // English Web Series
        http.get(Uri.parse(
          '${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_networks=213|1024|49|2739|2552&without_genres=16,10762,10764,10766,10767,10763&vote_count.gte=20&sort_by=popularity.desc',
        )).timeout(const Duration(seconds: 6)),
      ];

      final results = await Future.wait(futures);

      if (results[0].statusCode == 200) {
        final list = (jsonDecode(results[0].body)['results'] as List? ?? []).where(isCleanItem).toList();
        if (list.isNotEmpty) {
          bollywoodLatest = CatalogService.parseResults(list);
          heroBanners = bollywoodLatest.take(6).toList();
          _startCarouselTimer(heroBanners.length);
          prefs.setString('c_bollywood', jsonEncode(bollywoodLatest));
        }
      }

      if (results[1].statusCode == 200) {
        final list = (jsonDecode(results[1].body)['results'] as List? ?? []).where(isCleanItem).toList();
        if (list.isNotEmpty) {
          southMovies = CatalogService.parseResults(list);
          prefs.setString('c_south', jsonEncode(southMovies));
        }
      }

      if (results[2].statusCode == 200) {
        final list = (jsonDecode(results[2].body)['results'] as List? ?? []).where(isCleanItem).toList();
        if (list.isNotEmpty) {
          hollywoodHindiDubbed = CatalogService.parseResults(list);
          prefs.setString('c_hollywood', jsonEncode(hollywoodHindiDubbed));
        }
      }

      if (results[3].statusCode == 200) {
        final list = (jsonDecode(results[3].body)['results'] as List? ?? []).where(isCleanItem).toList();
        if (list.isNotEmpty) {
          hindiWebSeries = CatalogService.parseResults(list, isTv: true);
          prefs.setString('c_hinditv', jsonEncode(hindiWebSeries));
        }
      }

      if (results[4].statusCode == 200) {
        final list = (jsonDecode(results[4].body)['results'] as List? ?? []).where(isCleanItem).toList();
        if (list.isNotEmpty) {
          englishWebSeries = CatalogService.parseResults(list, isTv: true);
          prefs.setString('c_englishtv', jsonEncode(englishWebSeries));
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() => isLoading = false);
    }
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
            onPlaySaved: () => _refreshContinueWatching(),
          );
        },
      );
    }
  }

  Future<void> _refreshContinueWatching() async {
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

  Future<void> _saveContinueWatching(dynamic item) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List list = List.from(continueWatchingList);
      list.removeWhere((e) => e['tmdb_id'].toString() == item['tmdb_id'].toString());
      list.insert(0, item);
      if (list.length > 20) list = list.take(20).toList();
      await prefs.setString('continue_watching_mobile', jsonEncode(list));
      _refreshContinueWatching();
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
            TvFocusable(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchScreen()),
                );
              },
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(Icons.search_rounded, color: Colors.white, size: 26),
              ),
            ),
          ],
        ),
      ),
      body: isLoading && bollywoodLatest.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0072D2)),
            )
          : RefreshIndicator(
              color: const Color(0xFF0072D2),
              backgroundColor: const Color(0xFF16181F),
              onRefresh: _fetchAllDataLightningFast,
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
    if (heroBanners.isEmpty) return const SizedBox.shrink();

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
          return TvFocusable(
            onTap: () => _onItemTapped(item),
            onLongPress: () => _addToMyList(item),
            borderRadius: BorderRadius.circular(14),
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
          final String providerName = p['name'] as String;
          final Color color = p['color'] as Color;

          return TvFocusable(
            onTap: () => _openProviderCatalog(providerName, color),
            focusColor: color,
            borderRadius: BorderRadius.circular(10),
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
              return TvFocusable(
                onTap: () => _onItemTapped(item),
                onLongPress: () => _addToMyList(item),
                borderRadius: BorderRadius.circular(8),
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

// ============================================================================
// WEB SERIES SEASON & EPISODE SELECTOR SHEET
// ============================================================================
class _MobileSeasonEpisodeSelectorSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  final List activeProviders;
  final List<XtreamAccount> xtreamAccounts;
  final Map<String, String> iptvHeaders;
  final Function(String url, String title) onPlayEpisode;

  const _MobileSeasonEpisodeSelectorSheet({
    required this.item,
    required this.activeProviders,
    required this.xtreamAccounts,
    required this.iptvHeaders,
    required this.onPlayEpisode,
  });

  @override
  State<_MobileSeasonEpisodeSelectorSheet> createState() => _MobileSeasonEpisodeSelectorSheetState();
}

class _MobileSeasonEpisodeSelectorSheetState extends State<_MobileSeasonEpisodeSelectorSheet> {
  bool isLoading = true;
  String? errorMessage;
  Map<String, List<dynamic>> seasonsMap = {};
  String? selectedSeason;

  @override
  void initState() {
    super.initState();
    _loadSeriesEpisodes();
  }

  String _clean(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').trim();
  }

  Future<void> _loadSeriesEpisodes() async {
    if (widget.xtreamAccounts.isEmpty) {
      if (mounted) {
        setState(() {
          isLoading = false;
          errorMessage = 'Xtream servers not configured in Gist.';
        });
      }
      return;
    }

    final cleanTitle = _clean(widget.item['title'] ?? '');

    for (var acc in widget.xtreamAccounts) {
      try {
        final seriesListUrl = Uri.parse('${acc.host}/player_api.php?username=${acc.username}&password=${acc.password}&action=get_series');
        final seriesRes = await http.get(seriesListUrl, headers: widget.iptvHeaders).timeout(const Duration(seconds: 15));

        if (seriesRes.statusCode == 200) {
          final seriesList = jsonDecode(seriesRes.body) as List;

          dynamic targetSeries;
          for (var s in seriesList) {
            final sName = _clean(s['name']?.toString() ?? '');
            if (sName.contains(cleanTitle) || cleanTitle.contains(sName)) {
              targetSeries = s;
              break;
            }
          }

          if (targetSeries != null) {
            final seriesId = targetSeries['series_id'];
            final infoUrl = Uri.parse('${acc.host}/player_api.php?username=${acc.username}&password=${acc.password}&action=get_series_info&series_id=$seriesId');
            final infoRes = await http.get(infoUrl, headers: widget.iptvHeaders).timeout(const Duration(seconds: 15));

            if (infoRes.statusCode == 200) {
              final infoData = jsonDecode(infoRes.body);
              final episodes = infoData['episodes'];

              if (episodes != null && episodes is Map && episodes.isNotEmpty) {
                episodes.forEach((seasonNum, epList) {
                  if (epList is List) {
                    seasonsMap[seasonNum.toString()] = epList;
                  }
                });

                if (seasonsMap.isNotEmpty) {
                  selectedSeason = seasonsMap.keys.first;
                  break;
                }
              }
            }
          }
        }
      } catch (_) {
        continue;
      }
    }

    if (mounted) {
      setState(() {
        isLoading = false;
        if (seasonsMap.isEmpty && errorMessage == null) {
          errorMessage = 'Web series kisi bhi Xtream server par nahi mili!';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(
        color: Color(0xFF16181F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.item['title'] ?? 'Select Episode',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              if (seasonsMap.isNotEmpty)
                DropdownButton<String>(
                  value: selectedSeason,
                  dropdownColor: const Color(0xFF1F222E),
                  style: const TextStyle(color: Color(0xFF0072D2), fontWeight: FontWeight.bold),
                  underline: const SizedBox(),
                  items: seasonsMap.keys.map((s) {
                    return DropdownMenuItem(value: s, child: Text('Season $s'));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => selectedSeason = val);
                  },
                ),
            ],
          ),
          const Divider(color: Colors.white24, height: 20),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0072D2)))
                : errorMessage != null
                    ? Center(child: Text(errorMessage!, style: const TextStyle(color: Colors.white60)))
                    : ListView.builder(
                        itemCount: seasonsMap[selectedSeason]?.length ?? 0,
                        itemBuilder: (ctx, i) {
                          final ep = seasonsMap[selectedSeason]![i];
                          final epNum = ep['episode_num'] ?? (i + 1);
                          final epTitle = ep['title'] ?? 'Episode $epNum';

                          return TvFocusable(
                            onTap: () {
                              Navigator.pop(context);
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: const Color(0xFF16181F),
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                                ),
                                builder: (ctx) {
                                  return MobileQualitySelectorSheet(
                                    item: widget.item,
                                    season: int.tryParse(selectedSeason ?? '1') ?? 1,
                                    episode: int.tryParse(epNum.toString()) ?? 1,
                                    providers: widget.activeProviders,
                                    onPlaySaved: () {},
                                  );
                                },
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: ListTile(
                              leading: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0072D2).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text('$epNum', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                              title: Text(epTitle, style: const TextStyle(color: Colors.white, fontSize: 14)),
                              trailing: const Icon(Icons.play_circle_fill, color: Color(0xFF0072D2), size: 30),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// OTT PLATFORM CATALOG SCREEN (NETFLIX, HOTSTAR, PRIME, ZEE5, SONYLIV)
// WITH TV REMOTE FRIENDLY FOCUSABLE GRID
// ============================================================================
class _MobileCategoryGridScreen extends StatefulWidget {
  final String providerName;
  final Color providerColor;
  final Function(dynamic) onItemTapped;
  final Function(dynamic) onItemLongPressed;

  const _MobileCategoryGridScreen({
    required this.providerName,
    required this.providerColor,
    required this.onItemTapped,
    required this.onItemLongPressed,
  });

  @override
  State<_MobileCategoryGridScreen> createState() => _MobileCategoryGridScreenState();
}

class _MobileCategoryGridScreenState extends State<_MobileCategoryGridScreen> {
  String selectedType = 'Movies';
  bool isLoading = true;
  List<dynamic> items = [];

  final Map<String, List<dynamic>> _catalogCache = {};

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  String _getProviderIds(String name) {
    switch (name) {
      case 'Netflix':
        return '8|175';
      case 'JioHotstar':
        return '122|220|337|390|384';
      case 'Prime Video':
        return '119|9';
      case 'ZEE5':
        return '232';
      case 'SonyLIV':
        return '237';
      default:
        return '8';
    }
  }

  bool _isCleanCatalogItem(dynamic m) {
    final genres = (m['genre_ids'] as List?) ?? [];
    final origLang = m['original_language']?.toString().toLowerCase() ?? '';

    if (genres.contains(16) || origLang == 'ja') return false; // No Anime
    if (genres.contains(10766) || genres.contains(10764) || genres.contains(10762) || genres.contains(10763)) {
      return false; // No Soaps or Reality
    }
    return true;
  }

  Future<void> _loadCatalog() async {
    final cacheKey = selectedType;
    if (_catalogCache.containsKey(cacheKey) && _catalogCache[cacheKey]!.isNotEmpty) {
      setState(() {
        items = _catalogCache[cacheKey]!;
        isLoading = false;
      });
      return;
    }

    setState(() => isLoading = true);

    final providerIds = _getProviderIds(widget.providerName);
    final bool isTv = (selectedType == 'Web Series');
    final String endpoint = isTv ? 'discover/tv' : 'discover/movie';

    List<dynamic> fetchedResults = [];

    try {
      final banFilter = '&without_genres=16,10762,10764,10766,10767,10763';

      final futures = [1, 2, 3, 4].map((page) {
        final url = Uri.parse(
          '${AppConfig.tmdbBase}/$endpoint?api_key=${AppConfig.tmdbKey}&watch_region=IN&with_watch_providers=$providerIds&sort_by=popularity.desc$banFilter&vote_count.gte=5&page=$page',
        );
        return http.get(url).timeout(const Duration(seconds: 7));
      }).toList();

      final responses = await Future.wait(futures);

      for (var res in responses) {
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final rawList = data['results'] as List? ?? [];
          for (var m in rawList) {
            if (!_isCleanCatalogItem(m)) continue;

            final title = isTv ? (m['name'] ?? m['original_name'] ?? '') : (m['title'] ?? m['original_title'] ?? '');
            final posterPath = m['poster_path'];
            final date = isTv ? (m['first_air_date'] ?? '') : (m['release_date'] ?? '');
            final year = date.toString().split('-').first;

            if (posterPath != null && posterPath.toString().isNotEmpty) {
              fetchedResults.add({
                'tmdb_id': m['id'],
                'title': title,
                'poster': 'https://image.tmdb.org/t/p/w500$posterPath',
                'backdrop': m['backdrop_path'] != null ? 'https://image.tmdb.org/t/p/w780${m['backdrop_path']}' : '',
                'year': year,
                'rating': (m['vote_average'] ?? 0.0).toString(),
                'isTv': isTv,
              });
            }
          }
        }
      }

      // Hotstar Fallback for full 60+ catalog
      if (fetchedResults.length < 25 && isTv && widget.providerName == 'JioHotstar') {
        final fallbackUrl = Uri.parse(
          '${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_networks=3919|3671|2739$banFilter&sort_by=popularity.desc&page=1',
        );
        final fbRes = await http.get(fallbackUrl).timeout(const Duration(seconds: 6));
        if (fbRes.statusCode == 200) {
          final data = jsonDecode(fbRes.body);
          final rawList = data['results'] as List? ?? [];
          for (var m in rawList) {
            if (!_isCleanCatalogItem(m)) continue;
            final title = m['name'] ?? m['original_name'] ?? '';
            final posterPath = m['poster_path'];
            final date = m['first_air_date'] ?? '';
            final year = date.toString().split('-').first;
            if (posterPath != null && posterPath.toString().isNotEmpty) {
              fetchedResults.add({
                'tmdb_id': m['id'],
                'title': title,
                'poster': 'https://image.tmdb.org/t/p/w500$posterPath',
                'backdrop': m['backdrop_path'] != null ? 'https://image.tmdb.org/t/p/w780${m['backdrop_path']}' : '',
                'year': year,
                'rating': (m['vote_average'] ?? 0.0).toString(),
                'isTv': isTv,
              });
            }
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        items = fetchedResults;
        _catalogCache[cacheKey] = fetchedResults;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1014),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1014),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: widget.providerColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.providerName.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '(${items.length})',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2029),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: widget.providerColor, width: 1.2),
            ),
            alignment: Alignment.center,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedType,
                dropdownColor: const Color(0xFF1E2029),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 20),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                items: const [
                  DropdownMenuItem(
                    value: 'Movies',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.movie_creation_outlined, color: Colors.white70, size: 16),
                        SizedBox(width: 6),
                        Text('Movies'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Web Series',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tv_rounded, color: Colors.white70, size: 16),
                        SizedBox(width: 6),
                        Text('Web Series'),
                      ],
                    ),
                  ),
                ],
                onChanged: (val) {
                  if (val != null && val != selectedType) {
                    setState(() {
                      selectedType = val;
                    });
                    _loadCatalog();
                  }
                },
              ),
            ),
          ),
        ],
      ),
      body: isLoading
          ? Center(
              child: CircularProgressIndicator(color: widget.providerColor),
            )
          : items.isEmpty
              ? const Center(
                  child: Text(
                    'No content available for this platform.',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.62,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final item = items[i];
                    return TvFocusable(
                      onTap: () => widget.onItemTapped(item),
                      onLongPress: () => widget.onItemLongPressed(item),
                      focusColor: widget.providerColor,
                      borderRadius: BorderRadius.circular(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.network(
                                    item['poster'] ?? '',
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Colors.grey[900],
                                      child: const Icon(Icons.broken_image, color: Colors.white24),
                                    ),
                                  ),
                                  if (item['rating'] != null && item['rating'] != '0.0')
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.75),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.star, color: Colors.amber, size: 10),
                                            const SizedBox(width: 2),
                                            Text(
                                              double.tryParse(item['rating'])?.toStringAsFixed(1) ?? item['rating'],
                                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item['title'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
