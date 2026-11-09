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
  String currentStatus = 'Connecting to servers...';
  List<String> debugLogs = [];

  // Memory Cache taaki ek baar load hone ke baad turant chale
  static final Map<String, List<dynamic>> _vodCache = {};
  static final Map<String, List<dynamic>> _seriesCache = {};

  final Map<String, String> _iptvHeaders = {
    'User-Agent': 'IPTVSmartersPro/1.0.0 (Linux; Android 12)',
    'Accept': '*/*',
    'Connection': 'keep-alive',
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

  Future<List<Map<String, dynamic>>> _searchXtreamStreams() async {
    List<Map<String, dynamic>> xtreamResults = [];

    final title = widget.item['title'] ?? widget.item['name'] ?? '';
    final tmdbId = widget.item['tmdb_id']?.toString() ?? widget.item['id']?.toString();
    final cleanQuery = _cleanTitle(title);
    final bool isTv = widget.season != null || widget.item['isTv'] == true;

    for (var p in widget.providers) {
      if (p is! Map) continue;
      final bool isXtream = p['type'] == 'xtream' || p['xc_host'] != null;
      if (!isXtream) continue;

      final host = (p['xc_host'] ?? p['server'] ?? p['url'])?.toString().replaceAll(RegExp(r'/+$'), '');
      final user = (p['xc_username'] ?? p['username'])?.toString();
      final pass = (p['xc_password'] ?? p['password'])?.toString();
      final serverName = (p['name'] ?? 'Xtream Server').toString();

      if (host == null || user == null || pass == null || host.isEmpty) {
        debugLogs.add('$serverName: Host/User/Pass missing in JSON');
        continue;
      }

      if (mounted) {
        setState(() => currentStatus = 'Connecting: $serverName...');
      }

      try {
        if (!isTv) {
          // === MOVIE STREAM SEARCH ===
          List<dynamic>? vodList = _vodCache[host];

          if (vodList == null) {
            final uri = Uri.parse('$host/player_api.php').replace(queryParameters: {
              'username': user,
              'password': pass,
              'action': 'get_vod_streams',
            });

            debugLogs.add('$serverName: Fetching VOD list...');
            final res = await http.get(uri, headers: _iptvHeaders).timeout(const Duration(seconds: 30));

            if (res.statusCode == 200) {
              final decoded = jsonDecode(res.body);
              if (decoded is List) {
                vodList = decoded;
                _vodCache[host] = vodList;
                debugLogs.add('$serverName: ${vodList.length} movies loaded!');
              } else if (decoded is Map && decoded['user_info']?['auth'] == 0) {
                debugLogs.add('$serverName: ❌ Auth Failed (Wrong user/password/expired)');
              } else {
                debugLogs.add('$serverName: Server returned invalid format');
              }
            } else {
              debugLogs.add('$serverName: HTTP Error ${res.statusCode}');
            }
          }

          if (vodList != null && vodList.isNotEmpty) {
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
              final bool isHindi = vodName.toLowerCase().contains('hindi') || serverName.toLowerCase().contains('hindi');

              debugLogs.add('✅ Found on $serverName: $vodName');
              xtreamResults.add({
                'title': '$title (${widget.item['year'] ?? ''})',
                'server': serverName,
                'url': streamUrl,
                'isHindi': isHindi,
                'isXtream': true,
              });
            } else {
              debugLogs.add('$serverName: Movie "$title" not in list');
            }
          }
        } else {
          // === WEB SERIES STREAM SEARCH ===
          final seasonNum = widget.season ?? 1;
          final episodeNum = widget.episode ?? 1;

          List<dynamic>? seriesList = _seriesCache[host];
          if (seriesList == null) {
            final uri = Uri.parse('$host/player_api.php').replace(queryParameters: {
              'username': user,
              'password': pass,
              'action': 'get_series',
            });

            final res = await http.get(uri, headers: _iptvHeaders).timeout(const Duration(seconds: 30));
            if (res.statusCode == 200) {
              final decoded = jsonDecode(res.body);
              if (decoded is List) {
                seriesList = decoded;
                _seriesCache[host] = seriesList;
              }
            }
          }

          if (seriesList != null && seriesList.isNotEmpty) {
            final matchedSeries = seriesList.firstWhere(
              (s) => _isTitleMatch(s['name']?.toString() ?? '', cleanQuery),
              orElse: () => null,
            );

            if (matchedSeries != null) {
              final seriesId = matchedSeries['series_id'];
              final infoUri = Uri.parse('$host/player_api.php').replace(queryParameters: {
                'username': user,
                'password': pass,
                'action': 'get_series_info',
                'series_id': seriesId.toString(),
              });

              final infoRes = await http.get(infoUri, headers: _iptvHeaders).timeout(const Duration(seconds: 20));
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

                    xtreamResults.add({
                      'title': '$title (S$seasonNum E$episodeNum)',
                      'server': serverName,
                      'url': streamUrl,
                      'isHindi': serverName.toLowerCase().contains('hindi'),
                      'isXtream': true,
                    });
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        debugLogs.add('$serverName error: ${e.toString().split('\n').first}');
      }
    }

    return xtreamResults;
  }

  Future<void> _fetchAllStreams() async {
    final xtreamList = await _searchXtreamStreams();

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
        if (decoded is List) current = decoded;
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

      if (current.length > 15) current = current.sublist(0, 15);
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
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.season != null
                      ? '${widget.item['title']} - S${widget.season} E${widget.episode}'
                      : widget.item['title'] ?? 'Select Server',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline, color: Colors.white38, size: 20),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: const Color(0xFF16181F),
                      title: const Text('Server Diagnostics', style: TextStyle(color: Colors.white, fontSize: 14)),
                      content: SingleChildScrollView(
                        child: Text(
                          debugLogs.join('\n\n'),
                          style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (loading)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF0072D2)),
                    const SizedBox(height: 12),
                    Text(currentStatus, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            )
          else if (streams.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No active streams found on servers.', style: TextStyle(color: Colors.white54)),
                    const SizedBox(height: 10),
                    Text(
                      debugLogs.take(3).join('\n'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 10),
                    ),
                  ],
                ),
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
                        color: isXtream ? const Color(0xFF0072D2) : Colors.white10,
                        width: isXtream ? 1.5 : 1.0,
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
                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
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
                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black),
                                      ),
                                    ),
                                  Expanded(
                                    child: Text(
                                      s['title'] ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
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
