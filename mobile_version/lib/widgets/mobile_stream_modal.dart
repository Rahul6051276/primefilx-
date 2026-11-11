import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import '../services/stream_service.dart';
import '../internal_player.dart';

class _TvModalFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final BorderRadius? borderRadius;
  final Color focusColor;
  const _TvModalFocusable({required this.child, required this.onTap, this.borderRadius, this.focusColor = const Color(0xFF0072D2)});
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
          if (event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.space || event.logicalKey == LogicalKeyboardKey.gameButtonA) {
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
  final int? season, episode;
  final List<dynamic> providers;
  final VoidCallback onPlaySaved;
  const MobileQualitySelectorSheet({super.key, required this.item, this.season, this.episode, required this.providers, required this.onPlaySaved});
  @override
  State<MobileQualitySelectorSheet> createState() => _MobileQualitySelectorSheetState();
}

class _MobileQualitySelectorSheetState extends State<MobileQualitySelectorSheet> {
  List<dynamic> streams = [];
  bool loading = true;
  String currentStatus = 'Finding best streaming servers...';
  static final Map<String, List<dynamic>> _vodCache = {};
  static final Map<String, List<dynamic>> _seriesCache = {};
  static final Map<String, String> _stalkerTokens = {};

  final Map<String, String> _iptvHeaders = {'User-Agent': 'IPTVSmartersPro/1.0.0 (Linux; Android 12)', 'Accept': '*/*'};

  @override
  void initState() {
    super.initState();
    _fetchEverythingInParallel();
  }

  bool _isHindiAudioStream(String name) {
    final l = name.toLowerCase();
    return l.contains('hindi') || l.contains('dubbed') || l.contains('dual audio') || l.contains('dual-audio') || l.contains('multi audio') || l.contains('[hin]') || l.contains('(hin)');
  }

  String _clean(String t) => t.toLowerCase().replaceAll(RegExp(r'\[.*?\]|\(.*?\)|fhd|1080p|720p|4k|hindi|dubbed|telugu|tamil|eng'), '').replaceAll(RegExp(r'[^a-z0-9]'), '').trim();

  bool _isStrictMatch(String vName, String query, String? year) {
    final cV = _clean(vName);
    if (cV.isEmpty || query.isEmpty || !cV.contains(query)) return false;
    if (year != null && year.length == 4 && vName.contains(year)) return true;
    return cV == query || cV.startsWith(query);
  }

