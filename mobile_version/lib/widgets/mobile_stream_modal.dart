import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../internal_player.dart';
import '../services/tmdb_service.dart';

class MobileStreamModal extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback? onListChanged;

  const MobileStreamModal({
    super.key,
    required this.item,
    this.onListChanged,
  });

  static void show(
    BuildContext context,
    dynamic item, {
    VoidCallback? onListChanged,
  }) {
    final size = MediaQuery.of(context).size;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0C1219),
      constraints: BoxConstraints(
        maxWidth: size.width,
        maxHeight: size.height * 0.92,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => MobileStreamModal(
        item: Map<String, dynamic>.from(item as Map),
        onListChanged: onListChanged,
      ),
    );
  }

  @override
  State<MobileStreamModal> createState() => _MobileStreamModalState();
}

class _MobileStreamModalState extends State<MobileStreamModal> {
  static const Color _primeBlue = Color(0xFF00A8E1);
  static const Color _darkBg = Color(0xFF0C1219);
  static const Color _cardBg = Color(0xFF16202C);

  bool _showEpisodes = false;
  bool _loadingSeasons = false;
  bool _loadingEpisodes = false;
  bool _inMyList = false;

  List _seasons = [];
  List _episodes = [];
  int _selectedSeason = 1;

  @override
  void initState() {
    super.initState();
    _checkMyList();
  }

  bool get _isTv {
    if (widget.item['isTv'] == true) return true;
    final type = widget.item['media_type'];
    if (type == 'tv') return true;
    if (type == 'movie') return false;
    return widget.item['first_air_date'] != null;
  }

  int get _tmdbId =>
      ((widget.item['tmdb_id'] ?? widget.item['id']) as num?)?.toInt() ?? 0;

  String get _title =>
      (widget.item['title'] ?? widget.item['name'] ?? 'Untitled').toString();

  String get _overview =>
      (widget.item['overview'] ?? 'No description available.').toString();

  String get _year {
    final raw = (widget.item['year'] ??
            widget.item['release_date'] ??
            widget.item['first_air_date'] ??
            '')
        .toString();
    return raw.length >= 4 ? raw.substring(0, 4) : '';
  }

  String get _rating {
    final v = widget.item['rating'] ?? widget.item['vote_average'];
    if (v is num && v > 0) return v.toStringAsFixed(1);
    final parsed = double.tryParse(v?.toString() ?? '');
    if (parsed != null && parsed > 0) return parsed.toStringAsFixed(1);
    return 'HD';
  }

