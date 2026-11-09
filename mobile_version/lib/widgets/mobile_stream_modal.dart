import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../services/stream_service.dart';
import '../internal_player.dart';

class MobileQualitySelectorSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  final int? season;
  final int? episode;
  final List<dynamic> providers;
  final VoidCallback onPlaySaved;

  const MobileQualitySelectorSheet({
    super.key,
    required this.item,
    this.season,
    this.episode,
    required this.providers,
    required this.onPlaySaved,
  });

  @override
  State<MobileQualitySelectorSheet> createState() => _MobileQualitySelectorSheetState();
}

class _MobileQualitySelectorSheetState extends State<MobileQualitySelectorSheet> {
  var streams = [];
  bool loading = true;

  // Caching taaki har baar poori VOD list dubara download na karni pade
  static final Map<String, List<dynamic>> _vodCache = {};
  static final Map<String, List<dynamic>> _seriesCache = {};

  final Map<String, String> _iptvHeaders = {
    'User-Agent': 'IPTVSmartersPro/1.0.0 (Linux; Android 12)',
    'Accept': '*/*',
  };

  @override
  void initState() {
    super.initState();
    _fetchAllStreams();
  }

  String _cleanTitle(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'\[.*?\]|\(.*?\)|fhd|1080p|720p|4k|hindi|dubbed|telugu|tamil|eng'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .trim();
  }

  bool _isTitleMatch(String vodName, String cleanQuery) {
    final cleanVod = _cleanTitle(vodName);
    if (cleanVod.isEmpty || cleanQuery.isEmpty) return false;
    return cleanVod.contains(cleanQuery) || cleanQuery.contains(cleanVod);
  }

  // Teeno Xtream Servers se parallel link search karna
  Future<List<Map<String, dynamic>>> _searchXtreamStreams() async {
    List<Map<String, dynamic>> xtreamResults = [];

    final title = widget.item['title'] ?? widget.item['name'] ?? '';
    final tmdbId = widget.item['tmdb_id']?.toString() ?? widget.item['id']?.toString();
    final cleanQuery = _cleanTitle(title);
    final bool isTv = widget.season != null || widget.item['isTv'] == true;

    List<Future<void>> searchTasks = [];

    for (var p in widget.providers) {
      if (p is! Map) continue;
      final bool isXtream = p['type'] == 'xtream' || p['xc_host'] != null;
      if (!isXtream) continue;

      final host = (p['xc_host'] ?? p['server'] ?? p['url'])?.toString().replaceAll(RegExp(r'/+$'), '');
      final user = (p['xc_username'] ?? p['username'])?.toString();
      final pass = (p['xc_password'] ?? p['password'])?.toString();
      final serverName = (p['name'] ?? 'Xtream Server').toString();

      if (host == null || user == null || pass == null || host.isEmpty) continue;

      searchTasks.add(() async {
        try {
          if (!isTv) {
            // === MOVIE STREAM SEARCH ===
            List<dynamic>? vodList = _vodCache[host];
            if (vodList == null) {
              final url = Uri.parse('$host/player_api.php?username=$user&password=$pass&action=get_vod_streams');
              final res = await http.get(url, headers: _iptvHeaders).timeout(const Duration(seconds: 15));
              if (res.statusCode == 200) {
                vodList = jsonDecode(res.body);
                _vodCache[host] = vodList!;
              }
            }

            if (vodList != null && vodList is List) {
              dynamic matchedVod;

              // 1. TMDB ID Match
              if (tmdbId != null && tmdbId.isNotEmpty) {
                matchedVod = vodList.firstWhere(
                  (v) => v['tmdb_id']?.toString() == tmdbId,
                  orElse: () => null,
                );
              }

              // 2. Title Match
              if (matchedVod == null) {
                matchedVod = vodList.firstWhere(
                  (v) => _isTitleMatch(v['name']?.toString() ?? '', cleanQuery),
                  orElse: () => null,
                );
              }

              if (matchedVod != null) {
                final streamId = matchedVod['stream_id'];
                final ext = matchedVod['container_extension'] ?? 'mp4';
                final streamUrl = '$host/movie/$user/$pass/$streamId.$ext';
                final vodName = matchedVod['name']?.toString() ?? title;
                final bool isHindi = vodName.toLowerCase().contains('hindi') ||
                    serverName.toLowerCase().contains('hindi');

                xtreamResults.add({
                  'title': '$title (${widget.item['year'] ?? ''})',
                  'server': serverName,
                  'url': streamUrl,
                  'isHindi': isHindi,
                  'isXtream': true,
                });
              }
            }
          } else {
            // === WEB SERIES STREAM SEARCH ===
            final seasonNum = widget.season ?? 1;
            final episodeNum = widget.episode ?? 1;

            List<dynamic>? seriesList = _seriesCache[host];
            if (seriesList == null) {
              final url = Uri.parse('$host/player_api.php?username=$user&password=$pass&action=get_series');
              final res = await http.get(url, headers: _iptvHeaders).timeout(const Duration(seconds: 15));
              if (res.statusCode == 200) {
                seriesList = jsonDecode(res.body);
                _seriesCache[host] = seriesList!;
              }
            }

            if (seriesList != null && seriesList is List) {
              final matchedSeries = seriesList.firstWhere(
                (s) => _isTitleMatch(s['name']?.toString() ?? '', cleanQuery),
                orElse: () => null,
              );

              if (matchedSeries != null) {
                final seriesId = matchedSeries['series_id'];
                final infoUrl = Uri.parse('$host/player_api.php?username=$user&password=$pass&action=get_series_info&series_id=$seriesId');
                final infoRes = await http.get(infoUrl, headers: _iptvHeaders).timeout(const Duration(seconds: 15));

                if (infoRes.statusCode == 200) {
                  final infoData = jsonDecode(infoRes.body);
                  final episodes = infoData['episodes'];
                  if (episodes != null && episodes is Map && episodes[seasonNum.toString()] != null) {
                    final seasonEps = episodes[seasonNum.toString()] as List;
                    final matchedEp = seasonEps.firstWhere(
                      (e) => e['episode_num'].toString() == episodeNum.toString(),
                      orElse: () => null,
                    );

                    if (matchedEp != null) {
                      final epId = matchedEp['id'];
                      final ext = matchedEp['container_extension'] ?? 'mp4';
                      final streamUrl = '$host/series/$user/$pass/$epId.$ext';
                      final bool isHindi = serverName.toLowerCase().contains('hindi');

                      xtreamResults.add({
                        'title': '$title (S$seasonNum E$episodeNum)',
                        'server': serverName,
                        'url': streamUrl,
                        'isHindi': isHindi,
                        'isXtream': true,
                      });
                    }
                  }
                }
              }
            }
          }
        } catch (_) {}
      }());
    }

    // Saare Xtream servers ko ek sath (parallel) query karein
    await Future.wait(searchTasks);
    return xtreamResults;
  }

