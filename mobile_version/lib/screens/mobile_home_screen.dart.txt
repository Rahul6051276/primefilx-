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

// TV REMOTE D-PAD FOCUSABLE
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
          duration: const Duration(milliseconds: 150),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius ?? BorderRadius.circular(10),
              border: Border.all(color: _isFocused ? widget.focusColor : Colors.transparent, width: _isFocused ? 2.5 : 0),
              boxShadow: _isFocused ? [BoxShadow(color: widget.focusColor.withOpacity(0.6), blurRadius: 10, spreadRadius: 2)] : null,
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
  XtreamAccount({required this.name, required this.host, required this.username, required this.password});
}

class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key});
  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  var activeProviders = [], continueWatchingList = [];
  var heroBanners = [], bollywoodLatest = [], hollywoodHindiDubbed = [], hindiWebSeries = [], englishWebSeries = [], southMovies = [];
  final List<XtreamAccount> _xtreamAccounts = [];
  final PageController _bannerController = PageController();
  int _currentBannerIndex = 0;
  Timer? _carouselTimer;
  bool isLoading = true;

  final Map<String, String> _iptvHeaders = {'User-Agent': 'IPTVSmartersPro/1.0.0 (Linux; Android 12)', 'Accept': '*/*'};

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
        _bannerController.animateToPage(next, duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
      }
    });
  }

  Future<void> _loadCachedDataInstantly() async {
    try {
      final p = await SharedPreferences.getInstance();
      final b = p.getString('c_bolly'), s = p.getString('c_south'), h = p.getString('c_holly'), hi = p.getString('c_hitv'), en = p.getString('c_entv');
      if (b != null) { bollywoodLatest = jsonDecode(b); heroBanners = bollywoodLatest.take(6).toList(); _startCarouselTimer(heroBanners.length); }
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
    try {
      final res = await http.get(Uri.parse("$kGistPermanentRawUrl?t=${DateTime.now().millisecondsSinceEpoch}")).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        activeProviders = d['active_providers'] ?? [];
        _parseXtream(d);
      }
    } catch (_) {}

    if (activeProviders.isEmpty) activeProviders = [{'name': 'Render Cloud', 'url': 'https://vidsrc.me'}];

    bool isClean(dynamic m) {
      final g = (m['genre_ids'] as List?) ?? [];
      final lang = m['original_language']?.toString().toLowerCase() ?? '';
      if (g.contains(16) || lang == 'ja' || g.contains(10766) || g.contains(10764) || g.contains(10762) || g.contains(10763)) return false;
      return true;
    }

    try {
      final f = await Future.wait([
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=hi&primary_release_date.gte=2024-01-01&sort_by=popularity.desc&without_genres=16')).timeout(const Duration(seconds: 6)),
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=te|ta|ml|kn&primary_release_date.gte=2024-01-01&sort_by=popularity.desc&without_genres=16')).timeout(const Duration(seconds: 6)),
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_original_language=en&primary_release_date.gte=2024-01-01&sort_by=popularity.desc&without_genres=16')).timeout(const Duration(seconds: 6)),
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_networks=1024|213|3919|2893|2892|3671&with_original_language=hi&without_genres=16,10762,10764,10766,10767,10763&vote_count.gte=10&sort_by=popularity.desc')).timeout(const Duration(seconds: 6)),
        http.get(Uri.parse('${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_networks=213|1024|49|2739|2552&without_genres=16,10762,10764,10766,10767,10763&vote_count.gte=20&sort_by=popularity.desc')).timeout(const Duration(seconds: 6)),
      ]);

      void saveRes(http.Response r, Function(List) setFn, String key, {bool isTv = false}) {
        if (r.statusCode == 200) {
          final list = (jsonDecode(r.body)['results'] as List? ?? []).where(isClean).toList();
          if (list.isNotEmpty) { final parsed = CatalogService.parseResults(list, isTv: isTv); setFn(parsed); p.setString(key, jsonEncode(parsed)); }
        }
      }

      saveRes(f[0], (l) { bollywoodLatest = l; heroBanners = l.take(6).toList(); _startCarouselTimer(heroBanners.length); }, 'c_bolly');
      saveRes(f[1], (l) => southMovies = l, 'c_south');
      saveRes(f[2], (l) => hollywoodHindiDubbed = l, 'c_holly');
      saveRes(f[3], (l) => hindiWebSeries = l, 'c_hitv', isTv: true);
      saveRes(f[4], (l) => englishWebSeries = l, 'c_entv', isTv: true);
    } catch (_) {}

    if (mounted) setState(() => isLoading = false);
  }

  void _parseXtream(dynamic data) {
    _xtreamAccounts.clear();
    if (data is! Map) return;
    final provs = data['active_providers'];
    if (provs is List) {
      for (var p in provs) {
        if (p is Map && (p['type'] == 'xtream' || p['xc_host'] != null)) {
          final host = (p['xc_host'] ?? p['server'] ?? p['url'])?.toString().replaceAll(RegExp(r'/+$'), '');
          final user = (p['xc_username'] ?? p['username'])?.toString(), pass = (p['xc_password'] ?? p['password'])?.toString();
          if (host != null && user != null && pass != null && host.isNotEmpty) {
            _xtreamAccounts.add(XtreamAccount(name: (p['name'] ?? 'Xtream Server').toString(), host: host, username: user, password: pass));
          }
        }
      }
    }
  }

  void _onItemTapped(dynamic item) {
    bool isTv = item['isTv'] == true;
    if (isTv) {
      showModalBottomSheet(
        context: context, isScrollControlled: true, backgroundColor: const Color(0xFF16181F),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => _MobileSeasonEpisodeSelectorSheet(item: Map<String, dynamic>.from(item), activeProviders: activeProviders, xtreamAccounts: _xtreamAccounts, iptvHeaders: _iptvHeaders),
      );
    } else {
      showModalBottomSheet(
        context: context, isScrollControlled: true, backgroundColor: const Color(0xFF16181F),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => MobileQualitySelectorSheet(item: Map<String, dynamic>.from(item), providers: activeProviders, onPlaySaved: _refreshCw),
      );
    }
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${item['title']} added to My List'), backgroundColor: const Color(0xFF0072D2)));
      }
    } catch (_) {}
  }

  void _openProvider(String name, Color color) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _MobileCategoryGridScreen(providerName: name, providerColor: color, onItemTapped: _onItemTapped, onItemLongPressed: _addToMyList)));
  }

  @override
  Widget build(BuildContext context) {
    final isTv = MediaQuery.of(context).size.width > 600;
    return Scaffold(
      backgroundColor: const Color(0xFF0F1014),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(isTv ? 70 : 60),
        child: AppBar(
          backgroundColor: const Color(0xFF0F1014), elevation: 0, automaticallyImplyLeading: false,
          title: Text('Primeflix', style: TextStyle(fontWeight: FontWeight.w900, fontSize: isTv ? 26 : 22, color: Colors.white)),
          actions: [
            TvFocusable(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
              borderRadius: BorderRadius.circular(20),
              child: Padding(padding: const EdgeInsets.all(8.0), child: Icon(Icons.search_rounded, color: Colors.white, size: isTv ? 30 : 26)),
            ),
          ],
        ),
      ),
      body: isLoading && bollywoodLatest.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0072D2)))
          : RefreshIndicator(
              color: const Color(0xFF0072D2), backgroundColor: const Color(0xFF16181F), onRefresh: _fetchAllDataLightningFast,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCarousel(isTv),
                    const SizedBox(height: 16),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('Streaming', style: TextStyle(color: Colors.white, fontSize: isTv ? 20 : 16, fontWeight: FontWeight.bold))),
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
        backgroundColor: const Color(0xFF0F1014), type: BottomNavigationBarType.fixed, selectedItemColor: const Color(0xFF0072D2), unselectedItemColor: Colors.white54,
        currentIndex: 0,
        onTap: (i) { if (i == 1) Navigator.push(context, MaterialPageRoute(builder: (_) => const MyListScreen())); },
        items: const [BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'), BottomNavigationBarItem(icon: Icon(Icons.bookmark_added_rounded), label: 'My List')],
      ),
    );
  }

  Widget _buildCarousel(bool isTv) {
    if (heroBanners.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: isTv ? 320 : 220,
      child: PageView.builder(
        controller: _bannerController, onPageChanged: (i) => setState(() => _currentBannerIndex = i), itemCount: heroBanners.length,
        itemBuilder: (ctx, i) {
          final item = heroBanners[i];
          return TvFocusable(
            onTap: () => _onItemTapped(item), onLongPress: () => _addToMyList(item), borderRadius: BorderRadius.circular(14),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), image: DecorationImage(image: NetworkImage(item['backdrop'] ?? ''), fit: BoxFit.cover)),
              child: Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: LinearGradient(colors: [Colors.transparent, Colors.black.withOpacity(0.85)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                padding: const EdgeInsets.all(16), alignment: Alignment.bottomCenter,
                child: Text(item['title'] ?? '', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: isTv ? 24 : 20, fontWeight: FontWeight.w900)),
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
        scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 14), itemCount: list.length,
        itemBuilder: (ctx, i) {
          final p = list[i]; final name = p['name'] as String, color = p['color'] as Color;
          return TvFocusable(
            onTap: () => _openProvider(name, color), focusColor: color, borderRadius: BorderRadius.circular(10),
            child: Container(
              width: isTv ? 150 : 120, margin: const EdgeInsets.only(right: 10), alignment: Alignment.center,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 3))]),
              child: Text(name.toUpperCase(), textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: isTv ? 13 : 11)),
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
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(title, style: TextStyle(color: Colors.white, fontSize: isTv ? 19 : 16, fontWeight: FontWeight.bold))),
        SizedBox(
          height: isTv ? 210 : 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: items.length,
            itemBuilder: (ctx, i) {
              final item = items[i];
              return TvFocusable(
                onTap: () => _onItemTapped(item), onLongPress: () => _addToMyList(item), borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: isTv ? 140 : 110, margin: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(item['poster'] ?? '', fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => Container(color: Colors.grey[850], child: const Icon(Icons.broken_image, color: Colors.white24))),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(item['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: isTv ? 13 : 12)),
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

// SEASON & EPISODE SELECTOR
class _MobileSeasonEpisodeSelectorSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  final List activeProviders, xtreamAccounts;
  final Map<String, String> iptvHeaders;
  const _MobileSeasonEpisodeSelectorSheet({required this.item, required this.activeProviders, required this.xtreamAccounts, required this.iptvHeaders});
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
    _loadSeries();
  }

  Future<void> _loadSeries() async {
    final clean = (widget.item['title'] ?? '').toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (var acc in widget.xtreamAccounts) {
      try {
        final res = await http.get(Uri.parse('${acc.host}/player_api.php?username=${acc.username}&password=${acc.password}&action=get_series'), headers: widget.iptvHeaders).timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final list = jsonDecode(res.body) as List;
          final target = list.firstWhere((s) {
            final n = (s['name'] ?? '').toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
            return n.contains(clean) || clean.contains(n);
          }, orElse: () => null);

          if (target != null) {
            final info = await http.get(Uri.parse('${acc.host}/player_api.php?username=${acc.username}&password=${acc.password}&action=get_series_info&series_id=${target['series_id']}'), headers: widget.iptvHeaders).timeout(const Duration(seconds: 15));
            if (info.statusCode == 200) {
              final epData = jsonDecode(info.body)['episodes'];
              if (epData is Map && epData.isNotEmpty) {
                epData.forEach((k, v) { if (v is List) seasonsMap[k.toString()] = v; });
                if (seasonsMap.isNotEmpty) { selectedSeason = seasonsMap.keys.first; break; }
              }
            }
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() { isLoading = false; if (seasonsMap.isEmpty) errorMessage = 'Web series Xtream IPTV par nahi mili!'; });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16), height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(color: Color(0xFF16181F), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(widget.item['title'] ?? 'Select Episode', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
              if (seasonsMap.isNotEmpty)
                DropdownButton<String>(
                  value: selectedSeason, dropdownColor: const Color(0xFF1F222E), style: const TextStyle(color: Color(0xFF0072D2), fontWeight: FontWeight.bold), underline: const SizedBox(),
                  items: seasonsMap.keys.map((s) => DropdownMenuItem(value: s, child: Text('Season $s'))).toList(),
                  onChanged: (v) { if (v != null) setState(() => selectedSeason = v); },
                ),
            ],
          ),
          const Divider(color: Colors.white24),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0072D2)))
                : errorMessage != null
                    ? Center(child: Text(errorMessage!, style: const TextStyle(color: Colors.white60)))
                    : ListView.builder(
                        itemCount: seasonsMap[selectedSeason]?.length ?? 0,
                        itemBuilder: (ctx, i) {
                          final ep = seasonsMap[selectedSeason]![i]; final epNum = ep['episode_num'] ?? (i + 1);
                          return TvFocusable(
                            onTap: () {
                              Navigator.pop(context);
                              showModalBottomSheet(
                                context: context, isScrollControlled: true, backgroundColor: const Color(0xFF16181F),
                                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                                builder: (_) => MobileQualitySelectorSheet(item: widget.item, season: int.tryParse(selectedSeason ?? '1') ?? 1, episode: int.tryParse(epNum.toString()) ?? 1, providers: widget.activeProviders, onPlaySaved: () {}),
                              );
                            },
                            child: ListTile(
                              leading: Container(width: 38, height: 38, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFF0072D2).withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: Text('$epNum', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                              title: Text(ep['title'] ?? 'Episode $epNum', style: const TextStyle(color: Colors.white, fontSize: 14)),
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

// OTT PLATFORM CATALOG SCREEN (MOBILE 3, TV 6 COLUMNS)
class _MobileCategoryGridScreen extends StatefulWidget {
  final String providerName; final Color providerColor; final Function(dynamic) onItemTapped, onItemLongPressed;
  const _MobileCategoryGridScreen({required this.providerName, required this.providerColor, required this.onItemTapped, required this.onItemLongPressed});
  @override
  State<_MobileCategoryGridScreen> createState() => _MobileCategoryGridScreenState();
}

class _MobileCategoryGridScreenState extends State<_MobileCategoryGridScreen> {
  String selectedType = 'Movies'; bool isLoading = true; List<dynamic> items = [];
  final Map<String, List<dynamic>> _cache = {};

  @override
  void initState() { super.initState(); _loadCatalog(); }

  String _getIds(String n) {
    if (n.contains('Hotstar')) return '122|390|337|220|384';
    if (n.contains('Prime')) return '119|9';
    if (n.contains('ZEE5')) return '232';
    if (n.contains('SonyLIV')) return '237';
    return '8|175';
  }

  Future<void> _loadCatalog() async {
    if (_cache.containsKey(selectedType)) { setState(() { items = _cache[selectedType]!; isLoading = false; }); return; }
    setState(() => isLoading = true);
    final isTv = selectedType == 'Web Series'; final ep = isTv ? 'discover/tv' : 'discover/movie';
    final ids = _getIds(widget.providerName);
    List<dynamic> res = [];

    try {
      final reqs = await Future.wait([1, 2, 3, 4].map((page) => http.get(Uri.parse('${AppConfig.tmdbBase}/$ep?api_key=${AppConfig.tmdbKey}&watch_region=IN&with_watch_providers=$ids&sort_by=popularity.desc&without_genres=16,10762,10764,10766,10767,10763&page=$page')).timeout(const Duration(seconds: 6))));
      for (var r in reqs) {
        if (r.statusCode == 200) {
          final raw = jsonDecode(r.body)['results'] as List? ?? [];
          for (var m in raw) {
            final g = (m['genre_ids'] as List?) ?? [];
            if (g.contains(16) || m['original_language'] == 'ja' || g.contains(10766) || g.contains(10764)) continue;
            final p = m['poster_path'];
            if (p != null) {
              res.add({'tmdb_id': m['id'], 'title': isTv ? (m['name'] ?? m['original_name'] ?? '') : (m['title'] ?? m['original_title'] ?? ''), 'poster': 'https://image.tmdb.org/t/p/w500$p', 'backdrop': m['backdrop_path'] != null ? 'https://image.tmdb.org/t/p/w780${m['backdrop_path']}' : '', 'year': (isTv ? (m['first_air_date'] ?? '') : (m['release_date'] ?? '')).toString().split('-').first, 'rating': (m['vote_average'] ?? 0.0).toString(), 'isTv': isTv});
            }
          }
        }
      }
      if (res.length < 25 && widget.providerName.contains('Hotstar')) {
        final fb = isTv ? '${AppConfig.tmdbBase}/discover/tv?api_key=${AppConfig.tmdbKey}&with_networks=3919|2739&without_genres=16,10766&sort_by=popularity.desc&page=1' : '${AppConfig.tmdbBase}/discover/movie?api_key=${AppConfig.tmdbKey}&with_companies=2|420|3&without_genres=16&sort_by=popularity.desc&page=1';
        final fbR = await http.get(Uri.parse(fb)).timeout(const Duration(seconds: 6));
        if (fbR.statusCode == 200) {
          for (var m in (jsonDecode(fbR.body)['results'] as List? ?? [])) {
            final p = m['poster_path'];
            if (p != null) res.add({'tmdb_id': m['id'], 'title': isTv ? (m['name'] ?? '') : (m['title'] ?? ''), 'poster': 'https://image.tmdb.org/t/p/w500$p', 'backdrop': '', 'year': '', 'rating': (m['vote_average'] ?? 0.0).toString(), 'isTv': isTv});
          }
        }
      }
    } catch (_) {}

    if (mounted) setState(() { items = res; _cache[selectedType] = res; isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width; final int cols = w > 900 ? 6 : (w > 600 ? 4 : 3); final bool isTv = w > 600;
    return Scaffold(
      backgroundColor: const Color(0xFF0F1014),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1014), elevation: 0, iconTheme: const IconThemeData(color: Colors.white),
        title: Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: widget.providerColor, borderRadius: BorderRadius.circular(6)), child: Text(widget.providerName.toUpperCase(), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: isTv ? 13 : 11))),
          const SizedBox(width: 8), Text('(${items.length})', style: const TextStyle(color: Colors.white54, fontSize: 13)),
        ]),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12, top: 8, bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: const Color(0xFF1E2029), borderRadius: BorderRadius.circular(20), border: Border.all(color: widget.providerColor)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedType, dropdownColor: const Color(0xFF1E2029), icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                items: const [DropdownMenuItem(value: 'Movies', child: Text('Movies')), DropdownMenuItem(value: 'Web Series', child: Text('Web Series'))],
                onChanged: (v) { if (v != null && v != selectedType) { setState(() => selectedType = v); _loadCatalog(); } },
              ),
            ),
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: widget.providerColor))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, childAspectRatio: 0.62, crossAxisSpacing: 10, mainAxisSpacing: 12),
              itemCount: items.length,
              itemBuilder: (ctx, i) {
                final it = items[i];
                return TvFocusable(
                  onTap: () => widget.onItemTapped(it), onLongPress: () => widget.onItemLongPressed(it), focusColor: widget.providerColor, borderRadius: BorderRadius.circular(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(it['poster'] ?? '', fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => Container(color: Colors.grey[900], child: const Icon(Icons.broken_image, color: Colors.white24))),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(it['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: isTv ? 12 : 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
// END OF FILE