  // 1. XTREAM IPTV SEARCH
  Future<List<Map<String, dynamic>>> _searchXtreamStreams() async {
    List<Map<String, dynamic>> res = [];
    final title = widget.item['title'] ?? widget.item['name'] ?? '';
    final tmdbId = widget.item['tmdb_id']?.toString() ?? widget.item['id']?.toString();
    final year = widget.item['year']?.toString();
    final q = _clean(title);
    final bool isTv = widget.season != null || widget.item['isTv'] == true;

    for (var p in widget.providers) {
      if (p is! Map) continue;
      if (p['type'] != 'xtream' && p['xc_host'] == null) continue;
      final host = (p['xc_host'] ?? p['server'] ?? p['url'])?.toString().replaceAll(RegExp(r'/+$'), '');
      final user = (p['xc_username'] ?? p['username'])?.toString();
      final pass = (p['xc_password'] ?? p['password'])?.toString();
      final sName = (p['name'] ?? 'Xtream Server').toString();
      if (host == null || user == null || pass == null || host.isEmpty) continue;

      try {
        if (!isTv) {
          List<dynamic>? vodList = _vodCache[host];
          if (vodList == null) {
            final uri = Uri.parse('$host/player_api.php').replace(queryParameters: {'username': user, 'password': pass, 'action': 'get_vod_streams'});
            final r = await http.get(uri, headers: _iptvHeaders).timeout(const Duration(seconds: 20));
            if (r.statusCode == 200 && jsonDecode(r.body) is List) { vodList = jsonDecode(r.body); _vodCache[host] = vodList!; }
          }
          if (vodList != null && vodList.isNotEmpty) {
            List<dynamic> allM = [];
            for (var v in vodList) {
              final vN = v['name']?.toString() ?? '';
              if (tmdbId != null && v['tmdb_id']?.toString() == tmdbId) { allM.add(v); }
              else if (_isStrictMatch(vN, q, year)) { allM.add(v); }
            }
            if (allM.isNotEmpty) {
              allM.sort((a, b) {
                final aH = _isHindiAudioStream(a['name']?.toString() ?? '');
                final bH = _isHindiAudioStream(b['name']?.toString() ?? '');
                return (aH && !bH) ? -1 : ((!aH && bH) ? 1 : 0);
              });
              for (var m in allM.take(2)) {
                final realN = m['name']?.toString() ?? title;
                res.add({'title': realN, 'server': sName, 'url': '$host/movie/$user/$pass/${m['stream_id']}.${m['container_extension'] ?? 'mp4'}', 'isHindi': _isHindiAudioStream(realN) || sName.toLowerCase().contains('hindi'), 'isXtream': true});
              }
            }
          }
        } else {
          final sNum = widget.season ?? 1, epNum = widget.episode ?? 1;
          List<dynamic>? sList = _seriesCache[host];
          if (sList == null) {
            final uri = Uri.parse('$host/player_api.php').replace(queryParameters: {'username': user, 'password': pass, 'action': 'get_series'});
            final r = await http.get(uri, headers: _iptvHeaders).timeout(const Duration(seconds: 20));
            if (r.statusCode == 200 && jsonDecode(r.body) is List) { sList = jsonDecode(r.body); _seriesCache[host] = sList!; }
          }
          if (sList != null && sList.isNotEmpty) {
            final target = sList.firstWhere((s) => _clean(s['name']?.toString() ?? '').contains(q), orElse: () => null);
            if (target != null) {
              final infoUri = Uri.parse('$host/player_api.php').replace(queryParameters: {'username': user, 'password': pass, 'action': 'get_series_info', 'series_id': target['series_id'].toString()});
              final iR = await http.get(infoUri, headers: _iptvHeaders).timeout(const Duration(seconds: 15));
              if (iR.statusCode == 200) {
                final eps = jsonDecode(iR.body)['episodes'];
                if (eps is Map && eps[sNum.toString()] != null) {
                  final ep = (eps[sNum.toString()] as List).firstWhere((e) => e['episode_num'].toString() == epNum.toString(), orElse: () => null);
                  if (ep != null) {
                    final isH = _isHindiAudioStream(target['name']?.toString() ?? '') || sName.toLowerCase().contains('hindi');
                    res.add({'title': '${target['name']} - S$sNum E$epNum', 'server': sName, 'url': '$host/series/$user/$pass/${ep['id']}.${ep['container_extension'] ?? 'mp4'}', 'isHindi': isH, 'isXtream': true});
                  }
                }
              }
            }
          }
        }
      } catch (_) {}
    }
    return res;
  }

