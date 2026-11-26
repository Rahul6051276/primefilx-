import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../internal_player.dart';
import '../services/tmdb_service.dart';

class MobileStreamModal extends StatefulWidget {
  final Map item;

  const MobileStreamModal({super.key, required this.item});

  static void show(BuildContext context, dynamic item) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 600;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F171E),
      constraints: BoxConstraints(
        maxWidth: isWide ? size.width * 0.85 : size.width,
        maxHeight: size.height * (isWide ? 0.94 : 0.92),
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => MobileStreamModal(
        item: Map.from(item as Map),
      ),
    );
  }

  @override
  State<MobileStreamModal> createState() => _MobileStreamModalState();
}

class _MobileStreamModalState extends State<MobileStreamModal> {
  static const Color _primeBlue = Color(0xFF00A8E1);
  static const Color _darkBg = Color(0xFF0F171E);
  static const Color _cardBg = Color(0xFF1A242F);

  bool _showEpisodes = false;
  bool _loadingSeasons = false;
  bool _loadingEpisodes = false;

  List<dynamic> _seasons = [];
  List<dynamic> _episodes = [];
  int _selectedSeason = 1;

  bool get _isTv {
    final type = widget.item['media_type'];
    if (type == 'tv') return true;
    if (type == 'movie') return false;
    return widget.item['first_air_date'] != null;
  }

  int get _tmdbId => (widget.item['id'] as num?)?.toInt() ?? 0;

  String get _title =>
      (widget.item['title'] ?? widget.item['name'] ?? 'Untitled').toString();

  String get _overview =>
      (widget.item['overview'] ?? 'No description available.').toString();

  String get _year {
    final date = (widget.item['release_date'] ??
            widget.item['first_air_date'] ??
            '')
        .toString();
    return date.length >= 4 ? date.substring(0, 4) : '';
  }

  String get _rating {
    final v = widget.item['vote_average'];
    if (v is num && v > 0) return v.toStringAsFixed(1);
    return 'HD';
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
      setState(() {
        _loadingSeasons = false;
      });
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
    final isWide = MediaQuery.of(context).size.width > 600;
    final backdropHeight = isWide ? 160.0 : 210.0;
    final backdropUrl = TmdbService.getBackdropUrl(
      widget.item['backdrop_path'] ?? widget.item['poster_path'],
    );

    return DraggableScrollableSheet(
      initialChildSize: isWide ? 0.94 : (_showEpisodes ? 0.88 : 0.68),
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (ctx, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Backdrop
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    child: backdropUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: backdropUrl,
                            height: backdropHeight,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            height: backdropHeight,
                            color: _cardBg,
                          ),
                  ),
                  Container(
                    height: backdropHeight,
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, _darkBg],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: CircleAvatar(
                      backgroundColor: Colors.black54,
                      child: IconButton(
                        focusColor: _primeBlue.withOpacity(0.5),
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ],
              ),

              // Title, Meta & Watch Now
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
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _primeBlue,
                            borderRadius: BorderRadius.circular(4),
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
                        const SizedBox(width: 10),
                        if (_year.isNotEmpty)
                          Text(
                            _year,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        const SizedBox(width: 10),
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          _rating,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Watch Now Button (TV Remote Autofocus)
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        autofocus: true,
                        style: ButtonStyle(
                          backgroundColor:
                              WidgetStateProperty.all(_primeBlue),
                          foregroundColor:
                              WidgetStateProperty.all(Colors.white),
                          overlayColor: WidgetStateProperty.all(
                            Colors.white.withOpacity(0.2),
                          ),
                          side: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.focused)) {
                              return const BorderSide(
                                color: Colors.white,
                                width: 3,
                              );
                            }
                            return BorderSide.none;
                          }),
                          shape: WidgetStateProperty.all(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        onPressed: _onWatchNowPressed,
                        icon: const Icon(Icons.play_arrow, size: 26),
                        label: Text(
                          _isTv
                              ? (_showEpisodes
                                  ? 'Select Episode Below'
                                  : 'Watch Now (Episodes)')
                              : 'Watch Now',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    Text(
                      _overview,
                      maxLines: _showEpisodes ? 2 : 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),

                    // Web Series Seasons & Episodes
                    if (_showEpisodes && _isTv) ...[
                      const SizedBox(height: 14),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 8),
                      if (_loadingSeasons)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                              color: _primeBlue,
                            ),
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
                                      (s['season_number'] as num?)?.toInt() ??
                                          1;
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
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(
                                color: _primeBlue,
                              ),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _episodes.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, index) {
                              final ep = _episodes[index];
                              final epNum =
                                  (ep['episode_number'] as num?)?.toInt() ??
                                      (index + 1);
                              final epName =
                                  (ep['name'] ?? 'Episode $epNum').toString();
                              final stillUrl = TmdbService.getPosterUrl(
                                ep['still_path'],
                              );

                              return InkWell(
                                borderRadius: BorderRadius.circular(10),
                                focusColor: _primeBlue.withOpacity(0.4),
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
                                                width: 110,
                                                height: 64,
                                                fit: BoxFit.cover,
                                              )
                                            : Container(
                                                width: 110,
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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