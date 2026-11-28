import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import '../services/app_settings_service.dart';
import '../services/stream_service.dart';
import '../services/tmdb_service.dart';
import '../widgets/mobile_stream_modal.dart';
import 'catalog_collection_screen.dart';
import 'my_list_screen.dart';
import 'settings_screen.dart';

class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  static const Color _primeBlue = Color(0xFF00A8E1);
  static const Color _darkBg = Color(0xFF0B1118);
  static const Color _cardBg = Color(0xFF15202B);

  int _navIndex = 0;
  bool _isLoading = true;
  bool _hasTmdbKey = false;
  int _connectedProviders = 0;

  List _bollywoodMovies = [];
  List _southMovies = [];
  List _hollywoodMovies = [];
  List _hindiWebSeries = [];
  List _netflixWebSeries = [];
  List _amazonWebSeries = [];

  final PageController _bannerController = PageController();
  Timer? _bannerTimer;
  int _currentBannerPage = 0;

  final GlobalKey _myListKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerController.dispose();
    super.dispose();
  }

  void _startBannerAutoSlide(int count) {
    _bannerTimer?.cancel();
    if (count <= 1) return;
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_bannerController.hasClients) return;
      final next = (_currentBannerPage + 1) % count;
      _bannerController.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<List> _fetchTmdbFallback({
    required String apiKey,
    required bool isTv,
    required String lang,
  }) async {
    if (apiKey.trim().isEmpty) return [];
    final type = isTv ? 'tv' : 'movie';
    final sort = isTv ? 'first_air_date.desc' : 'primary_release_date.desc';
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final voteFilter = lang == 'en' ? '&vote_count.gte=5' : '&vote_count.gte=1';
    final dateParam = isTv
        ? '&first_air_date.lte=$today&without_genres=10766,10767,10764,10763$voteFilter'
        : '&primary_release_date.lte=$today$voteFilter';

    final uri = Uri.parse(
      'https://api.themoviedb.org/3/discover/$type'
      '?api_key=$apiKey'
      '&with_original_language=$lang'
      '&sort_by=$sort'
      '$dateParam'
      '&page=1',
    );

    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return [];
      final decoded = jsonDecode(res.body);
      final results = decoded['results'];
      if (results is! List) return [];
      final List list = [];
      for (final raw in results) {
        if (raw is Map &&
            (raw['backdrop_path'] != null || raw['poster_path'] != null)) {
          final map = Map<String, dynamic>.from(raw);
          map['isTv'] = isTv;
          map['tmdb_id'] = map['id'];
          list.add(map);
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  List _buildBannerSlides() {
    final List slides = [];
    final Set usedIds = {};

    void addLatestFrom(List source, String badge) {
      Map? chosen;
      for (final item in source) {
        if (item is Map) {
          final id = item['id'] ?? item['tmdb_id'] ?? item['title'] ?? item['name'];
          final bd = (item['backdrop_path'] ?? '').toString();
          if (bd.isNotEmpty && (id == null || !usedIds.contains(id))) {
            chosen = item;
            break;
          }
        }
      }
      if (chosen == null) {
        for (final item in source) {
          if (item is Map) {
            final id = item['id'] ?? item['tmdb_id'] ?? item['title'] ?? item['name'];
            final ps = (item['poster_path'] ?? item['poster'] ?? '').toString();
            if (ps.isNotEmpty && (id == null || !usedIds.contains(id))) {
              chosen = item;
              break;
            }
          }
        }
      }

      if (chosen != null) {
        final id =
            chosen['id'] ?? chosen['tmdb_id'] ?? chosen['title'] ?? chosen['name'];
        if (id != null) usedIds.add(id);
        slides.add({
          'item': chosen,
          'badge': badge,
        });
      }
    }

    addLatestFrom(_bollywoodMovies, 'NEW • BOLLYWOOD');
    addLatestFrom(_southMovies, 'NEW • SOUTH MOVIE');
    addLatestFrom(_hollywoodMovies, 'NEW • HOLLYWOOD');
    addLatestFrom(_hindiWebSeries, 'NEW • HINDI SERIES');

    final List globalPool = [
      ..._netflixWebSeries,
      ..._amazonWebSeries,
    ];
    addLatestFrom(globalPool, 'NEW • GLOBAL SERIES');

    return slides;
  }

  Future _initData() async {
    setState(() => _isLoading = true);

    final tmdbKey = await AppSettingsService.getTmdbApiKey();
    final results = await Future.wait([
      TmdbService.getLatestBollywoodMovies(),
      TmdbService.getLatestSouthMovies(),
      TmdbService.getLatestHollywoodMovies(),
      TmdbService.getLatestHindiWebSeries(),
      TmdbService.getLatestNetflixWebSeries(),
      TmdbService.getLatestAmazonWebSeries(),
      StreamService.loadProviders(forceRefresh: true),
    ]);

    List bolly = results[0] as List;
    List south = results[1] as List;
    List holly = results[2] as List;
    List hindiSeries = results[3] as List;
    List netflixSeries = results[4] as List;
    List amazonSeries = results[5] as List;

    // Jo bhi category empty aaye uske liye direct TMDB se fallback lein
    if (tmdbKey.isNotEmpty) {
      final fallbackTasks = <Future>[];
      final needBolly = bolly.isEmpty;
      final needSouth = south.isEmpty;
      final needHolly = holly.isEmpty;
      final needHindiSeries = hindiSeries.isEmpty;
      final needGlobalSeries = netflixSeries.isEmpty && amazonSeries.isEmpty;

      if (needBolly) {
        fallbackTasks.add(
            _fetchTmdbFallback(apiKey: tmdbKey, isTv: false, lang: 'hi'));
      }
      if (needSouth) {
        fallbackTasks.add(_fetchTmdbFallback(
            apiKey: tmdbKey, isTv: false, lang: 'te|ta|ml|kn'));
      }
      if (needHolly) {
        fallbackTasks.add(
            _fetchTmdbFallback(apiKey: tmdbKey, isTv: false, lang: 'en'));
      }
      if (needHindiSeries) {
        fallbackTasks.add(
            _fetchTmdbFallback(apiKey: tmdbKey, isTv: true, lang: 'hi'));
      }
      if (needGlobalSeries) {
        fallbackTasks.add(
            _fetchTmdbFallback(apiKey: tmdbKey, isTv: true, lang: 'en'));
      }

      if (fallbackTasks.isNotEmpty) {
        final fbResults = await Future.wait(fallbackTasks);
        int idx = 0;
        if (needBolly) bolly = fbResults[idx++];
        if (needSouth) south = fbResults[idx++];
        if (needHolly) holly = fbResults[idx++];
        if (needHindiSeries) hindiSeries = fbResults[idx++];
        if (needGlobalSeries) netflixSeries = fbResults[idx++];
      }
    }

    if (!mounted) return;
    setState(() {
      _hasTmdbKey = tmdbKey.isNotEmpty;
      _bollywoodMovies = bolly;
      _southMovies = south;
      _hollywoodMovies = holly;
      _hindiWebSeries = hindiSeries;
      _netflixWebSeries = netflixSeries;
      _amazonWebSeries = amazonSeries;
      _connectedProviders = (results[6] as List).length;
      _currentBannerPage = 0;
      _isLoading = false;
    });

    final slides = _buildBannerSlides();
    _startBannerAutoSlide(slides.length);
  }

  void _openSearchSheet() {
    final searchController = TextEditingController();
    List results = [];
    bool searching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _darkBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future runSearch(String q) async {
              if (q.trim().isEmpty) return;
              setSheetState(() => searching = true);
              final data = await TmdbService.searchMulti(q);
              if (!ctx.mounted) return;
              setSheetState(() {
                results = data;
                searching = false;
              });
            }

            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.9,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      textInputAction: TextInputAction.search,
                      onSubmitted: runSearch,
                      decoration: InputDecoration(
                        hintText: 'Search movies or web series...',
                        hintStyle: const TextStyle(color: Colors.white54),
                        prefixIcon: const Icon(Icons.search, color: Colors.white70),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_forward, color: _primeBlue),
                          onPressed: () => runSearch(searchController.text),
                        ),
                        filled: true,
                        fillColor: _cardBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: searching
                          ? const Center(
                              child: CircularProgressIndicator(color: _primeBlue),
                            )
                          : results.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Koi Movie ya Web Series search karein',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                )
                              : GridView.builder(
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    childAspectRatio: 0.64,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                  ),
                                  itemCount: results.length,
                                  itemBuilder: (_, i) {
                                    final item = results[i];
                                    return _MobilePosterCard(
                                      item: item,
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        MobileStreamModal.show(context, item);
                                      },
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeroBanner() {
    final slides = _buildBannerSlides();
    if (slides.isEmpty) return const SizedBox.shrink();

    final activeIndex = _currentBannerPage.clamp(0, slides.length - 1);

    return SizedBox(
      height: 335,
      child: Stack(
        children: [
          PageView.builder(
            controller: _bannerController,
            itemCount: slides.length,
            onPageChanged: (index) {
              setState(() => _currentBannerPage = index);
            },
            itemBuilder: (context, index) {
              final slide = slides[index];
              final hero = slide['item'];
              final badge = (slide['badge'] ?? 'NEW RELEASE').toString();
              final backdrop = TmdbService.getBackdropUrl(
                hero['backdrop_path'] ?? hero['poster_path'],
              );
              final title = (hero['title'] ?? hero['name'] ?? '').toString();
              final releaseDate =
                  (hero['release_date'] ?? hero['first_air_date'] ?? '').toString();
              final year =
                  releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';
              final rating = (hero['vote_average'] is num)
                  ? (hero['vote_average'] as num).toStringAsFixed(1)
                  : '';

              return GestureDetector(
                onTap: () => MobileStreamModal.show(context, hero),
                child: Stack(
                  alignment: Alignment.bottomLeft,
                  children: [
                    backdrop.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: backdrop,
                            height: 335,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          )
                        : Container(height: 335, color: _cardBg),
                    Container(
                      height: 335,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black26,
                            Colors.transparent,
                            Color(0xCC0B1118),
                            _darkBg,
                          ],
                          stops: [0.0, 0.35, 0.78, 1.0],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _primeBlue,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  badge,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.9,
                                  ),
                                ),
                              ),
                              if (year.isNotEmpty || rating.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: Text(
                                    [
                                      if (year.isNotEmpty) year,
                                      if (rating.isNotEmpty && rating != '0.0')
                                        '★ $rating',
                                    ].join('  •  '),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primeBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 22, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () => MobileStreamModal.show(context, hero),
                            icon: const Icon(Icons.play_arrow, size: 22),
                            label: const Text(
                              'Watch Now',
                              style: TextStyle(
                                  fontSize: 14.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(slides.length, (idx) {
                final isSelected = idx == activeIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 6,
                  width: isSelected ? 22 : 6,
                  decoration: BoxDecoration(
                    color: isSelected ? _primeBlue : Colors.white38,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: _primeBlue,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 11),
            itemBuilder: (_, index) {
              final item = items[index];
              return SizedBox(
                width: 124,
                child: _MobilePosterCard(
                  item: item,
                  onTap: () => MobileStreamModal.show(context, item),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHomeBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _primeBlue),
      );
    }

    final noCatalogs = _bollywoodMovies.isEmpty &&
        _southMovies.isEmpty &&
        _hollywoodMovies.isEmpty &&
        _hindiWebSeries.isEmpty;

    return RefreshIndicator(
      color: _primeBlue,
      onRefresh: _initData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (noCatalogs)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _primeBlue.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _hasTmdbKey
                        ? 'Catalog load nahi ho paya'
                        : 'TMDB API Key & Gist URL set karein',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Settings tab mein apna Gist Raw URL aur TMDB API Key dalein, phir Save & Connect dabayein.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primeBlue,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => setState(() => _navIndex = 4),
                    icon: const Icon(Icons.settings),
                    label: const Text('Open Settings'),
                  ),
                ],
              ),
            ),
          _buildHeroBanner(),
          _buildSection('Latest Bollywood Movies', _bollywoodMovies),
          _buildSection('Latest South Movies', _southMovies),
          _buildSection('Latest Hollywood Movies', _hollywoodMovies),
          _buildSection('Latest Hindi Web Series', _hindiWebSeries),
          _buildSection('Latest Netflix Web Series', _netflixWebSeries),
          _buildSection('Latest Amazon Prime Web Series', _amazonWebSeries),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildHomeBody(),
      CatalogCollectionScreen(
        key: const ValueKey('all_movies_collection'),
        isTv: false,
        onItemTap: (item) => MobileStreamModal.show(context, item),
      ),
      CatalogCollectionScreen(
        key: const ValueKey('all_series_collection'),
        isTv: true,
        onItemTap: (item) => MobileStreamModal.show(context, item),
      ),
      MyListScreen(key: _myListKey),
      SettingsScreen(onSettingsUpdated: _initData),
    ];

    return Scaffold(
      backgroundColor: _darkBg,
      appBar: _navIndex == 0
          ? AppBar(
              backgroundColor: _darkBg,
              title: const Text(
                'PRIMEFLIX',
                style: TextStyle(
                  color: _primeBlue,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.8,
                ),
              ),
              actions: [
                if (_connectedProviders > 0)
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_connectedProviders Servers',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.white),
                  onPressed: _openSearchSheet,
                ),
              ],
            )
          : null,
      body: pages[_navIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _navIndex,
        type: BottomNavigationBarType.fixed,
        backgroundColor: _cardBg,
        selectedItemColor: _primeBlue,
        unselectedItemColor: Colors.white54,
        selectedFontSize: 11.5,
        unselectedFontSize: 11,
        onTap: (idx) {
          setState(() => _navIndex = idx);
          if (idx == 3) {
            final state = _myListKey.currentState as dynamic;
            state?.loadMyList();
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.movie_rounded), label: 'Movies'),
          BottomNavigationBarItem(icon: Icon(Icons.tv_rounded), label: 'Web Series'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmarks_rounded), label: 'My List'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}

class _MobilePosterCard extends StatelessWidget {
  final dynamic item;
  final VoidCallback onTap;

  const _MobilePosterCard({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final posterUrl = TmdbService.getPosterUrl(
      item['poster_path'] ?? item['poster'],
    );
    final title = (item['title'] ?? item['name'] ?? '').toString();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF15202B),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: posterUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: posterUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: const Color(0xFF15202B),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: const Color(0xFF15202B),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                  ),
                )
              : Container(
                  color: const Color(0xFF15202B),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                  ),
                ),
        ),
      ),
    );
  }
}