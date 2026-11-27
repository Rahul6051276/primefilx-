import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/app_settings_service.dart';

class CatalogCollectionScreen extends StatefulWidget {
  final bool isTv;
  final void Function(Map<String, dynamic> item) onItemTap;

  const CatalogCollectionScreen({
    super.key,
    required this.isTv,
    required this.onItemTap,
  });

  @override
  State<CatalogCollectionScreen> createState() => _CatalogCollectionScreenState();
}

class _CatalogCollectionScreenState extends State<CatalogCollectionScreen> {
  static const Color _bgDark = Color(0xFF0B1118);
  static const Color _cardDark = Color(0xFF15202B);
  static const Color _primeBlue = Color(0xFF00A8E1);

  final List _items = [];
  final Set _seenIds = {};
  final ScrollController _scrollController = ScrollController();

  String _selectedFilter = 'popular';
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _nextPageBatch = 6;
  String _errorText = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial200Plus();
  }

  @override
  void didUpdateWidget(covariant CatalogCollectionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isTv != widget.isTv) {
      _loadInitial200Plus();
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 500 &&
        !_isLoading &&
        !_isLoadingMore) {
      _loadMoreBatch();
    }
  }

  String _todayIso() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  bool _isBlockedSerial(String title) {
    final t = title.toLowerCase();
    const blocked = [
      'c.i.d.',
      'cid',
      'lapataganj',
      'naagin',
      'nagin',
      'bhabiji',
      'balika vadhu',
      'kapil sharma',
      'roadies',
      'splitsvilla',
      'bigg boss',
      'khatron ke khiladi',
      'taarak mehta',
      'tmkoc',
      'anupamaa',
      'yeh rishta',
      'ye rishta',
      'yrkkh',
      'kundali bhagya',
      'kumkum bhagya',
      'bhagya lakshmi',
      'jhanak',
      'ghkkpm',
      'ghum hai',
      'udaariyaan',
      'parineetii',
      'imlie',
      'pandya store',
      'saath nibhaana',
      'diya aur baati',
      'kasautii',
      'ishqbaaaz',
      'qubool hai',
      'jamai raja',
      'pavitra rishta',
      'radhakrishn',
      'mahabharat',
      'ramayan',
      'crime patrol',
      'savdhaan india',
      'adaalat',
      'f.i.r.',
      'tenali rama',
      'baalveer',
      'aladdin',
      'watch what happens',
      'tonight show',
      'late show',
      'daily show',
      'good morning',
      'sasural',
      'suhaagan',
      'dharampatnii',
      'shravani',
      'koffee with karan',
      'indian idol',
      'sa re ga ma',
      'dance india dance',
      'super dancer',
      'kaun banega crorepati',
    ];
    return blocked.any((b) => t.contains(b));
  }

  Future _fetchDiscoverPage({
    required String apiKey,
    required String langFilter,
    required int page,
  }) async {
    final type = widget.isTv ? 'tv' : 'movie';
    final sortBy = _selectedFilter == 'popular'
        ? 'popularity.desc'
        : (widget.isTv ? 'first_air_date.desc' : 'primary_release_date.desc');

    final today = _todayIso();
    final dateFilter = _selectedFilter == 'latest'
        ? (widget.isTv
            ? '&first_air_date.lte=$today&vote_count.gte=2'
            : '&primary_release_date.lte=$today&vote_count.gte=2')
        : '';

    // 10766=Soap, 10767=Talk, 10764=Reality, 10763=News
    final tvCleanFilter =
        widget.isTv ? '&without_genres=10766,10767,10764,10763' : '';

    final uri = Uri.parse(
      'https://api.themoviedb.org/3/discover/$type'
      '?api_key=$apiKey'
      '&with_original_language=$langFilter'
      '&sort_by=$sortBy'
      '$dateFilter'
      '$tvCleanFilter'
      '&page=$page',
    );

    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return [];
      final decoded = jsonDecode(res.body);
      final results = decoded['results'];
      if (results is! List) return [];

      final List parsed = [];
      for (final raw in results) {
        if (raw is! Map) continue;
        final id = int.tryParse((raw['id'] ?? '').toString()) ?? 0;
        final posterPath = (raw['poster_path'] ?? '').toString();
        if (id <= 0 || posterPath.isEmpty) continue;

        final title = (raw['title'] ?? raw['name'] ?? 'Untitled').toString();
        if (widget.isTv && _isBlockedSerial(title)) continue;

        final genreIds = raw['genre_ids'];
        if (widget.isTv && genreIds is List) {
          if (genreIds.contains(10766) ||
              genreIds.contains(10767) ||
              genreIds.contains(10764) ||
              genreIds.contains(10763)) {
            continue;
          }
        }

        final releaseDate =
            (raw['release_date'] ?? raw['first_air_date'] ?? '').toString();
        final year = releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';
        final ratingVal = (raw['vote_average'] is num)
            ? (raw['vote_average'] as num).toStringAsFixed(1)
            : '7.5';
        final backdropPath = (raw['backdrop_path'] ?? '').toString();
        final origLang = (raw['original_language'] ?? '').toString();

        String regionTag = 'Hollywood';
        if (origLang == 'hi') {
          regionTag = widget.isTv ? 'Hindi' : 'Bollywood';
        } else if (['te', 'ta', 'ml', 'kn'].contains(origLang)) {
          regionTag = 'South';
        }

        parsed.add(<String, dynamic>{
          'id': id,
          'tmdb_id': id,
          'title': title,
          'poster': 'https://image.tmdb.org/t/p/w500$posterPath',
          'poster_path': posterPath,
          'backdrop': backdropPath.isNotEmpty
              ? 'https://image.tmdb.org/t/p/w1280$backdropPath'
              : 'https://image.tmdb.org/t/p/w500$posterPath',
          'backdrop_path': backdropPath,
          'rating': ratingVal,
          'year': year,
          'overview': (raw['overview'] ?? '').toString(),
          'isTv': widget.isTv,
          'regionTag': regionTag,
        });
      }
      return parsed;
    } catch (_) {
      return [];
    }
  }

  Future _loadInitial200Plus() async {
    setState(() {
      _isLoading = true;
      _errorText = '';
      _items.clear();
      _seenIds.clear();
      _nextPageBatch = 6;
    });

    final apiKey = await AppSettingsService.getTmdbApiKey();
    if (apiKey.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = 'Settings mein TMDB API Key dalein.';
      });
      return;
    }

    final List futures = [];
    for (int page = 1; page <= 5; page++) {
      futures.add(_fetchDiscoverPage(apiKey: apiKey, langFilter: 'hi', page: page));
      futures.add(_fetchDiscoverPage(apiKey: apiKey, langFilter: 'en', page: page));
      futures.add(_fetchDiscoverPage(
          apiKey: apiKey, langFilter: 'te|ta|ml|kn', page: page));
    }

    final batches = await Future.wait(futures.cast());
    if (!mounted) return;

    final List combined = [];
    int maxLen = 0;
    for (final b in batches) {
      if (b is List && b.length > maxLen) maxLen = b.length;
    }
    for (int i = 0; i < maxLen; i++) {
      for (final b in batches) {
        if (b is List && i < b.length) {
          final item = b[i];
          final id = item['id'];
          if (_seenIds.add(id)) {
            combined.add(item);
          }
        }
      }
    }

    setState(() {
      _items.addAll(combined);
      _isLoading = false;
      if (_items.isEmpty) {
        _errorText =
            'Collection load nahi ho paya. Internet ya TMDB key check karein.';
      }
    });
  }

  Future _loadMoreBatch() async {
    if (_nextPageBatch > 18) return;
    setState(() => _isLoadingMore = true);

    final apiKey = await AppSettingsService.getTmdbApiKey();
    if (apiKey.trim().isEmpty) {
      if (mounted) setState(() => _isLoadingMore = false);
      return;
    }

    final page = _nextPageBatch++;
    final batches = await Future.wait([
      _fetchDiscoverPage(apiKey: apiKey, langFilter: 'hi', page: page),
      _fetchDiscoverPage(apiKey: apiKey, langFilter: 'en', page: page),
      _fetchDiscoverPage(apiKey: apiKey, langFilter: 'te|ta|ml|kn', page: page),
    ]);

    if (!mounted) return;
    final List added = [];
    for (final b in batches) {
      if (b is List) {
        for (final item in b) {
          final id = item['id'];
          if (_seenIds.add(id)) {
            added.add(item);
          }
        }
      }
    }

    setState(() {
      _items.addAll(added);
      _isLoadingMore = false;
    });
  }

  Widget _buildFilterChip(String label, String filterValue) {
    final selected = _selectedFilter == filterValue;
    return GestureDetector(
      onTap: () {
        if (_selectedFilter == filterValue) return;
        setState(() => _selectedFilter = filterValue);
        _loadInitial200Plus();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _primeBlue : _cardDark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _primeBlue : Colors.white24,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final heading = widget.isTv ? 'All Web Series' : 'All Movies';
    final subHeading = widget.isTv
        ? 'Hindi • English • South (${_items.length}+ Series)'
        : 'Bollywood • Hollywood • South (${_items.length}+ Movies)';

    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: _bgDark,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              heading,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              subHeading,
              style: const TextStyle(
                color: _primeBlue,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                _buildFilterChip('Popular', 'popular'),
                const SizedBox(width: 8),
                _buildFilterChip('Latest', 'latest'),
              ],
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: _primeBlue),
                  SizedBox(height: 12),
                  Text(
                    'Loading 200+ Hindi, Hollywood & South collection...',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            )
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _errorText,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primeBlue,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _loadInitial200Plus,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.62,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _items.length + (_isLoadingMore ? 3 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _items.length) {
                      return Container(
                        decoration: BoxDecoration(
                          color: _cardDark,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _primeBlue,
                            ),
                          ),
                        ),
                      );
                    }

                    final item = Map<String, dynamic>.from(_items[index]);
                    return GestureDetector(
                      onTap: () => widget.onItemTap(item),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    item['poster'] ?? '',
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: _cardDark,
                                      child: const Icon(
                                        Icons.movie_outlined,
                                        color: Colors.white38,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 6,
                                  left: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.78),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(
                                        color: _primeBlue.withOpacity(0.7),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Text(
                                      item['regionTag'] ?? '',
                                      style: const TextStyle(
                                        color: _primeBlue,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            item['title'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
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