import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tmdb_service.dart';
import '../services/stream_service.dart';
import '../widgets/mobile_stream_modal.dart';
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

  Future _loadFastInitialData() async {
    if (mounted) setState(() => isLoading = false);

    await Future.wait([
      _fetchProviders(),
      _loadContinueWatching(),
      _fetchMainHomeContent(),
    ]);

    // Background fetch expanded to load 200+ rich catalogs per category
    _fetchMassiveProviderCatalogsInBackground();
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

  Future _fetchMainHomeContent() async {
    try {
      final responses = await Future.wait([
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=hi&sort_by=popularity.desc&vote_count.gte=5')).timeout(const Duration(seconds: 5)),
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_original_language=hi&without_genres=10766&sort_by=vote_count.desc&vote_count.gte=5')).timeout(const Duration(seconds: 5)),
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=en&sort_by=popularity.desc&vote_count.gte=50')).timeout(const Duration(seconds: 5)),
      ]);

      if (responses[0].statusCode == 200) {
        bollywoodLatest = _parseResults(jsonDecode(responses[0].body)['results']);
        if (bollywoodLatest.isNotEmpty) {
          heroBanners = bollywoodLatest.take(6).toList();
          _startCarouselTimer(heroBanners.length);
        }
      }

      if (responses[1].statusCode == 200) {
        final rawList = jsonDecode(responses[1].body)['results'] ?? [];
        hindiWebSeries = _parseResults(rawList, isTv: true)
            .where((item) => !isDailySoapTitle(item['title'] ?? ''))
            .toList();
      }

      if (responses[2].statusCode == 200) {
        hollywoodHindiDubbed = _parseResults(jsonDecode(responses[2].body)['results']);
      }
      
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _fetchMassiveProviderCatalogsInBackground() async {
    try {
      // Fetch multiple pages (1 to 5) concurrently to ensure 200+ items per category
      List<Future<http.Response>> netflixFutures = [];
      List<Future<http.Response>> primeFutures = [];
      List<Future<http.Response>> hotstarFutures = [];
      List<Future<http.Response>> regionalFutures = [];

      for (int p = 1; p <= 5; p++) {
        netflixFutures.add(http.get(Uri.parse('${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_original_language=en&sort_by=vote_count.desc&page=$p')));
        netflixFutures.add(http.get(Uri.parse('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=hi&sort_by=popularity.desc&page=$p')));

        primeFutures.add(http.get(Uri.parse('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=en&sort_by=popularity.desc&page=$p')));
        primeFutures.add(http.get(Uri.parse('${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_genres=10759&sort_by=vote_count.desc&page=$p')));

        hotstarFutures.add(http.get(Uri.parse('${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_original_language=hi&sort_by=popularity.desc&page=$p')));
        hotstarFutures.add(http.get(Uri.parse('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=hi&sort_by=vote_average.desc&page=$p')));

        regionalFutures.add(http.get(Uri.parse('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=te|ta|ml|kn&sort_by=popularity.desc&page=$p')));
        regionalFutures.add(http.get(Uri.parse('${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_genres=18&sort_by=vote_count.desc&page=$p')));
      }

      final nResponses = await Future.wait(netflixFutures);
      var nList = [];
      for (var r in nResponses) {
        if (r.statusCode == 200) {
          bool isTv = r.request?.url.toString().contains('/discover/tv') ?? false;
          nList.addAll(_parseResults(jsonDecode(r.body)['results'], isTv: isTv));
        }
      }

      final pResponses = await Future.wait(primeFutures);
      var pList = [];
      for (var r in pResponses) {
        if (r.statusCode == 200) {
          bool isTv = r.request?.url.toString().contains('/discover/tv') ?? false;
          pList.addAll(_parseResults(jsonDecode(r.body)['results'], isTv: isTv));
        }
      }

      final hResponses = await Future.wait(hotstarFutures);
      var hList = [];
      for (var r in hResponses) {
        if (r.statusCode == 200) {
          bool isTv = r.request?.url.toString().contains('/discover/tv') ?? false;
          hList.addAll(_parseResults(jsonDecode(r.body)['results'], isTv: isTv));
        }
      }

      final rResponses = await Future.wait(regionalFutures);
      var rList = [];
      for (var r in rResponses) {
        if (r.statusCode == 200) {
          bool isTv = r.request?.url.toString().contains('/discover/tv') ?? false;
          rList.addAll(_parseResults(jsonDecode(r.body)['results'], isTv: isTv));
        }
      }

      if (mounted) {
        setState(() {
          netflixCatalog = nList;
          primeCatalog = pList;
          hotstarCatalog = hList;
          zee5Catalog = rList;
          sonylivCatalog = rList;
        });
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
        'year': (m['release_date'] ?? m['first_air_date'] ?? currentYear).toString().split('-')[0],
        'rating': m['vote_average']?.toString() ?? '7.8',
        'backdrop': m['backdrop_path'] != null ? AppConfig.backdropBase + m['backdrop_path'] : AppConfig.imgBase + m['poster_path'],
        'poster': m['poster_path'] != null ? AppConfig.imgBase + m['poster_path'] : AppConfig.backdropBase + m['backdrop_path'],
        'isTv': isTv,
      });
    }
    return res;
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

  Future _addToMyList(dynamic item) async {
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
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${item['title']} is already in My List'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.grey[800],
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
      body: SingleChildScrollView(
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
        child: const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0072D2)),
        ),
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
                    width: 24,
                    height: 24,
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

  const _MobileSeasonEpisodeSelectorSheet({
    required this.item,
    required this.activeProviders,
  });

  @override
  State<_MobileSeasonEpisodeSelectorSheet> createState() => _MobileSeasonEpisodeSelectorSheetState();
}

class _MobileSeasonEpisodeSelectorSheetState extends State<_MobileSeasonEpisodeSelectorSheet> {
  int selectedSeason = 1;
  int selectedEpisode = 1;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      constraints: const BoxConstraints(maxHeight: 450),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.item['title'] ?? 'Web Series',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Select Season', style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 5,
              itemBuilder: (ctx, i) {
                int sNum = i + 1;
                bool isSelected = selectedSeason == sNum;
                return GestureDetector(
                  onTap: () => setState(() => selectedSeason = sNum),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF0072D2) : Colors.grey[850],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text('Season $sNum', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          const Text('Select Episode', style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: 10,
              itemBuilder: (ctx, i) {
                int eNum = i + 1;
                bool isSelected = selectedEpisode == eNum;
                return ListTile(
                  tileColor: isSelected ? const Color(0xFF0072D2).withOpacity(0.3) : Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  title: Text('Episode $eNum', style: const TextStyle(color: Colors.white)),
                  trailing: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF0072D2)),
                  onTap: () {
                    Navigator.pop(context);
                    var updatedItem = Map<String, dynamic>.from(widget.item);
                    updatedItem['title'] = "${widget.item['title']} - S${selectedSeason}E$eNum";

                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: const Color(0xFF16181F),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (modalCtx) {
                        return MobileQualitySelectorSheet(
                          item: updatedItem,
                          providers: widget.activeProviders,
                          onPlaySaved: () {},
                        );
                      },
                    );
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
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: const Color(0xFF16181F),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: rawItems.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0072D2)),
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
                  onLongPress: () => onItemLongPressed(item),
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
