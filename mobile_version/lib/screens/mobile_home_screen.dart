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

  // Streaming platform click hone par screen open karna
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
                  matchedAccount = acc;
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

// ============================================================================
// OTT PLATFORM CATALOG SCREEN (NETFLIX, HOTSTAR, PRIME, ZEE5, SONYLIV)
// WITH MOVIES & WEB SERIES DROPDOWN FILTER (50+ TITLES PER PLATFORM)
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
  String selectedType = 'Movies'; // 'Movies' or 'Web Series'
  bool isLoading = true;
  List<dynamic> items = [];

  // Instant switching ke liye memory cache
  final Map<String, List<dynamic>> _catalogCache = {};

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  // TMDB Watch Provider IDs for India (IN)
  int _getProviderId(String name) {
    switch (name) {
      case 'Netflix':
        return 8;
      case 'JioHotstar':
        return 122;
      case 'Prime Video':
        return 119;
      case 'ZEE5':
        return 232;
      case 'SonyLIV':
        return 237;
      default:
        return 8;
    }
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

    final providerId = _getProviderId(widget.providerName);
    final bool isTv = (selectedType == 'Web Series');
    final String endpoint = isTv ? 'discover/tv' : 'discover/movie';

    List<dynamic> fetchedResults = [];

    try {
      // 50+ Titles ke liye 3 Pages (20 x 3 = 60 items) parallel me fetch karein
      final futures = [1, 2, 3].map((page) {
        final url = Uri.parse(
          '${AppConfig.tmdbBase}/$endpoint?api_key=${AppConfig.tmdbKey}&watch_region=IN&with_watch_providers=$providerId&sort_by=popularity.desc&page=$page',
        );
        return http.get(url).timeout(const Duration(seconds: 6));
      }).toList();

      final responses = await Future.wait(futures);

      for (var res in responses) {
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final rawList = data['results'] as List? ?? [];
          for (var m in rawList) {
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
          // DROPDOWN FILTER: MOVIES & WEB SERIES
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
                    return GestureDetector(
                      onTap: () => widget.onItemTapped(item),
                      onLongPress: () => widget.onItemLongPressed(item),
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
                                  // Rating Badge
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
