import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const Color _primeBlue = Color(0xFF00A8E1);
  static const Color _darkBg = Color(0xFF0F171E);
  static const Color _cardBg = Color(0xFF1A242F);

  bool _isLoading = true;
  int _connectedProviders = 0;

  List<dynamic> _bollywoodMovies = [];
  List<dynamic> _southMovies = [];
  List<dynamic> _hollywoodMovies = [];
  List<dynamic> _hindiWebSeries = [];
  List<dynamic> _netflixWebSeries = [];
  List<dynamic> _amazonWebSeries = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);

    final results = await Future.wait([
      TmdbService.getLatestBollywoodMovies(),
      TmdbService.getLatestSouthMovies(),
      TmdbService.getLatestHollywoodMovies(),
      TmdbService.getLatestHindiWebSeries(),
      TmdbService.getLatestNetflixWebSeries(),
      TmdbService.getLatestAmazonWebSeries(),
      StreamService.loadProviders(),
    ]);

    if (!mounted) return;
    setState(() {
      _bollywoodMovies = results[0];
      _southMovies = results[1];
      _hollywoodMovies = results[2];
      _hindiWebSeries = results[3];
      _netflixWebSeries = results[4];
      _amazonWebSeries = results[5];
      _connectedProviders = results[6].length;
      _isLoading = false;
    });
  }

  Future<void> _showGistUrlDialog() async {
    final currentUrl = await StreamService.getSavedGistUrl();
    if (!mounted) return;

    final controller = TextEditingController(text: currentUrl);
    final urlFocus = FocusNode();
    final saveFocus = FocusNode();
    final cancelFocus = FocusNode();
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            Future<void> handleSave() async {
              if (isSaving) return;
              setDialogState(() => isSaving = true);
              final count = await StreamService.saveAndConnectGistUrl(
                controller.text,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              setState(() => _connectedProviders = count);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor:
                      count > 0 ? Colors.green.shade700 : Colors.red.shade700,
                  content: Text(
                    count > 0
                        ? 'Connected! $count providers active.'
                        : 'Connection failed. Raw Gist URL check karein.',
                  ),
                ),
              );
            }

            return AlertDialog(
              backgroundColor: _cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: _primeBlue.withOpacity(0.5)),
              ),
              title: const Row(
                children: [
                  Icon(Icons.link, color: _primeBlue),
                  SizedBox(width: 8),
                  Text(
                    'Gist Raw URL Setup',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'URL type/paste karein, phir keyboard par ✓ ya Down dabakar Save & Connect karein:',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Focus(
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          saveFocus.requestFocus();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: controller,
                        focusNode: urlFocus,
                        autofocus: true,
                        maxLines: 1,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          saveFocus.requestFocus();
                        },
                        decoration: InputDecoration(
                          hintText:
                              'https://gist.githubusercontent.com/.../raw/...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: _darkBg,
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: _primeBlue,
                              width: 2.5,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  focusNode: cancelFocus,
                  style: ButtonStyle(
                    overlayColor: WidgetStateProperty.all(
                      _primeBlue.withOpacity(0.25),
                    ),
                    side: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.focused)) {
                        return const BorderSide(color: Colors.white, width: 2);
                      }
                      return BorderSide.none;
                    }),
                  ),
                  onPressed: isSaving ? null : () => Navigator.pop(ctx),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                ElevatedButton(
                  focusNode: saveFocus,
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.all(_primeBlue),
                    foregroundColor: WidgetStateProperty.all(Colors.white),
                    side: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.focused)) {
                        return const BorderSide(
                          color: Colors.white,
                          width: 3,
                        );
                      }
                      return BorderSide.none;
                    }),
                  ),
                  onPressed: isSaving ? null : handleSave,
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save & Connect',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );

    urlFocus.dispose();
    saveFocus.dispose();
    cancelFocus.dispose();
  }

  void _openSearchSheet() {
    final searchController = TextEditingController();
    List<dynamic> results = [];
    bool searching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _darkBg,
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
                        prefixIcon:
                            const Icon(Icons.search, color: Colors.white70),
                        suffixIcon: IconButton(
                          focusColor: _primeBlue.withOpacity(0.4),
                          icon: const Icon(Icons.arrow_forward,
                              color: _primeBlue),
                          onPressed: () => runSearch(searchController.text),
                        ),
                        filled: true,
                        fillColor: _cardBg,
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: _primeBlue, width: 2),
                        ),
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
                                color: _primeBlue,
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
                                    return _FocusablePosterCard(
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
      alignment: Alignment.bottomCenter,
      children: [
        backdrop.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: backdrop,
                height: 360,
                width: double.infinity,
                fit: BoxFit.cover,
              )
            : Container(height: 360, color: _cardBg),
        Container(
          height: 360,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black54,
                Colors.transparent,
                _darkBg,
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
                autofocus: true,
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(_primeBlue),
                  foregroundColor: WidgetStateProperty.all(Colors.white),
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  ),
                  side: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.focused)) {
                      return const BorderSide(color: Colors.white, width: 2.5);
                    }
                    return BorderSide.none;
                  }),
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
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

  Widget _buildSection(String title, List<dynamic> items) {
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
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 186,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, index) {
              final item = items[index];
              return SizedBox(
                width: 122,
                child: _FocusablePosterCard(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkBg,
      appBar: AppBar(
        backgroundColor: const Color(0xE60F171E),
        title: const Text(
          'PRIMEFLIX',
          style: TextStyle(
            color: _primeBlue,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.8,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            focusColor: _primeBlue.withOpacity(0.4),
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: _openSearchSheet,
          ),
          TextButton.icon(
            style: ButtonStyle(
              overlayColor: WidgetStateProperty.all(
                _primeBlue.withOpacity(0.3),
              ),
              side: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return const BorderSide(color: _primeBlue, width: 2);
                }
                return BorderSide.none;
              }),
            ),
            onPressed: _showGistUrlDialog,
            icon: Icon(
              Icons.link,
              color: _connectedProviders > 0 ? Colors.greenAccent : _primeBlue,
            ),
            label: Text(
              _connectedProviders > 0
                  ? 'Gist ($_connectedProviders)'
                  : 'Add Gist',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: _primeBlue),
            )
          : RefreshIndicator(
              color: _primeBlue,
              onRefresh: _initData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeroBanner(),
                    _buildSection('Latest Bollywood Movies', _bollywoodMovies),
                    _buildSection('Latest South Movies', _southMovies),
                    _buildSection('Latest Hollywood Movies', _hollywoodMovies),
                    _buildSection('Latest Hindi Web Series', _hindiWebSeries),
                    _buildSection(
                        'Latest Netflix Web Series', _netflixWebSeries),
                    _buildSection(
                        'Latest Amazon Prime Web Series', _amazonWebSeries),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }
}

class _FocusablePosterCard extends StatefulWidget {
  final dynamic item;
  final VoidCallback onTap;

  const _FocusablePosterCard({
    required this.item,
    required this.onTap,
  });

  @override
  State<_FocusablePosterCard> createState() => _FocusablePosterCardState();
}

class _FocusablePosterCardState extends State<_FocusablePosterCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final posterUrl = TmdbService.getPosterUrl(widget.item['poster_path']);

    return Focus(
      onFocusChange: (focused) {
        if (mounted) setState(() => _isFocused = focused);
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused ? const Color(0xFF00A8E1) : Colors.transparent,
              width: _isFocused ? 3 : 0,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: const Color(0xFF00A8E1).withOpacity(0.5),
                      blurRadius: 10,
                    ),
                  ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: posterUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: posterUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: const Color(0xFF1A242F),
                    ),
                  )
                : Container(
                    color: const Color(0xFF1A242F),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      (widget.item['title'] ?? widget.item['name'] ?? '')
                          .toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}