import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/tmdb_service.dart';
import '../services/stream_service.dart';
import '../widgets/mobile_stream_modal.dart';

class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  bool _isLoading = true;
  int _connectedProviders = 0;

  List> _trendingMovies = [];
  List> _popularMovies = [];
  List> _topRatedMovies = [];
  List> _trendingTv = [];
  List> _popularTv = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);

    final results = await Future.wait([
      TmdbService.getTrendingMovies(),
      TmdbService.getPopularMovies(),
      TmdbService.getTopRatedMovies(),
      TmdbService.getTrendingTv(),
      TmdbService.getPopularTv(),
      StreamService.loadProviders(),
    ]);

    if (!mounted) return;
    setState(() {
      _trendingMovies = results[0] as List>;
      _popularMovies = results[1] as List>;
      _topRatedMovies = results[2] as List>;
      _trendingTv = results[3] as List>;
      _popularTv = results[4] as List>;
      _connectedProviders = (results[5] as List).length;
      _isLoading = false;
    });
  }

  Future<void> _showGistUrlDialog() async {
    final currentUrl = await StreamService.getSavedGistUrl();
    if (!mounted) return;

    final controller = TextEditingController(text: currentUrl);
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF181818),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: const Row(
                children: [
                  Icon(Icons.link, color: Color(0xFFE50914)),
                  SizedBox(width: 8),
                  Text(
                    'Gist Raw URL Setup',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Apna GitHub Gist Raw JSON URL yahan paste karein:',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'https://gist.githubusercontent.com/.../raw/...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF0E0E0E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(ctx),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE50914),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          setDialogState(() => isSaving = true);
                          final count = await StreamService.saveAndConnectGistUrl(
                            controller.text,
                          );
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          setState(() => _connectedProviders = count);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: count > 0
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                              content: Text(
                                count > 0
                                    ? 'Connected! $count providers active.'
                                    : 'Connection failed. Raw Gist URL check karein.',
                              ),
                            ),
                          );
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save & Connect'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openSearchSheet() {
    final searchController = TextEditingController();
    List> results = [];
    bool searching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101010),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> runSearch(String q) async {
              if (q.trim().isEmpty) return;
              setSheetState(() => searching = true);
              final data = await TmdbService.searchMulti(q);
              setSheetState(() {
                results = data;
                searching = false;
              });
            }

            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.85,
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
                        prefixIcon:
                            const Icon(Icons.search, color: Colors.white70),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_forward,
                              color: Color(0xFFE50914)),
                          onPressed: () => runSearch(searchController.text),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1E1E1E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: searching
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFFE50914),
                              ),
                            )
                          : results.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Search any Movie or Web Series',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                )
                              : GridView.builder(
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    childAspectRatio: 0.65,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                  ),
                                  itemCount: results.length,
                                  itemBuilder: (_, i) {
                                    final item = results[i];
                                    final poster = TmdbService.getPosterUrl(
                                      item['poster_path'],
                                    );
                                    return GestureDetector(
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        MobileStreamModal.show(context, item);
                                      },
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: poster.isNotEmpty
                                            ? CachedNetworkImage(
                                                imageUrl: poster,
                                                fit: BoxFit.cover,
                                              )
                                            : Container(
                                                color: Colors.grey.shade900,
                                                alignment: Alignment.center,
                                                padding:
                                                    const EdgeInsets.all(6),
                                                child: Text(
                                                  (item['title'] ??
                                                          item['name'] ??
                                                          '')
                                                      .toString(),
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                      ),
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
    if (_trendingMovies.isEmpty) return const SizedBox.shrink();
    final hero = _trendingMovies.first;
    final backdrop = TmdbService.getBackdropUrl(
      hero['backdrop_path'] ?? hero['poster_path'],
    );
    final title = (hero['title'] ?? hero['name'] ?? '').toString();

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        backdrop.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: backdrop,
                height: 420,
                width: double.infinity,
                fit: BoxFit.cover,
              )
            : Container(height: 420, color: Colors.black),
        Container(
          height: 420,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black54,
                Colors.transparent,
                Color(0xFF0A0A0A),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => MobileStreamModal.show(context, hero),
                icon: const Icon(Icons.play_arrow, size: 24),
                label: const Text(
                  'Watch Now',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, index) {
              final item = items[index];
              final posterUrl = TmdbService.getPosterUrl(item['poster_path']);
              return GestureDetector(
                onTap: () => MobileStreamModal.show(context, item),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: posterUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: posterUrl,
                          width: 120,
                          height: 180,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            width: 120,
                            color: Colors.grey.shade900,
                          ),
                        )
                      : Container(
                          width: 120,
                          color: Colors.grey.shade900,
                          alignment: Alignment.center,
                          child: const Icon(Icons.movie, color: Colors.white38),
                        ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'PRIMEFLIX',
          style: TextStyle(
            color: Color(0xFFE50914),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: _openSearchSheet,
          ),
          TextButton.icon(
            onPressed: _showGistUrlDialog,
            icon: Icon(
              Icons.link,
              color: _connectedProviders > 0
                  ? Colors.greenAccent
                  : const Color(0xFFE50914),
            ),
            label: Text(
              _connectedProviders > 0 ? 'Gist ($_connectedProviders)' : 'Add Gist',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFE50914)),
            )
          : RefreshIndicator(
              color: const Color(0xFFE50914),
              onRefresh: _initData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeroBanner(),
                    _buildSection('Trending Movies', _trendingMovies),
                    _buildSection('Trending Web Series', _trendingTv),
                    _buildSection('Popular Movies', _popularMovies),
                    _buildSection('Popular Web Series', _popularTv),
                    _buildSection('Top Rated Movies', _topRatedMovies),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }
}