  // 2. STALKER PORTAL (MAG / MAC ADDRESS) DIRECT SEARCH & CREATE LINK
  Future<List<Map<String, dynamic>>> _searchStalkerStreams() async {
    List<Map<String, dynamic>> res = [];
    final title = widget.item['title'] ?? widget.item['name'] ?? '';
    final cleanTitle = title.trim();
    final bool isTv = widget.season != null || widget.item['isTv'] == true;
    final type = isTv ? 'series' : 'vod';

    for (var p in widget.providers) {
      if (p is! Map) continue;
      final bool isStalker = p['type'] == 'stalker' || (p['mac'] != null && p['portal_url'] != null);
      if (!isStalker) continue;

      var portalUrl = (p['portal_url'] ?? p['url'])?.toString().trim().replaceAll(RegExp(r'/+$'), '') ?? '';
      if (portalUrl.endsWith('/c')) portalUrl = portalUrl.substring(0, portalUrl.length - 2).replaceAll(RegExp(r'/+$'), '');
      final mac = p['mac']?.toString().trim();
      final sName = p['name']?.toString() ?? 'Stalker Portal';
      final sn = p['serial_number']?.toString() ?? 'e73857b1e06c0d227d20367c8bd81f1d';
      final devId1 = p['device_id']?.toString() ?? '9F3DD57FF522B51F28849BB26018507A8C0655C8C39FFB0EBE81BFCC42A9E382';
      final devId2 = p['device_id2']?.toString() ?? devId1;
      final sig = p['signature']?.toString() ?? '';

      if (portalUrl.isEmpty || mac == null || mac.isEmpty) continue;
      final loadUrl = '$portalUrl/server/load.php';

      try {
        // Step A: Token / Handshake
        String? token = _stalkerTokens[mac];
        if (token == null) {
          final hsHeaders = {
            'User-Agent': 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3',
            'Cookie': 'mac=$mac; stb_lang=en; timezone=Europe/Kiev;',
            'Accept': '*/*',
          };
          final hsRes = await http.get(Uri.parse('$loadUrl?type=stb&action=handshake&token=&JsHttpRequest=1-xml'), headers: hsHeaders).timeout(const Duration(seconds: 8));
          if (hsRes.statusCode == 200) {
            token = jsonDecode(hsRes.body)['js']?['token']?.toString();
            if (token != null) {
              _stalkerTokens[mac] = token;
              // Profile Auth
              final profUrl = '$loadUrl?type=stb&action=get_profile&hd=1&token=$token&ver=ImageDescription&num_banks=2&sn=$sn&stb_type=MAG250&image_version=218&video_out=hdmi&device_id=$devId1&device_id2=$devId2&signature=$sig&auth_second_step=0&hw_version=1.7-BD-00&not_valid_token=0&client_type=STB&JsHttpRequest=1-xml';
              await http.get(Uri.parse(profUrl), headers: {...hsHeaders, 'Authorization': 'Bearer $token', 'Cookie': 'mac=$mac; token=$token; stb_lang=en; timezone=Europe/Kiev;'}).timeout(const Duration(seconds: 8));
            }
          }
        }

        if (token == null) continue;

        final authHeaders = {
          'User-Agent': 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3',
          'Cookie': 'mac=$mac; token=$token; stb_lang=en; timezone=Europe/Kiev;',
          'Authorization': 'Bearer $token',
          'Accept': '*/*',
        };

        // Step B: Search VOD
        final sUri = Uri.parse('$loadUrl?type=$type&action=get_ordered_list&sortby=added&p=1&token=$token&search=${Uri.encodeComponent(cleanTitle)}&JsHttpRequest=1-xml');
        final sRes = await http.get(sUri, headers: authHeaders).timeout(const Duration(seconds: 10));

        if (sRes.statusCode == 200) {
          final data = jsonDecode(sRes.body);
          final list = (data['js']?['data'] as List?) ?? [];

          for (var item in list.take(2)) {
            final cmd = item['cmd']?.toString();
            final itemName = item['name']?.toString() ?? cleanTitle;
            if (cmd == null || cmd.isEmpty) continue;

            // Step C: Create Link
            final lUri = Uri.parse('$loadUrl?type=$type&action=create_link&cmd=${Uri.encodeComponent(cmd)}&token=$token&JsHttpRequest=1-xml');
            final lRes = await http.get(lUri, headers: authHeaders).timeout(const Duration(seconds: 8));

            if (lRes.statusCode == 200) {
              final linkData = jsonDecode(lRes.body);
              String? rawCmd = linkData['js']?['cmd']?.toString();
              if (rawCmd != null && rawCmd.isNotEmpty) {
                final streamUrl = rawCmd.replaceFirst('ffmpeg ', '').trim();
                final bool isHindi = _isHindiAudioStream(itemName) || sName.toLowerCase().contains('hindi');

                res.add({
                  'title': itemName,
                  'server': sName,
                  'url': streamUrl,
                  'isHindi': isHindi,
                  'isStalker': true,
                });
              }
            }
          }
        }
      } catch (_) {}
    }
    return res;
  }

