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

// Xtream Server Model
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

  List netflixCatalog = [];
  List primeCatalog = [];
  List hotstarCatalog = [];
  List zee5Catalog = [];
  List sonylivCatalog = [];

  // Multiple Xtream IPTV Servers from Gist
  final List<XtreamAccount> _xtreamAccounts = [];

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
    _preloadAllXtreamVodInBackground();
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

  // Gist JSON se xc_host, xc_username, xc_password parse karna
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

  // Har Xtream server ke VOD background me cache karna
  void _preloadAllXtreamVodInBackground() async {
    for (var acc in _xtreamAccounts) {
      try {
        final url = Uri.parse('${acc.host}/player_api.php?username=${acc.username}&password=${acc.password}&action=get_vod_streams');
        final res = await http.get(url).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          acc.cachedVod = jsonDecode(res.body);
        }
      } catch (_) {}
    }
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

  // Saare available Xtream servers me Movie search karega (Server 1 -> Server 2 -> Server 3)
  Future<String?> _getXtreamMovieUrl({required String title, String? tmdbId}) async {
    if (_xtreamAccounts.isEmpty) {
      try {
        final res = await http.get(Uri.parse(AppConfig.gistUrl)).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          _parseXtreamCredentials(jsonDecode(res.body));
        }
      } catch (_) {}
    }

    if (_xtreamAccounts.isEmpty) return null;

    final cleanQuery = _cleanTitle(title);

    for (var acc in _xtreamAccounts) {
      if (acc.cachedVod == null) {
        try {
          final url = Uri.parse('${acc.host}/player_api.php?username=${acc.username}&password=${acc.password}&action=get_vod_streams');
          final res = await http.get(url).timeout(const Duration(seconds: 8));
          if (res.statusCode == 200) {
            acc.cachedVod = jsonDecode(res.body);
          }
        } catch (_) {
          continue; // agla server try karein
        }
      }

      if (acc.cachedVod == null) continue;

      // 1. Check TMDB ID match
      if (tmdbId != null && tmdbId.isNotEmpty) {
        for (var vod in acc.cachedVod!) {
          if (vod['tmdb_id']?.toString() == tmdbId) {
            final streamId = vod['stream_id'];
            final ext = vod['container_extension'] ?? 'mp4';
            return '${acc.host}/movie/${acc.username}/${acc.password}/$streamId.$ext';
          }
        }
      }

      // 2. Check Title match
      for (var vod in acc.cachedVod!) {
        final vodName = vod['name']?.toString() ?? '';
        if (_isTitleMatch(vodName, cleanQuery)) {
          final streamId = vod['stream_id'];
          final ext = vod['container_extension'] ?? 'mp4';
          return '${acc.host}/movie/${acc.username}/${acc.password}/$streamId.$ext';
        }
      }
    }

    return null; // kisi bhi server par nahi mili
  }

  Future<void> _playMovieWithXtream(dynamic item) async {
    final title = item['title'] ?? item['name'] ?? 'Movie';
    final tmdbId = item['tmdb_id']?.toString() ?? item['id']?.toString();

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
                  'Searching across Xtream IPTV Servers...',
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
            content: Text('"$title" kisi bhi Xtream server par nahi mili!'),
            backgroundColor: Colors.redAccent,
            action: SnackBarAction(
              label: 'Standard Stream',
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
            xtreamAccounts: _xtreamAccounts,
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

// Web Series Episode Selector across Xtream Servers
class _MobileSeasonEpisodeSelectorSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  final List activeProviders;
  final List<XtreamAccount> xtreamAccounts;
  final Function(String url, String title) onPlayEpisode;

  const _MobileSeasonEpisodeSelectorSheet({
    required this.item,
    required this.activeProviders,
    required this.xtreamAccounts,
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
  XtreamAccount? matchedAccount;

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
        final seriesRes = await http.get(seriesListUrl).timeout(const Duration(seconds: 8));

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
            final infoRes = await http.get(infoUrl).timeout(const Duration(seconds: 8));

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
                  matchedAccount = acc;
                  break; // Server mil gaya
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
                          final ext = ep['container_extension'] ?? 'mp4';
                          final epId = ep['id'];

                          return ListTile(
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
                            onTap: () {
                              if (matchedAccount == null) return;
                              final streamUrl = '${matchedAccount!.host}/series/${matchedAccount!.username}/${matchedAccount!.password}/$epId.$ext';
                              Navigator.pop(context);
                              widget.onPlayEpisode(streamUrl, '${widget.item['title']} - S$selectedSeason E$epNum');
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _MobileCategoryGridScreen extends StatelessWidget {
  final String title;
  final List rawItems;
  final Function(dynamic) onItemTapped;
  final Function(dynamic) onItemLongPressed;

  const _MobileCategoryGridScreen({
    required this.title,
    required this.rawItems,
    required this.onItemTapped,
    required this.onItemLongPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1014),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1014),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.65,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: rawItems.length,
        itemBuilder: (ctx, i) {
          final item = rawItems[i];
          return GestureDetector(
            onTap: () => onItemTapped(item),
            onLongPress: () => onItemLongPressed(item),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(item['poster'] ?? '', fit: BoxFit.cover),
            ),
          );
        },
      ),
    );
  }
}