  Future<void> _checkMyList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('my_list_mobile') ?? '[]';
      final List list = jsonDecode(raw);
      final exists = list.any(
        (e) => ((e['tmdb_id'] ?? e['id'])?.toString() ?? '') == _tmdbId.toString(),
      );
      if (mounted) setState(() => _inMyList = exists);
    } catch (_) {}
  }

  Future<void> _toggleMyList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('my_list_mobile') ?? '[]';
      final List list = List.from(jsonDecode(raw));

      if (_inMyList) {
        list.removeWhere(
          (e) => ((e['tmdb_id'] ?? e['id'])?.toString() ?? '') == _tmdbId.toString(),
        );
      } else {
        list.insert(0, {
          'tmdb_id': _tmdbId,
          'id': _tmdbId,
          'title': _title,
          'overview': _overview,
          'poster_path': widget.item['poster_path'],
          'backdrop_path': widget.item['backdrop_path'],
          'poster': TmdbService.getPosterUrl(
            widget.item['poster_path'] ?? widget.item['poster'],
          ),
          'isTv': _isTv,
          'media_type': _isTv ? 'tv' : 'movie',
          'vote_average': _rating,
        });
      }

      await prefs.setString('my_list_mobile', jsonEncode(list));
      if (!mounted) return;
      setState(() => _inMyList = !_inMyList);
      widget.onListChanged?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _cardBg,
          content: Text(
            _inMyList ? '$_title My List mein add ho gaya' : '$_title My List se hat gaya',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (_) {}
  }

  void _openPlayer({int? season, int? episode}) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InternalPlayer(
          tmdbId: _tmdbId,
          title: _title,
          isTv: _isTv,
          season: season,
          episode: episode,
        ),
      ),
    );
  }

  Future<void> _onWatchNowPressed() async {
    if (!_isTv) {
      _openPlayer();
      return;
    }

    setState(() {
      _showEpisodes = true;
      _loadingSeasons = true;
    });

    final seasons = await TmdbService.getTvSeasons(_tmdbId);
    if (!mounted) return;

    if (seasons.isNotEmpty) {
      final firstSeason =
          (seasons.first['season_number'] as num?)?.toInt() ?? 1;
      setState(() {
        _seasons = seasons;
        _selectedSeason = firstSeason;
        _loadingSeasons = false;
      });
      await _loadEpisodes(firstSeason);
    } else {
      setState(() => _loadingSeasons = false);
    }
  }

  Future<void> _loadEpisodes(int seasonNumber) async {
    setState(() {
      _selectedSeason = seasonNumber;
      _loadingEpisodes = true;
      _episodes = [];
    });

    final eps = await TmdbService.getSeasonEpisodes(_tmdbId, seasonNumber);
    if (!mounted) return;
    setState(() {
      _episodes = eps;
      _loadingEpisodes = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final backdropUrl = TmdbService.getBackdropUrl(
      widget.item['backdrop_path'] ??
          widget.item['backdrop'] ??
          widget.item['poster_path'] ??
          widget.item['poster'],
    );

    return DraggableScrollableSheet(
      initialChildSize: _showEpisodes ? 0.88 : 0.72,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                    child: backdropUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: backdropUrl,
                            height: 215,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          )
                        : Container(height: 215, color: _cardBg),
                  ),
                  Container(
                    height: 215,
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, _darkBg],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: CircleAvatar(
                      backgroundColor: Colors.black54,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _primeBlue,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            _isTv ? 'WEB SERIES' : 'MOVIE',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (_year.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Text(_year, style: const TextStyle(color: Colors.white70)),
                        ],
                        const SizedBox(width: 10),
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(_rating, style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primeBlue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _onWatchNowPressed,
                              icon: const Icon(Icons.play_arrow, size: 24),
                              label: Text(
                                _isTv
                                    ? (_showEpisodes ? 'Episodes Below' : 'Watch Series')
                                    : 'Watch Now',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: _inMyList ? _primeBlue : Colors.white24,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: _toggleMyList,
                            icon: Icon(
                              _inMyList ? Icons.check : Icons.bookmark_add_outlined,
                              color: _inMyList ? _primeBlue : Colors.white,
                            ),
                            label: Text(_inMyList ? 'Saved' : 'My List'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _overview,
                      maxLines: _showEpisodes ? 2 : 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                    if (_showEpisodes && _isTv) ...[
                      const SizedBox(height: 16),
                      const Divider(color: Colors.white12),
                      if (_loadingSeasons)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: CircularProgressIndicator(color: _primeBlue),
                          ),
                        )
                      else ...[
                        Row(
                          children: [
                            const Text(
                              'Episodes',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            if (_seasons.isNotEmpty)
                              DropdownButton<int>(
                                value: _selectedSeason,
                                dropdownColor: _cardBg,
                                style: const TextStyle(color: Colors.white),
                                underline: const SizedBox(),
                                items: _seasons.map((s) {
                                  final numVal =
                                      (s['season_number'] as num?)?.toInt() ?? 1;
                                  return DropdownMenuItem<int>(
                                    value: numVal,
                                    child: Text('Season $numVal'),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) _loadEpisodes(val);
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_loadingEpisodes)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(
                              child: CircularProgressIndicator(color: _primeBlue),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _episodes.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, index) {
                              final ep = _episodes[index];
                              final epNum =
                                  (ep['episode_number'] as num?)?.toInt() ?? (index + 1);
                              final epName = (ep['name'] ?? 'Episode $epNum').toString();
                              final stillUrl = TmdbService.getPosterUrl(ep['still_path']);

                              return InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => _openPlayer(
                                  season: _selectedSeason,
                                  episode: epNum,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _cardBg,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: stillUrl.isNotEmpty
                                            ? CachedNetworkImage(
                                                imageUrl: stillUrl,
                                                width: 112,
                                                height: 64,
                                                fit: BoxFit.cover,
                                              )
                                            : Container(
                                                width: 112,
                                                height: 64,
                                                color: Colors.black54,
                                                child: const Icon(
                                                  Icons.play_circle_outline,
                                                  color: Colors.white54,
                                                ),
                                              ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '$epNum. $epName',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              (ep['overview'] ?? '').toString(),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 11.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.play_circle_fill,
                                        color: _primeBlue,
                                        size: 30,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}