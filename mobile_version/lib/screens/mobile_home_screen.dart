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
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA) {
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

  Future<void> _fetchAllDataLightningFast() async {
    final prefs = await SharedPreferences.getInstance();

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

    bool isCleanItem(dynamic m) {
      final genres = (m['genre_ids'] as List?) ?? [];
      final origLang = m['original_language']?.toString().toLowerCase() ?? '';
      if (genres.contains(16) || origLang == 'ja') return false;
      if (genres.contains(10766) || genres.contains(10764) || genres.contains(10762) || genres.contains(10763)) {
        return false;
      }
      return true;
    }

    try {
      final futures = [
        http.get(Uri.parse(
          '${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=hi&primary_release_date.gte=2024-01-01&sort_by=popularity.desc&without_genres=16',
        )).timeout(const Duration(seconds: 6)),

        http.get(Uri.parse(
          '${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=te|ta|ml|kn&primary_release_date.gte=2024-01-01&sort_by=popularity.desc&without_genres=16',
        )).timeout(const Duration(seconds: 6)),

        http.get(Uri.parse(
          '${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=en&primary_release_date.gte=2024-01-01&sort_by=popularity.desc&without_genres=16',
        )).timeout(const Duration(seconds: 6)),

        http.get(Uri.parse(
          '${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_networks=1024|213|3919|2893|2892|3671&with_original_language=hi&without_genres=16,10762,10764,10766,10767,10763&vote_count.gte=10&sort_by=popularity.desc',
        )).timeout(const Duration(seconds: 6)),

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

    if (mounted) setState(() => isLoading = false);
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isTv = screenWidth > 600;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1014),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(isTv ? 70 : 60),
        child: AppBar(
          backgroundColor: const Color(0xFF0F1014),
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Text(
            'Primeflix',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: isTv ? 26 : 22,
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
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(Icons.search_rounded, color: Colors.white, size: isTv ? 30 : 26),
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Streaming',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isTv ? 20 : 16,
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
                    _buildHor
