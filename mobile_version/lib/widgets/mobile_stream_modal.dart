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
  List<dynamic> streams = [];
  bool loading = true;
  String currentStatus = 'Finding best streaming servers...';

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
    _fetchBothStreamsInParallel();
  }

  // Audio Hindi check
  bool _isHindiAudioStream(String name) {
    final lower = name.toLowerCase();
    return lower.contains('hindi') ||
        lower.contains('dubbed') ||
        lower.contains('dual audio') ||
        lower.contains('dual-audio') ||
        lower.contains('multi audio') ||
        lower.contains('multi-audio') ||
        lower.contains('[hin]') ||
        lower.contains('(hin)') ||
        lower.contains('hin-') ||
        lower.contains('hin ');
  }

  String _cleanTitle(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'\[.*?\]|\(.*?\)|fhd|1080p|720p|4k|hindi|dubbed|telugu|tamil|eng'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .trim();
  }

  bool _isStrictMatch(String vodName, String cleanQuery, String? targetYear) {
    final cleanVod = _cleanTitle(vodName);
    if (cleanVod.isEmpty || cleanQuery.isEmpty) return false;
    if (!cleanVod.contains(cleanQuery)) return false;

    if (targetYear != null && targetYear.length == 4) {
      if (vodName.contains(targetYear)) return true;
    }

    return cleanVod == cleanQuery || cleanVod.startsWith(cleanQuery);
  }

  // 1. XTREAM IPTV STREAMS SEARCH
  Future<List<Map<String, dynamic>>> _searchXtreamStreams() async {
    List<Map<String, dynamic>> xtreamResults = [];

    final title = widget.item['title'] ?? widget.item['name'] ?? '';
    final tmdbId = widget.item['tmdb_id']?.toString() ?? widget.item['id']?.toString();
    final year = widget.item['year']?.toString();
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

      if (host == null || user == null || pass == null || host.isEmpty) continue;

      try {
        if (!isTv) {
          // MOVIE SEARCH
          List<dynamic>? vodList = _vodCache[host];

          if (vodList == null) {
            final uri = Uri.parse('$host/player_api.php').replace(queryParameters: {
              'username': user,
              'password': pass,
              'action': 'get_vod_streams',
            });

            final res = await http.get(uri, headers: _iptvHeaders).timeout(const Duration(seconds: 25));
            if (res.statusCode == 200) {
              final decoded = jsonDecode(res.body);
              if (decoded is List) {
                vodList = decoded;
                _vodCache[host] = vodList;
              }
            }
          }

          if (vodList != null && vodList.isNotEmpty) {
            List<dynamic> allMatches = [];

            for (var v in vodList) {
              final vName = v['name']?.toString() ?? '';
              if (tmdbId != null && v['tmdb_id']?.toString() == tmdbId) {
                allMatches.add(v);
              } else if (_isStrictMatch(vName, cleanQuery, year)) {
                allMatches.add(v);
              }
            }

            if (allMatches.isNotEmpty) {
              allMatches.sort((a, b) {
                final aName = a['name']?.toString() ?? '';
                final bName = b['name']?.toString() ?? '';
                final aHindi = _isHindiAudioStream(aName);
                final bHindi = _isHindiAudioStream(bName);
                if (aHindi && !bHindi) return -1;
                if (!aHindi && bHindi) return 1;
                return 0;
              });

              final topMatches = allMatches.take(2).toList();
              for (var matchedVod in topMatches) {
                final streamId = matchedVod['stream_id'];
                final ext = matchedVod['container_extension'] ?? 'mp4';
                final streamUrl = '$host/movie/$user/$pass/$streamId.$ext';
                final realVodName = matchedVod['name']?.toString() ?? title;
                final bool isHindi = _isHindiAudioStream(realVodName) || serverName.toLowerCase().contains('hindi');

                xtreamResults.add({
                  'title': realVodName,
                  'server': serverName,
                  'url': streamUrl,
                  'isHindi': isHindi,
                  'isXtream': true,
                });
              }
            }
          }
        } else {
          // SERIES SEARCH
          final seasonNum = widget.season ?? 1;
          final episodeNum = widget.episode ?? 1;

          List<dynamic>? seriesList = _seriesCache[host];
          if (seriesList == null) {
            final uri = Uri.parse('$host/player_api.php').replace(queryParameters: {
              'username': user,
              'password': pass,
              'action': 'get_series',
            });

            final res = await http.get(uri, headers: _iptvHeaders).timeout(const Duration(seconds: 25));
            if (res.statusCode == 200) {
              final decoded = jsonDecode(res.body);
              if (decoded is List) {
                seriesList = decoded;
                _seriesCache[host] = seriesList;
              }
            }
          }

          if (seriesList != null && seriesList.isNotEmpty) {
            List<dynamic> matchedSeriesList = [];

            for (var s in seriesList) {
              final sName = s['name']?.toString() ?? '';
              if (_cleanTitle(sName).contains(cleanQuery)) {
                matchedSeriesList.add(s);
              }
            }

            matchedSeriesList.sort((a, b) {
              final aHindi = _isHindiAudioStream(a['name']?.toString() ?? '');
              final bHindi = _isHindiAudioStream(b['name']?.toString() ?? '');
              if (aHindi && !bHindi) return -1;
              if (!aHindi && bHindi) return 1;
              return 0;
            });

            if (matchedSeriesList.isNotEmpty) {
              final matchedSeries = matchedSeriesList.first;
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
                    final isHindi = _isHindiAudioStream(matchedSeries['name']?.toString() ?? '') ||
                        serverName.toLowerCase().contains('hindi');

                    xtreamResults.add({
                      'title': '${matchedSeries['name']} - S$seasonNum E$episodeNum',
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
    }

    return xtreamResults;
  }

  // 2. PARALLEL EXECUTION (XTREAM + CASTLE TV / RENDER CLOUD SIMULTANEOUSLY)
  Future<void> _fetchBothStreamsInParallel() async {
    // TMDB ID normalization
    final itemData = Map<String, dynamic>.from(widget.item);
    if (itemData['id'] == null && itemData['tmdb_id'] != null) {
      itemData['id'] = itemData['tmdb_id'];
    }
    if (itemData['tmdb_id'] == null && itemData['id'] != null) {
      itemData['tmdb_id'] = itemData['id'];
    }

    // Ensure Render Cloud Provider exists
    List<dynamic> activeProvidersList = List.from(widget.providers);
    bool hasRenderProvider = activeProvidersList.any((p) =>
        p is Map &&
        (p['url']?.toString().contains('onrender') == true ||
            p['name']?.toString().toLowerCase().contains('render') == true));

    if (!hasRenderProvider) {
      activeProvidersList.insert(0, {
        'name': 'Render Cloud API',
        'type': 'embed',
        'url': 'https://tmdb-embed-api-4.onrender.com'
      });
    }

    List<dynamic> xtreamStreams = [];
    List<dynamic> cloudStreams = [];

    // TASK 1: Castle TV & Render Cloud (Runs independently in parallel)
    final cloudTask = MobileStreamService.getDirectStreams(
      item: itemData,
      providers: activeProvidersList,
      season: widget.season,
      episode: widget.episode,
    ).then((results) {
      if (results is List && results.isNotEmpty) {
        cloudStreams = results;
        if (mounted) {
          setState(() {
            // Castle TV stream milte hi UI me turant show kar dein
            streams = [...xtreamStreams, ...cloudStreams];
            loading = false;
          });
        }
      }
    }).catchError((_) {});

    // TASK 2: Xtream IPTV Servers (Runs independently in parallel)
    final xtreamTask = _searchXtreamStreams().then((results) {
      if (results.isNotEmpty) {
        xtreamStreams = results;
        if (mounted) {
          setState(() {
            // Xtream link aate hi sabse upar laga dein
            streams = [...xtreamStreams, ...cloudStreams];
            loading = false;
          });
        }
      }
    }).catchError((_) {});

    // Dono tasks ke complete hone ka wait karein
    await Future.wait([cloudTask, xtreamTask]);

    if (mounted) {
      setState(() {
        streams = [...xtreamStreams, ...cloudStreams];
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
            ],
          ),
          const SizedBox(height: 12),
          if (loading && streams.isEmpty)
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
                        color: isHindi
                            ? const Color(0xFF10B981)
                            : (isXtream ? const Color(0xFF0072D2) : Colors.white10),
                        width: isHindi ? 1.5 : 1.0,
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
                                        'HINDI AUDIO',
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
