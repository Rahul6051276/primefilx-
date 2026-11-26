import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tmdb_service.dart';
import '../services/catalog_service.dart';
import '../widgets/mobile_stream_modal.dart';
import 'search_screen.dart';
import 'my_list_screen.dart';

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
    this.scaleFactor = 1.05,
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
      onFocusChange: (f) => setState(() => _isFocused = f),
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
          duration: const Duration(milliseconds: 150),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius ?? BorderRadius.circular(10),
              border: Border.all(
                color: _isFocused ? widget.focusColor : Colors.transparent,
                width: _isFocused ? 2.5 : 0,
              ),
              boxShadow: _isFocused
                  ? [BoxShadow(color: widget.focusColor.withOpacity(0.6), blurRadius: 10, spreadRadius: 2)]
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
  final String name, host, username, password;
  List<dynamic>? cachedVod, cachedSeries;
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
  var activeProviders = [], continueWatchingList = [];
  var heroBanners = [],
      bollywoodLatest = [],
      hollywoodHindiDubbed = [],
      hindiWebSeries = [],
      englishWebSeries = [],
      southMovies = [];
  final List<XtreamAccount> _xtreamAccounts = [];
  final PageController _bannerController = PageController();
  int _currentBannerIndex = 0;
  Timer? _carouselTimer;
  bool isLoading = true;
  String _customGistUrl = '';

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

  void _startCarouselTimer(int total) {
    _carouselTimer?.cancel();
    if (total <= 1) return;
    _carouselTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_bannerController.hasClients) {
        int next = _currentBannerIndex + 1;
        if (next >= total) next = 0;
        _bannerController.animateToPage(
          next,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  String _formatRating(dynamic r) {
    if (r == null) return '';
    final d = double.tryParse(r.toString());
    if (d == null || d == 0.0) return '';
    return d.toStringAsFixed(1);
  }

  Future<void> _loadCachedDataInstantly() async {
    try {
      final p = await SharedPreferences.getInstance();
      _customGistUrl = (p.getString('custom_gist_url') ?? '').trim();
      final b = p.getString('c_bolly'),
          s = p.getString('c_south'),
          h = p.getString('c_holly'),
          hi = p.getString('c_hitv'),
          en = p.getString('c_entv');
      if (b != null) {
        bollywoodLatest = jsonDecode(b);
        heroBanners = bollywoodLatest.take(6).toList();
        _startCarouselTimer(heroBanners.length);
      }
      if (s != null) southMovies = jsonDecode(s);
      if (h != null) hollywoodHindiDubbed = jsonDecode(h);
      if (hi != null) hindiWebSeries = jsonDecode(hi);
      if (en != null) englishWebSeries = jsonDecode(en);
      final rawCw = p.getString('continue_watching_mobile');
      if (rawCw != null) continueWatchingList = jsonDecode(rawCw);
      if (bollywoodLatest.isNotEmpty && mounted) setState(() => isLoading = false);
    } catch (_) {}
  }

  Future<void> _fetchAllDataLightningFast() async {
    final p = await SharedPreferences.getInstance();
    _customGistUrl = (p.getString('custom_gist_url') ?? '').trim();
    final gistEndpoint = _customGistUrl.isNotEmpty ? _customGistUrl : AppConfig.gistUrl.trim();
    final apiKey = AppConfig.tmdbKey.trim();

    if (gistEndpoint.isNotEmpty) {
      try {
        final sep = gistEndpoint.contains('?') ? '&' : '?';
        final res = await http
            .get(Uri.parse('$gistEndpoint${sep}t=${DateTime.now().millisecondsSinceEpoch}'))
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final d = jsonDecode(res.body);
          if (d is Map) {
            activeProviders = d['active_providers'] ?? d['providers'] ?? [];
            _parseXtream(d);
          } else if (d is List) {
            activeProviders = d;
          }
          if (mounted) setState(() {});
        }
      } catch (_) {}
    }

    if (apiKey.isEmpty) {
      if (mounted) setState(() => isLoading = false);
      return;
    }

    bool isClean(dynamic m) {
      final g = (m['genre_ids'] as List?) ?? [];
      final lang = m['original_language']?.toString().toLowerCase() ?? '';
      if (g.contains(16) ||
          lang == 'ja' ||
          g.contains(10766) ||
          g.contains(10764) ||
          g.contains(10762) ||
          g.contains(10763)) {
        return false;
      }
      return true;
    }

    Future<void> fetchCat(String url, Function(List) setFn, String key, {bool isTv = false}) async {
      try {
        final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
        if (r.statusCode == 200) {
          final list = (jsonDecode(r.body)['results'] as List? ?? []).where(isClean).toList();
          if (list.isNotEmpty) {
            final parsed = CatalogService.parseResults(list, isTv: isTv);
            setFn(parsed);
            p.setString(key, jsonEncode(parsed));
          }
        }
      } catch (_) {}
    }

    await Future.wait([
      fetchCat(
        '${AppConfig.tmdbBase}/discover/movie?api_key=$apiKey&with_original_language=hi&primary_release_date.gte=2024-01-01&sort_by=popularity.desc&without_genres=16',
        (l) {
          bollywoodLatest = l;
          heroBanners = l.take(6).toList();
          _startCarouselTimer(heroBanners.length);
        },
        'c_bolly',
      ),
      fetchCat(
        '${AppConfig.tmdbBase}/discover/movie?api_key=$apiKey&with_original_language=te|ta|ml|kn&primary_release_date.gte=2024-01-01&sort_by=popularity.desc&without_genres=16',
        (l) => southMovies = l,
        'c_south',
      ),
      fetchCat(
        '${AppConfig.tmdbBase}/discover/movie?api_key=$apiKey&with_original_language=en&primary_release_date.gte=2024-01-01&sort_by=popularity.desc&without_genres=16',
        (l) => hollywoodHindiDubbed = l,
        'c_holly',
      ),
      fetchCat(
        '${AppConfig.tmdbBase}/discover/tv?api_key=$apiKey&with_networks=1024|213|3919|2893|2892|3671&with_original_language=hi&without_genres=16,10762,10764,10766,10767,10763&vote_count.gte=10&sort_by=popularity.desc',
        (l) => hindiWebSeries = l,
        'c_hitv',
        isTv: true,
      ),
      fetchCat(
        '${AppConfig.tmdbBase}/discover/tv?api_key=$apiKey&with_networks=213|1024|49|2739|2552&without_genres=16,10762,10764,10766,10767,10763&vote_count.gte=20&sort_by=popularity.desc',
        (l) => englishWebSeries = l,
        'c_entv',
        isTv: true,
      ),
    ]);

    if (mounted) setState(() => isLoading = false);
  }

  void _parseXtream(dynamic data) {
    _xtreamAccounts.clear();
    if (data is! Map) return;
    final provs = data['active_providers'] ?? data['providers'];
    if (provs is List) {
      for (var p in provs) {
        if (p is Map && (p['type'] == 'xtream' || p['xc_host'] != null)) {
          final host = (p['xc_host'] ?? p['server'] ?? p['url'])?.toString().replaceAll(RegExp(r'/+$'), '');
          final user = (p['xc_username'] ?? p['username'])?.toString();
          final pass = (p['xc_password'] ?? p['password'])?.toString();
          if (host != null && user != null && pass != null && host.isNotEmpty) {
            _xtreamAccounts.add(
              XtreamAccount(
                name: (p['name'] ?? 'Xtream Server').toString(),
                host: host,
                username: user,
                password: pass,
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _openGistSettingsDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final currentSaved = (prefs.getString('custom_gist_url') ?? '').trim();
    final initialValue = currentSaved.isNotEmpty ? currentSaved : AppConfig.gistUrl.trim();
    final controller = TextEditingController(text: initialValue);

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16181F),
        title: const Text(
          'Raw Gist URL Settings',
          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GitHub Gist Raw URL डालें और सेव करें:',
              style: TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'https://gist.githubusercontent.com/.../raw/...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF1E2029),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await prefs.remove('custom_gist_url');
              if (ctx.mounted) Navigator.pop(ctx);
              await _fetchAllDataLightningFast();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Default Gist URL restored')),
                );
              }
            },
            child: const Text('Reset', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0072D2),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                await prefs.setString('custom_gist_url', url);
              } else {
                await prefs.remove('custom_gist_url');
              }
              if (ctx.mounted) Navigator.pop(ctx);
              await _fetchAllDataLightningFast();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Gist connected (${activeProviders.length} servers loaded)'),
                    backgroundColor: const Color(0xFF0072D2),
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _onItemTapped(dynamic item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MobileMovieDetailSheet(
        item: Map<String, dynamic>.from(item),
        providers: activeProviders,
        onPlaySaved: _refreshCw,
      ),
    );
  }

  Future<void> _refreshCw() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final raw = p.getString('continue_watching_mobile');
      if (raw != null && mounted) setState(() => continueWatchingList = jsonDecode(raw));
    } catch (_) {}
  }

  Future<void> _addToMyList(dynamic item) async {
    try {
      final p = await SharedPreferences.getInstance();
      List list = jsonDecode(p.getString('my_list_mobile') ?? '[]');
      if (!list.any((e) => e['tmdb_id'].toString() == item['tmdb_id'].toString())) {
        list.add(item);
        await p.setString('my_list_mobile', jsonEncode(list));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${item['title']} added to My List'),
              backgroundColor: const Color(0xFF0072D2),
            ),
          );
        }
      }
    } catch (_) {}
  }

  void _openProvider(String name, Color color) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MobileCategoryGridScreen(
          providerName: name,
          providerColor: color,
          onItemTapped: _onItemTapped,
          onItemLongPressed: _addToMyList,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTv = MediaQuery.of(context).size.width > 600;
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
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: isTv ? 26 : 22, color: Colors.white),
          ),
          actions: [
            TvFocusable(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(Icons.search_rounded, color: Colors.white, size: isTv ? 30 : 26),
              ),
            ),
            TvFocusable(
              onTap: _openGistSettingsDialog,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(Icons.settings_rounded, color: Colors.white, size: isTv ? 28 : 24),
              ),
            ),
          ],
        ),
      ),
      body: isLoading && bollywoodLatest.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0072D2)))
          : RefreshIndicator(
              color: const Color(0xFF0072D2),
              backgroundColor: const Color(0xFF16181F),
              onRefresh: _fetchAllDataLightningFast,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCarousel(isTv),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Streaming',
                        style: TextStyle(color: Colors.white, fontSize: isTv ? 20 : 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildProviders(isTv),
                    const SizedBox(height: 16),
                    _buildRow('Latest Bollywood Releases', bollywoodLatest, isTv),
                    const SizedBox(height: 16),
                    _buildRow('Latest South Indian Movies', southMovies, isTv),
                    const SizedBox(height: 16),
                    _buildRow('Latest English Web Series', englishWebSeries, isTv),
                    const SizedBox(height: 16),
                    _buildRow('Latest Hollywood Movies', hollywoodHindiDubbed, isTv),
                    const SizedBox(height: 16),
                    _buildRow('Latest Hindi Web Series', hindiWebSeries, isTv),
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
        onTap: (i) {
          if (i == 1) Navigator.push(context, MaterialPageRoute(builder: (_) => const MyListScreen()));
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmark_added_rounded), label: 'My List'),
        ],
      ),
    );
  }

  Widget _buildCarousel(bool isTv) {
    if (heroBanners.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: isTv ? 320 : 220,
      child: PageView.builder(
        controller: _bannerController,
        onPageChanged: (i) => setState(() => _currentBannerIndex = i),
        itemCount: heroBanners.length,
        itemBuilder: (ctx, i) {
          final item = heroBanners[i];
          final imgUrl = (item['backdrop'] != null && item['backdrop'].toString().isNotEmpty)
              ? item['backdrop']
              : (item['poster'] ?? '');
          final ratingStr = _formatRating(item['rating']);

          return TvFocusable(
            onTap: () => _onItemTapped(item),
            onLongPress: () => _addToMyList(item),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                image: (imgUrl.isNotEmpty) ? DecorationImage(image: NetworkImage(imgUrl), fit: BoxFit.cover) : null,
                color: Colors.grey[900],
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        item['title'] ?? '',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: isTv ? 24 : 18, fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (ratingStr.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: Colors.amber, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                            const SizedBox(width: 3),
                            Text(
                              ratingStr,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProviders(bool isTv) {
    final list = [
      {'name': 'Netflix', 'color': const Color(0xFFE50914)},
      {'name': 'Disney+ Hotstar', 'color': const Color(0xFF0072D2)},
      {'name': 'Prime Video', 'color': const Color(0xFF00A8E1)},
      {'name': 'ZEE5', 'color': const Color(0xFF8C1159)},
      {'name': 'SonyLIV', 'color': const Color(0xFFFC4C02)},
    ];
    return SizedBox(
      height: isTv ? 65 : 55,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: list.length,
        itemBuilder: (ctx, i) {
          final p = list[i];
          final name = p['name'] as String, color = p['color'] as Color;
          return TvFocusable(
            onTap: () => _openProvider(name, color),
            focusColor: color,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: isTv ? 150 : 120,
              margin: const EdgeInsets.only(right: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 3))],
              ),
              child: Text(
                name.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: isTv ? 13 : 11),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRow(String title, List items, bool isTv) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            title,
            style: TextStyle(color: Colors.white, fontSize: isTv ? 19 : 16, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: isTv ? 235 : 195,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final item = items[i];
              final poster = (item['poster'] ?? '').toString();
              final ratingStr = _formatRating(item['rating']);
              return TvFocusable(
                onTap: () => _onItemTapped(item),
                onLongPress: () => _addToMyList(item),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: isTv ? 145 : 115,
                  margin: const EdgeInsets.only(right: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: poster.isNotEmpty
                                  ? Image.network(
                                      poster,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: Colors.grey[900],
                                        child: const Icon(Icons.movie, color: Colors.white30),
                                      ),
                                    )
                                  : Container(
                                      color: Colors.grey[900],
                                      child: const Icon(Icons.movie, color: Colors.white30),
                                    ),
                            ),
                            if (ratingStr.isNotEmpty)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.8),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.amber, width: 0.8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.star_rounded, color: Colors.amber, size: 12),
                                      const SizedBox(width: 2),
                                      Text(
                                        ratingStr,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item['title'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white70, fontSize: isTv ? 13 : 11.5),
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

class _MobileCategoryGridScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1014),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1014),
        title: Text(providerName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Text(
          '$providerName catalog coming soon',
          style: const TextStyle(color: Colors.white54),
        ),
      ),
    );
  }
}