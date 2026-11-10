import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tmdb_service.dart';
import '../services/catalog_service.dart';
import '../widgets/mobile_stream_modal.dart';

const String kGistPermanentRawUrl = "https://gist.githubusercontent.com/Rahul6051276/5b0a18b2cf69a99d1d3e06629fcbc70a/raw";

// TV REMOTE D-PAD FOCUS & LONG-PRESS WIDGET
class _TvSearchFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final Color focusColor;

  const _TvSearchFocusable({
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.focusColor = const Color(0xFF0072D2),
  });

  @override
  State<_TvSearchFocusable> createState() => _TvSearchFocusableState();
}

class _TvSearchFocusableState extends State<_TvSearchFocusable> {
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
        onLongPress: widget.onLongPress, // TV Remote Hold & Mobile Long Press Support
        borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
        child: AnimatedScale(
          scale: _isFocused ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
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

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;

  bool _isLoading = false;
  List<dynamic> _searchResults = [];
  List<dynamic> _activeProviders = [];

  @override
  void initState() {
    super.initState();
    _loadProviders();

    _searchFocusNode.addListener(() {
      if (_searchFocusNode.hasFocus) {
        SystemChannels.textInput.invokeMethod('TextInput.show');
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadProviders() async {
    try {
      final res = await http.get(Uri.parse("$kGistPermanentRawUrl?t=${DateTime.now().millisecondsSinceEpoch}")).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        _activeProviders = d['active_providers'] ?? [];
      }
    } catch (_) {}

    if (_activeProviders.isEmpty) {
      _activeProviders = [{'name': 'Render Cloud', 'url': 'https://vidsrc.me'}];
    }
  }

  // ADD TO MY LIST ON LONG PRESS (MOBILE + TV REMOTE)
  Future<void> _addToMyList(dynamic item) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List list = jsonDecode(prefs.getString('my_list_mobile') ?? '[]');

      bool exists = list.any((e) => e['tmdb_id'].toString() == item['tmdb_id'].toString());
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
              content: Text('${item['title']} already in My List'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.grey[800],
            ),
          );
        }
      }
    } catch (_) {}
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isLoading = true);
    final encodedQuery = Uri.encodeComponent(query);

    try {
      final url = Uri.parse(
        '${AppConfig.tmdbBase}/search/multi?api_key=${AppConfig.tmdbKey}&query=$encodedQuery&include_adult=false&page=1',
      );

      final res = await http.get(url).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rawList = data['results'] as List? ?? [];
        List<dynamic> parsed = [];

        for (var m in rawList) {
          final mediaType = m['media_type'];
          if (mediaType != 'movie' && mediaType != 'tv') continue;
          final bool isTv = (mediaType == 'tv');

          final genres = (m['genre_ids'] as List?) ?? [];
          if (genres.contains(16) || m['original_language'] == 'ja') continue;

          final posterPath = m['poster_path'];
          if (posterPath != null && posterPath.toString().isNotEmpty) {
            parsed.add({
              'tmdb_id': m['id'],
              'title': isTv ? (m['name'] ?? m['original_name'] ?? '') : (m['title'] ?? m['original_title'] ?? ''),
              'poster': 'https://image.tmdb.org/t/p/w500$posterPath',
              'backdrop': m['backdrop_path'] != null ? 'https://image.tmdb.org/t/p/w780${m['backdrop_path']}' : '',
              'year': (isTv ? (m['first_air_date'] ?? '') : (m['release_date'] ?? '')).toString().split('-').first,
              'rating': (m['vote_average'] ?? 0.0).toString(),
              'isTv': isTv,
            });
          }
        }

        if (mounted) {
          setState(() {
            _searchResults = parsed;
            _isLoading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openStreamSelector(dynamic item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16181F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => MobileQualitySelectorSheet(
        item: Map<String, dynamic>.from(item),
        providers: _activeProviders,
        onPlaySaved: () {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isTv = width > 600;
    final int cols = width > 900 ? 6 : (width > 600 ? 4 : 3);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1014),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1014),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Container(
          height: isTv ? 50 : 42,
          decoration: BoxDecoration(
            color: const Color(0xFF1E2029),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _searchFocusNode.hasFocus ? const Color(0xFF0072D2) : Colors.white24,
              width: 1.5,
            ),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            autofocus: true,
            style: TextStyle(color: Colors.white, fontSize: isTv ? 16 : 14),
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) => _performSearch(v.trim()),
            onChanged: _onSearchChanged,
            onTap: () {
              SystemChannels.textInput.invokeMethod('TextInput.show');
            },
            decoration: InputDecoration(
              hintText: 'Search movies, web series...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF0072D2), size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0072D2)))
          : _searchResults.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.movie_filter_outlined, color: Colors.white24, size: isTv ? 80 : 50),
                      const SizedBox(height: 12),
                      Text(
                        _searchController.text.isEmpty
                            ? 'Type to search (Hold poster to save in My List)'
                            : 'No movies or series found',
                        style: const TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    childAspectRatio: 0.62,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _searchResults.length,
                  itemBuilder: (ctx, i) {
                    final item = _searchResults[i];
                    final pUrl = (item['poster'] ?? '').toString();

                    return _TvSearchFocusable(
                      onTap: () => _openStreamSelector(item),
                      onLongPress: () => _addToMyList(item), // LONG PRESS: ADDS TO MY LIST (MOBILE & TV)
                      focusColor: const Color(0xFF0072D2),
                      borderRadius: BorderRadius.circular(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: (pUrl.isNotEmpty)
                                  ? Image.network(
                                      pUrl,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      cacheWidth: 300,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: Colors.grey[900],
                                        child: const Icon(Icons.broken_image, color: Colors.white24),
                                      ),
                                    )
                                  : Container(color: Colors.grey[900], child: const Icon(Icons.movie, color: Colors.white24)),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item['title'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isTv ? 12 : 11,
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
// END OF FILE
