import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/app_settings_service.dart';
import '../services/stream_service.dart';
import '../services/tmdb_service.dart';
import '../widgets/mobile_stream_modal.dart';
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

  List> _bollywoodMovies = [];
  List> _southMovies = [];
  List> _hollywoodMovies = [];
  List> _hindiWebSeries = [];
  List> _netflixWebSeries = [];
  List> _amazonWebSeries = [];

  final GlobalKey<State<MyListScreen>> _myListKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
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

    if (!mounted) return;
    setState(() {
      _hasTmdbKey = tmdbKey.isNotEmpty;
      _bollywoodMovies = results[0] as List>;
      _southMovies = results[1] as List>;
      _hollywoodMovies = results[2] as List>;
      _hindiWebSeries = results[3] as List>;
      _netflixWebSeries = results[4] as List>;
      _amazonWebSeries = results[5] as List>;
      _connectedProviders = (results[6] as List).length;
      _isLoading = false;
    });
  }

  void _openSearchSheet() {
    final searchController = TextEditingController();
    List> results = [];
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
            Future<void> runSearch(String q) async {
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
    final heroList = _bollywoodMovies.isNotEmpty
        ? _bollywoodMovies
        : (_hollywoodMovies.isNotEmpty ? _hollywoodMovies : _southMovies);
    if (heroList.isEmpty) return const SizedBox.shrink();

    final hero = heroList.first;
    final backdrop = TmdbService.getBackdropUrl(
      hero['backdrop_path'] ?? hero['poster_path'],
    );
    final title = (hero['title'] ?? hero['name'] ?? '').toString();

    return Stack(
      alignment: Alignment.bottomLeft,
      children: [
        backdrop.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: backdrop,
                height: 310,
                width: double.infinity,
                fit: BoxFit.cover,
              )
            : Container(height: 310, color: _cardBg),
        Container(
          height: 310,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black38,
                Colors.transparent,
                _darkBg,
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _primeBlue,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  'FEATURED',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primeBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => MobileStreamModal.show(context, hero),
                icon: const Icon(Icons.play_arrow, size: 22),
                label: const Text(
                  'Watch Now',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection(String title, List> items) {
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
                    onPressed: () => setState(() => _navIndex = 2),
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
        backgroundColor: _cardBg,
        selectedItemColor: _primeBlue,
        unselectedItemColor: Colors.white54,
        onTap: (idx) {
          setState(() => _navIndex = idx);
          if (idx == 1) {
            final state = _myListKey.currentState as dynamic;
            state?.loadMyList();
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmarks_rounded), label: 'My List'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}

class _MobilePosterCard extends StatelessWidget {
  final Map<String, dynamic> item;
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