  // 3. PARALLEL EXECUTION: XTREAM + STALKER + CASTLE TV ALL RUN SIMULTANEOUSLY
  Future<void> _fetchEverythingInParallel() async {
    final itemData = Map<String, dynamic>.from(widget.item);
    if (itemData['id'] == null && itemData['tmdb_id'] != null) itemData['id'] = itemData['tmdb_id'];
    if (itemData['tmdb_id'] == null && itemData['id'] != null) itemData['tmdb_id'] = itemData['id'];

    List<dynamic> activeList = List.from(widget.providers);
    if (!activeList.any((p) => p is Map && (p['url']?.toString().contains('onrender') == true || p['name']?.toString().toLowerCase().contains('render') == true))) {
      activeList.insert(0, {'name': 'Render Cloud API', 'type': 'embed', 'url': 'https://tmdb-embed-api-4.onrender.com'});
    }

    List<dynamic> xtreamStreams = [];
    List<dynamic> stalkerStreams = [];
    List<dynamic> cloudStreams = [];

    // TASK 1: Xtream IPTV
    final xtreamTask = _searchXtreamStreams().then((r) {
      if (r.isNotEmpty && mounted) {
        xtreamStreams = r;
        setState(() { streams = [...xtreamStreams, ...stalkerStreams, ...cloudStreams]; loading = false; });
      }
    }).catchError((_) {});

    // TASK 2: Stalker Portal (CloudCDN VIP)
    final stalkerTask = _searchStalkerStreams().then((r) {
      if (r.isNotEmpty && mounted) {
        stalkerStreams = r;
        setState(() { streams = [...xtreamStreams, ...stalkerStreams, ...cloudStreams]; loading = false; });
      }
    }).catchError((_) {});

    // TASK 3: Castle TV & Render Cloud
    final cloudTask = MobileStreamService.getDirectStreams(item: itemData, providers: activeList, season: widget.season, episode: widget.episode).then((r) {
      if (r is List && r.isNotEmpty && mounted) {
        cloudStreams = r;
        setState(() { streams = [...xtreamStreams, ...stalkerStreams, ...cloudStreams]; loading = false; });
      }
    }).catchError((_) {});

    await Future.wait([xtreamTask, stalkerTask, cloudTask]);
    if (mounted) setState(() { streams = [...xtreamStreams, ...stalkerStreams, ...cloudStreams]; loading = false; });
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
          _TvModalFocusable(
            onTap: () { Navigator.pop(ctx); _playStream(url, false); },
            borderRadius: BorderRadius.circular(10),
            focusColor: const Color(0xFFE50914),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFFE50914), borderRadius: BorderRadius.circular(10)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.play_circle_fill, color: Colors.white, size: 20), SizedBox(width: 8), Text('In-App Player', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]),
            ),
          ),
          _TvModalFocusable(
            onTap: () { Navigator.pop(ctx); _playStream(url, true); },
            borderRadius: BorderRadius.circular(10),
            focusColor: Colors.amber,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: Colors.amber[800], borderRadius: BorderRadius.circular(10)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.open_in_new, color: Colors.white, size: 20), SizedBox(width: 8), Text('VLC / MX Player', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]),
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
        final intent = AndroidIntent(action: 'action_view', data: cleanUrl, type: 'video/*', flags: const [Flag.FLAG_ACTIVITY_NEW_TASK]);
        await intent.launch();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('VLC ya External Player install nahi hai!')));
      }
    } else {
      nav.pop();
      nav.push(MaterialPageRoute(builder: (_) => InternalPlayerScreen(videoUrl: cleanUrl, title: widget.season != null ? '${widget.item['title']} (S${widget.season} E${widget.episode})' : widget.item['title'] ?? 'Playing')));
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
          Text(widget.season != null ? '${widget.item['title']} - S${widget.season} E${widget.episode}' : widget.item['title'] ?? 'Select Server', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: isTv ? 20 : 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (loading && streams.isEmpty)
            Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(color: Color(0xFF0072D2)), const SizedBox(height: 12), Text(currentStatus, style: const TextStyle(color: Colors.white70, fontSize: 12))])))
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
                  final isStalker = s['isStalker'] == true;
                  final String streamTitle = s['title'] ?? '';

                  return _TvModalFocusable(
                    onTap: () => _showPlayerChoiceDialog(s['url'], streamTitle),
                    focusColor: isStalker ? const Color(0xFF8B5CF6) : const Color(0xFF0072D2),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: EdgeInsets.all(isTv ? 14 : 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2029),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isStalker
                              ? const Color(0xFF8B5CF6)
                              : (isHindi ? const Color(0xFF10B981) : (isXtream ? const Color(0xFF0072D2) : Colors.white10)),
                          width: (isStalker || isHindi || isXtream) ? 1.5 : 1.0,
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
                                    if (isStalker)
                                      Container(
                                        margin: const EdgeInsets.only(right: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(color: const Color(0xFF8B5CF6), borderRadius: BorderRadius.circular(3)),
                                        child: const Text('STALKER', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                                      ),
                                    if (isXtream)
                                      Container(
                                        margin: const EdgeInsets.only(right: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(color: const Color(0xFF0072D2), borderRadius: BorderRadius.circular(3)),
                                        child: const Text('IPTV', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                                      ),
                                    if (isHindi)
                                      Container(
                                        margin: const EdgeInsets.only(right: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(3)),
                                        child: const Text('HINDI AUDIO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black)),
                                      ),
                                    Expanded(child: Text(streamTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: isTv ? 15 : 13))),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  s['server'] ?? '',
                                  style: TextStyle(
                                    color: isStalker
                                        ? const Color(0xFFA78BFA)
                                        : (isXtream ? const Color(0xFF38BDF8) : Colors.white54),
                                    fontSize: isTv ? 13 : 11,
                                    fontWeight: (isStalker || isXtream) ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.play_circle_fill, color: isStalker ? const Color(0xFF8B5CF6) : const Color(0xFF0072D2), size: isTv ? 32 : 26),
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
// END OF FILE
