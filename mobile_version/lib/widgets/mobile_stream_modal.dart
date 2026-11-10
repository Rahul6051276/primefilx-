import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import '../services/stream_service.dart';
import '../internal_player.dart';

// TV REMOTE FOCUSABLE WIDGET
class _TvModalFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final BorderRadius? borderRadius;
  final Color focusColor;

  const _TvModalFocusable({
    required this.child,
    required this.onTap,
    this.borderRadius,
    this.focusColor = const Color(0xFF0072D2),
  });

  @override
  State<_TvModalFocusable> createState() => _TvModalFocusableState();
}

class _TvModalFocusableState extends State<_TvModalFocusable> {
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
        borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
            border: Border.all(color: _isFocused ? widget.focusColor : Colors.transparent, width: _isFocused ? 2.5 : 0),
            boxShadow: _isFocused ? [BoxShadow(color: widget.focusColor.withOpacity(0.6), blurRadius: 10, spreadRadius: 1.5)] : null,
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
    return lower.contains('hindi') || lower.contains('dubbed') || lower.contains('dual audio') ||
        lower.contains('dual-audio') || lower.contains('multi audio') || lower.contains('multi-audio') ||
        lower.contains('[hin]') || lower.contains('(hin)') || lower.contains('hin-') || lower.contains('hin ');
  }

  String _cleanTitle(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'\[.*?\]|\(.*?\)|fhd|1080p|720p|4k|hindi|dubbed|telugu|tamil|eng'), '').replaceAll(RegExp(r'[^a-z0-9]'), '').trim();
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
            final uri = Uri.parse('$host/player_api.php').replace(queryParameters: {'username': user, 'password': pass, 'action': 'get_vod_streams'});
            final res = await http.get(uri, headers: _iptvHeaders).timeout(const Duration(seconds: 25));
            if (res.statusCode == 200) {
              final decoded = jsonDecode(res.body);
              if (decoded is List) { vodList = decoded; _vodCache[host] = vodList; }
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
                final aHindi = _isHindiAudioStream(a['name']?.toString() ?? '');
                final bHindi = _isHindiAudioStream(b['name']?.toString() ?? '');
                if (aHindi && !bHindi) return -1;
                if (!aHindi && bHindi) return 1;
                return 0;
              });

              for (var matchedVod in allMatches.take(2)) {
                final streamId = matchedVod['stream_id'];
                final ext = matchedVod['container_extension'] ?? 'mp4';
                final streamUrl = '$host/movie/$user/$pass/$streamId.$ext';
                final realVodName = matchedVod['name']?.toString() ?? title;
                final bool isHindi = _isHindiAudioStream(realVodName) || serverName.toLowerCase().contains('hindi');

                xtreamResults.add({'title': realVodName, 'server': serverName, 'url': streamUrl, 'isHindi': isHindi, 'isXtream': true});
              }
            }
          }
        } else {
          final seasonNum = widget.season ?? 1;
          final episodeNum = widget.episode ?? 1;
          List<dynamic>? seriesList = _seriesCache[host];

          if (seriesList == null) {
            final uri = Uri.parse('$host/player_api.php').replace(queryParameters: {'username': user, 'password': pass, 'action': 'get_series'});
            final res = await http.get(uri, headers: _iptvHeaders).timeout(const Duration(seconds: 25));
            if (res.statusCode == 200) {
              final decoded = jsonDecode(res.body);
              if (decoded is List) { seriesList = decoded; _seriesCache[host] = seriesList; }
            }
          }

          if (seriesList != null && seriesList.isNotEmpty) {
            List<dynamic> matched = seriesList.where((s) => _cleanTitle(s['name']?.toString() ?? '').contains(cleanQuery)).toList();
            matched.sort((a, b) {
              final aH = _isHindiAudioStream(a['name']?.toString() ?? '');
              final bH = _isHindiAudioStream(b['name']?.toString() ?? '');
              if (aH && !bH) return -1;
              if (!aH && bH) return 1;
              return 0;
            });

            if (matched.isNotEmpty) {
              final seriesId = matched.first['series_id'];
              final infoUri = Uri.parse('$host/player_api.php').replace(queryParameters: {'username': user, 'password': pass, 'action': 'get_series_info', 'series_id': seriesId.toString()});
              final infoRes = await http.get(infoUri, headers: _iptvHeaders).timeout(const Duration(seconds: 20));

              if (infoRes.statusCode == 200) {
                final epData = jsonDecode(infoRes.body)['episodes'];
                if (epData is Map && epData[seasonNum.toString()] != null) {
                  final ep = (epData[seasonNum.toString()] as List).firstWhere((e) => e['episode_num'].toString() == episodeNum.toString(), orElse: () => null);
                  if (ep != null) {
                    final streamUrl = '$host/series/$user/$pass/${ep['id']}.${ep['container_extension'] ?? 'mp4'}';
                    final isHindi = _isHindiAudioStream(matched.first['name']?.toString() ?? '') || serverName.toLowerCase().contains('hindi');
                    xtreamResults.add({'title': '${matched.first['name']} - S$seasonNum E$episodeNum', 'server': serverName, 'url': streamUrl, 'isHindi': isHindi, 'isXtream': true});
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
    if (itemData['id'] == null && itemData['tmdb_id'] != null) itemData['id'] = itemData['tmdb_id'];
    if (itemData['tmdb_id'] == null && itemData['id'] != null) itemData['tmdb_id'] = itemData['id'];

    List<dynamic> activeList = List.from(widget.providers);
    if (!activeList.any((p) => p is Map && (p['url']?.toString().contains('onrender') == true || p['name']?.toString().toLowerCase().contains('render') == true))) {
      activeList.insert(0, {'name': 'Render Cloud API', 'type': 'embed', 'url': 'https://tmdb-embed-api-4.onrender.com'});
    }

    List<dynamic> xtreamStreams = [];
    List<dynamic> cloudStreams = [];

    final cloudTask = MobileStreamService.getDirectStreams(item: itemData, providers: activeList, season: widget.season, episode: widget.episode).then((res) {
      if (res is List && res.isNotEmpty) {
        cloudStreams = res;
        if (mounted) setState(() { streams = [...xtreamStreams, ...cloudStreams]; loading = false; });
      }
    }).catchError((_) {});

    final xtreamTask = _searchXtreamStreams().then((res) {
      if (res.isNotEmpty) {
        xtreamStreams = res;
        if (mounted) setState(() { streams = [...xtreamStreams, ...cloudStreams]; loading = false; });
      }
    }).catchError((_) {});

    await Future.wait([cloudTask, xtreamTask]);
    if (mounted) setState(() { streams = [...xtreamStreams, ...cloudStreams]; loading = false; });
  }

  Future<void> _saveContinueWatching() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      var c = jsonDecode(p.getString('continue_watching_mobile') ?? '[]');
      if (c is List) {
        c.removeWhere((item) => item['tmdb_id'].toString() == widget.item['tmdb_id'].toString());
        c.insert(0, {'tmdb_id': widget.item['tmdb_id'], 'title': widget.item['title'] ?? 'Untitled', 'poster': widget.item['poster'] ?? '', 'backdrop': widget.item['backdrop'] ?? '', 'year': widget.item['year'] ?? '', 'rating': widget.item['rating'] ?? '8.0', 'isTv': widget.item['isTv'] ?? false});
        if (c.length > 15) c = c.sublist(0, 15);
        await p.setString('continue_watching_mobile', jsonEncode(c));
        widget.onPlaySaved();
      }
    } catch (_) {}
  }

  // TV & MOBILE CHOICE DIALOG: INTERNAL VS EXTERNAL PLAYER
  void _showPlayerChoiceDialog(String url, String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2029),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text('Kisme play karna chahte hain?', style: TextStyle(color: Colors.white70, fontSize: 13)),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          // 1. Internal Player Button
          _TvModalFocusable(
            onTap: () {
              Navigator.pop(ctx);
              _playStream(url, false);
            },
            borderRadius: BorderRadius.circular(10),
            focusColor: const Color(0xFFE50914),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFFE50914), borderRadius: BorderRadius.circular(10)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_circle_fill, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('In-App Player', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),

          // 2. External Player Button
          _TvModalFocusable(
            onTap: () {
              Navigator.pop(ctx);
              _playStream(url, true);
            },
            borderRadius: BorderRadius.circular(10),
            focusColor: Colors.amber,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: Colors.amber[800], borderRadius: BorderRadius.circular(10)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.open_in_new, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('VLC / MX Player', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('VLC ya External Player install nahi hai!')));
      }
    } else {
      nav.pop();
      nav.push(
        MaterialPageRoute(
          builder: (_) => InternalPlayerScreen(
            videoUrl: cleanUrl,
            title: widget.season != null ? '${widget.item['title']} (S${widget.season} E${widget.episode})' : widget.item['title'] ?? 'Playing',
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
          Text(
            widget.season != null ? '${widget.item['title']} - S${widget.season} E${widget.episode}' : widget.item['title'] ?? 'Select Server',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white, fontSize: isTv ? 20 : 16, fontWeight: FontWeight.bold),
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
            const Expanded(child: Center(child: Text('No active streams found on servers.', style: TextStyle(color: Colors.white54))))
          else
            Expanded(
              child: ListView.separated(
                itemCount: streams.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final s = streams[i];
                  final isHindi = s['isHindi'] == true;
                  final isXtream = s['isXtream'] == true;
                  final String streamTitle = s['title'] ?? '';

                  return _TvModalFocusable(
                    // TV Remote se OK dabate hi Choice Dialog khulega
                    onTap: () => _showPlayerChoiceDialog(s['url'], streamTitle),
                    focusColor: const Color(0xFF0072D2),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: EdgeInsets.all(isTv ? 14 : 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2029),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isHindi ? const Color(0xFF10B981) : (isXtream ? const Color(0xFF0072D2) : Colors.white10), width: isHindi ? 1.5 : 1.0),
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
                                        decoration: BoxDecoration(color: const Color(0xFF