  Future<void> _fetchAllStreams() async {
    // 1. Xtream IPTV Servers se search
    final xtreamList = await _searchXtreamStreams();

    // 2. Standard Cloud Providers se fallback
    List standardList = [];
    try {
      final results = await MobileStreamService.getDirectStreams(
        item: widget.item,
        providers: widget.providers,
        season: widget.season,
        episode: widget.episode,
      );
      if (results is List) standardList = results;
    } catch (_) {}

    if (mounted) {
      setState(() {
        // Xtream servers ko sabse upar dikhayein
        streams = [...xtreamList, ...standardList];
        loading = false;
      });
    }
  }

  Future<void> _saveContinueWatching() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString('continue_watching_mobile');
      var current = [];
      if (raw != null && raw.isNotEmpty) {
        var decoded = jsonDecode(raw);
        if (decoded is List) {
          current = decoded;
        }
      }

      current.removeWhere((c) => c['tmdb_id'].toString() == widget.item['tmdb_id'].toString());

      current.insert(0, {
        'tmdb_id': widget.item['tmdb_id'],
        'title': widget.item['title'] ?? 'Untitled',
        'poster': widget.item['poster'] ?? '',
        'backdrop': widget.item['backdrop'] ?? widget.item['poster'] ?? '',
        'year': widget.item['year'] ?? DateTime.now().year.toString(),
        'rating': widget.item['rating'] ?? '8.0',
        'isTv': widget.item['isTv'] ?? false,
      });

      if (current.length > 15) {
        current = current.sublist(0, 15);
      }
      await prefs.setString('continue_watching_mobile', jsonEncode(current));
      widget.onPlaySaved();
    } catch (_) {}
  }

  void _playStream(String url, bool isVlc) async {
    await _saveContinueWatching();
    if (!mounted) return;
    Navigator.of(context).pop();

    final cleanUrl = url.trim();

    if (isVlc) {
      final intent = AndroidIntent(
        action: 'action_view',
        data: cleanUrl,
        type: 'video/*',
      );
      await intent.launch();
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InternalPlayerScreen(
            videoUrl: cleanUrl,
            title: widget.season != null
                ? '${widget.item['title']} (S${widget.season} E${widget.episode})'
                : widget.item['title'],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      height: MediaQuery.of(context).size.height * 0.55,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.season != null
                ? '${widget.item['title']} - S${widget.season} E${widget.episode}'
                : widget.item['title'] ?? 'Select Server',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (loading)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF0072D2)),
                    SizedBox(height: 12),
                    Text('Searching Xtream IPTV Servers...', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
            )
          else if (streams.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No active streams found on servers.', style: TextStyle(color: Colors.white54)),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: streams.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final s = streams[i];
                  final isHindi = s['isHindi'] == true;
                  final isXtream = s['isXtream'] == true;

                  return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2029),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isXtream
                            ? const Color(0xFF0072D2)
                            : (isHindi ? const Color(0xFF10B981) : Colors.white10),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (isXtream)
                                    Container(
                                      margin: const EdgeInsets.only(right: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0072D2),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: const Text(
                                        'IPTV',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  if (isHindi)
                                    Container(
                                      margin: const EdgeInsets.only(right: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: const Text(
                                        'HINDI',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: Text(
                                      s['title'] ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                s['server'] ?? '',
                                style: TextStyle(
                                  color: isXtream ? const Color(0xFF38BDF8) : Colors.white54,
                                  fontSize: 11,
                                  fontWeight: isXtream ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.play_circle_fill, color: Color(0xFF0072D2), size: 28),
                          onPressed: () => _playStream(s['url'], false),
                        ),
                        IconButton(
                          icon: const Icon(Icons.open_in_new, color: Colors.amber, size: 24),
                          onPressed: () => _playStream(s['url'], true),
                        ),
                      ],
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
