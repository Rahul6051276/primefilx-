import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import '../services/stream_service.dart';
import '../internal_player.dart';

// TV Remote Focusable Widget for Modal
class _TvStreamFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final BorderRadius? borderRadius;
  final Color focusColor;

  const _TvStreamFocusable({
    required this.child,
    required this.onTap,
    this.borderRadius,
    this.focusColor = const Color(0xFF0072D2),
  });

  @override
  State<_TvStreamFocusable> createState() => _TvStreamFocusableState();
}

class _TvStreamFocusableState extends State<_TvStreamFocusable> {
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
        borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused ? widget.focusColor : Colors.transparent,
              width: _isFocused ? 2.5 : 0,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: widget.focusColor.withOpacity(0.6),
                      blurRadius: 10,
                      spreadRadius: 1.5,
                    )
                  ]
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

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

  Future<void> _fetchBothStreamsInParallel() async {
    final itemData = Map<String, dynamic>.from(widget.item);
    if (itemData['id'] == null && itemData['tmdb_id'] != null) {
      itemData['id'] = itemData['tmdb_id'];
    }
    if (itemData['tmdb_id'] == null && itemData['id'] != null) {
      itemData['tmdb_id'] = itemData['id'];
    }

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
            streams = [...xtreamStreams, ...cloudStreams];
            loading = false;
          });
        }
      }
    }).catchError((_) {});

    final xtreamTask = _searchXtreamStreams().then((results) {
      if (results.isNotEmpty) {
        xtreamStreams = results;
        if (mounted) {
          setState(() {
            streams = [...xtreamStreams, ...cloudStreams];
            loading = false;
          });
        }
      }
    }).catchError((_) {});

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

  // 100% WORKING TV & MOBILE PLAY FUNCTION
  void _playStream(String url, bool isVlc) async {
    await _saveContinueWatching();
    if (!mounted) return;

    final nav = Navigator.of(context, rootNavigator: true);
    final cleanUrl = url.trim();

    if (isVlc) {
      try {
        final intent = AndroidIntent(
          action: 'action_view',
          data: cleanUrl,
          type: 'video/*',
          flags: const [Flag.FLAG_ACTIVITY_NEW_TASK],
        );
        await intent.launch();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('VLC ya External Player install nahi hai!')),
          );
        }
      }
    } else {
      // Sheet ko band karke player open karein
      nav.pop();
      nav.push(
        MaterialPageRoute(
          builder: (_) => InternalPlayerScreen(
            videoUrl: cleanUrl,
            title: widget.season != null
                ? '${widget.item['title']} (S${widget.season} E${widget.episode})'
                : widget.item['title'] ?? 'Playing',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTv = size.width > 600;

    return Container(
      padding: EdgeInsets.all(isTv ? 24 : 18),
      height: size.height * (isTv ? 0.75 : 0.6),
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
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isTv ? 20 : 16,
                    fontWeight: FontWeight.bold,
                  ),
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

                  // Pura Card Focusable hai (TV Remote ka OK dabate hi Play hoga)
                  return _TvStreamFocusable(
                    onTap: () => _playStream(s['url'], false),
                    focusColor: const Color(0xFF0072D2),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: EdgeInsets.all(isTv ? 14 : 10),
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
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: isTv ? 15 : 13,
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
                                    fontSize: isTv ? 13 : 11,
                                    fontWeight: isXtream ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Direct Play Button
                          IconButton(
                            icon: Icon(Icons.play_circle_fill, color: const Color(0xFF0072D2), size: isTv ? 34 : 28),
                            onPressed: () => _playStream(s['url'], false),
                          ),
                          // External VLC Button
                          IconButton(
                            icon: Icon(Icons.open_in_new, color: Colors.amber, size: isTv ? 28 : 24),
                            onPressed: () => _playStream(s['url'], true),
                          ),
                        ],
                      ),
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
