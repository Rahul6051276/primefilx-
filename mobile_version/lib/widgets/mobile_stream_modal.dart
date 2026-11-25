import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tmdb_service.dart';
import '../services/stream_service.dart';
import '../internal_player.dart';

const MethodChannel _kMedia3PlayerChannel = MethodChannel('com.primeflix/media3');

class MobileMovieDetailSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  final List<dynamic> providers;
  final int? season;
  final int? episode;
  final VoidCallback onPlaySaved;

  const MobileMovieDetailSheet({
    super.key,
    required this.item,
    required this.providers,
    this.season,
    this.episode,
    required this.onPlaySaved,
  });

  @override
  State<MobileMovieDetailSheet> createState() => _MobileMovieDetailSheetState();
}

class _MobileMovieDetailSheetState extends State<MobileMovieDetailSheet> {
  String _overview = '';
  bool _isLaunching = false;

  @override
  void initState() {
    super.initState();
    _overview = (widget.item['overview'] ?? '').toString().trim();
    if (_overview.isEmpty) {
      _fetchStorylineIfNeeded();
    }
  }

  Future<void> _fetchStorylineIfNeeded() async {
    final tmdbId = (widget.item['tmdb_id'] ?? widget.item['id'] ?? '').toString().trim();
    if (tmdbId.isEmpty || AppConfig.tmdbKey.isEmpty) return;
    final bool isTv = widget.season != null || widget.item['isTv'] == true;
    final pathType = isTv ? 'tv' : 'movie';
    try {
      final uri = Uri.parse('${AppConfig.tmdbBase}/$pathType/$tmdbId?api_key=${AppConfig.tmdbKey}');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final text = (data['overview'] ?? '').toString().trim();
        if (text.isNotEmpty && mounted) {
          setState(() => _overview = text);
        }
      }
    } catch (_) {}
  }

  Future<void> _saveContinueWatching() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final decoded = jsonDecode(p.getString('continue_watching_mobile') ?? '[]');
      if (decoded is List) {
        var c = List<dynamic>.from(decoded);
        c.removeWhere((e) => e['tmdb_id'].toString() == widget.item['tmdb_id'].toString());
        c.insert(0, {
          'tmdb_id': widget.item['tmdb_id'],
          'title': widget.item['title'] ?? 'Untitled',
          'overview': _overview,
          'poster': widget.item['poster'] ?? '',
          'backdrop': widget.item['backdrop'] ?? '',
          'year': widget.item['year'] ?? '',
          'rating': widget.item['rating'] ?? '8.0',
          'isTv': widget.item['isTv'] ?? false,
        });
        if (c.length > 15) c = c.sublist(0, 15);
        await p.setString('continue_watching_mobile', jsonEncode(c));
        widget.onPlaySaved();
      }
    } catch (_) {}
  }

  String _resolveGistUrl() {
    if (AppConfig.gistUrl.trim().isNotEmpty) return AppConfig.gistUrl.trim();
    for (final prov in widget.providers) {
      if (prov is Map && prov['gist_url'] != null && prov['gist_url'].toString().trim().isNotEmpty) {
        return prov['gist_url'].toString().trim();
      }
    }
    return '';
  }

  Future<void> _onWatchNowPressed() async {
    if (_isLaunching) return;
    setState(() => _isLaunching = true);

    await _saveContinueWatching();
    if (!mounted) return;

    final tmdbId = (widget.item['tmdb_id'] ?? widget.item['id'] ?? '').toString().trim();
    final bool isTv = widget.season != null || widget.item['isTv'] == true;
    final int sNum = widget.season ?? 1;
    final int eNum = widget.episode ?? 1;
    final String baseTitle = (widget.item['title'] ?? widget.item['name'] ?? 'Primeflix').toString().trim();
    final String displayTitle = widget.season != null ? '$baseTitle (S$sNum E$eNum)' : baseTitle;
    final String directUrl = (widget.item['url'] ?? '').toString().trim();
    final String gistUrl = _resolveGistUrl();

    try {
      final openedNative = await _kMedia3PlayerChannel.invokeMethod<bool>('playMedia', {
        'url': directUrl,
        'title': displayTitle,
        'tmdbId': tmdbId,
        'tmdbKey': AppConfig.tmdbKey,
        'gistUrl': gistUrl,
        'isTv': isTv,
        'season': sNum,
        'episode': eNum,
        'userAgent': 'VLC/3.0.18 LibVLC/3.0.18 (Linux; Android 13)',
      });

      if (mounted) setState(() => _isLaunching = false);
      if (openedNative == true && mounted) {
        Navigator.of(context).pop();
        return;
      }
    } catch (_) {}

    String resolvedUrl = directUrl;
    if (resolvedUrl.isEmpty) {
      try {
        final list = await MobileStreamService.getDirectStreams(
          item: widget.item,
          providers: widget.providers,
          season: widget.season,
          episode: widget.episode,
        );
        if (list.isNotEmpty) {
          resolvedUrl = (list.first['url'] ?? '').toString().trim();
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _isLaunching = false);

    if (resolvedUrl.isNotEmpty) {
      final nav = Navigator.of(context, rootNavigator: true);
      nav.pop();
      nav.push(
        MaterialPageRoute(
          builder: (_) => InternalPlayerScreen(
            videoUrl: resolvedUrl,
            title: displayTitle,
            tmdbId: tmdbId,
            tmdbKey: AppConfig.tmdbKey,
            gistUrl: gistUrl,
            isTv: isTv,
            season: sNum,
            episode: eNum,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stream start nahi ho saka.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (widget.item['title'] ?? widget.item['name'] ?? 'Untitled').toString();
    final poster = (widget.item['poster'] ?? '').toString();
    final rating = (widget.item['rating'] ?? '').toString();
    final year = (widget.item['year'] ?? '').toString();

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        color: Color(0xFF16181F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (poster.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      poster,
                      width: 100,
                      height: 145,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 100,
                        height: 145,
                        color: Colors.grey[900],
                        child: const Icon(Icons.movie, color: Colors.white38),
                      ),
                    ),
                  ),
                if (poster.isNotEmpty) const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (rating.isNotEmpty && rating != '0.0') ...[
                            const Icon(Icons.star_rounded, color: Colors.amber, size: 17),
                            const SizedBox(width: 4),
                            Text(
                              rating,
                              style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(width: 12),
                          ],
                          if (year.isNotEmpty)
                            Text(
                              year,
                              style: const TextStyle(color: Colors.white60, fontSize: 13),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isLaunching ? null : _onWatchNowPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isLaunching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 24),
                label: Text(
                  _isLaunching ? 'Starting Player...' : 'Watch Now',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Storyline',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              _overview.isEmpty ? 'Storyline loading / unavailable.' : _overview,
              style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.45),
            ),
          ],
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
  static final Map<String, String> _imdbIdCache = {};

  final Map<String, String> _iptvHeaders = {
    'User-Agent': 'IPTVSmartersPro/1.0.0 (Linux; Android 12)',
    'Accept': '*/*',
  };

  @override
  void initState() {
    super.initState();
    _fetchEverythingInParallel();
  }

  bool _isHindiAudioStream(String name) {
    final l = name.toLowerCase();
    return l.contains('hindi') ||
        l.contains('dubbed') ||
        l.contains('dual audio') ||
        l.contains('dual-audio') ||
        l.contains('multi audio') ||
        l.contains('[hin]') ||
        l.contains('(hin)');
  }

  String _clean(String t) => t
      .toLowerCase()
      .replaceAll(RegExp(r'\[.*?\]|\(.*?\)|fhd|1080p|720p|4k|hindi|dubbed|telugu|tamil|eng'), '')
      .replaceAll(RegExp(r'[^a-z0-9]'), '')
      .trim();

  bool _isStrictMatch(String vName, String query, String? year) {
    final cV = _clean(vName);
    if (cV.isEmpty || query.isEmpty || !cV.contains(query)) return false;
    if (year != null && year.length == 4 && vName.contains(year)) return true;
    return cV == query || cV.startsWith(query);
  }

  Future<String?> _getImdbId(String tmdbId, bool isTv) async {
    if (AppConfig.tmdbKey.isEmpty) return null;
    if (_imdbIdCache.containsKey(tmdbId)) return _imdbIdCache[tmdbId];
    try {
      final ep = isTv ? 'tv' : 'movie';
      final url = Uri.parse('${AppConfig.tmdbBase}/$ep/$tmdbId/external_ids?api_key=${AppConfig.tmdbKey}');
      final res = await http.get(url).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final imdbId = data['imdb_id']?.toString();
        if (imdbId != null && imdbId.isNotEmpty) {
          _imdbIdCache[tmdbId] = imdbId;
          return imdbId;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List>> _searchStremioStreams() async {
    final List> out = [];
    final tmdbId = widget.item['tmdb_id']?.toString() ?? widget.item['id']?.toString();
    if (tmdbId == null || tmdbId.isEmpty) return out;

    final bool isTv = widget.season != null || widget.item['isTv'] == true;
    final imdbId = await _getImdbId(tmdbId, isTv);
    if (imdbId == null) return out;

    for (final p in widget.providers) {
      if (p is! Map) continue;
      final bool isStremio = p['type'] == 'stremio' || (p['url']?.toString().contains('manifest.json') == true);
      if (!isStremio) continue;

      var baseUrl = (p['url'] ?? p['base_url'])?.toString().trim().replaceAll(RegExp(r'/+$'), '') ?? '';
      baseUrl = baseUrl.replaceFirst('stremio://', 'https://');
      if (baseUrl.endsWith('/manifest.json')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 14).replaceAll(RegExp(r'/+$'), '');
      }

      if (baseUrl.isEmpty) continue;
      final sName = p['name']?.toString() ?? 'Stremio';

      try {
        final String streamPath = isTv
            ? '$baseUrl/stream/series/$imdbId:${widget.season ?? 1}:${widget.episode ?? 1}.json'
            : '$baseUrl/stream/movie/$imdbId.json';

        final r = await http.get(
          Uri.parse(streamPath),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': '*/*',
          },
        ).timeout(const Duration(seconds: 12));

        if (r.statusCode == 200) {
          final data = jsonDecode(r.body);
          final streamList = data['streams'] as List? ?? [];

          for (final s in streamList) {
            final String? directUrl = s['url']?.toString();
            if (directUrl == null || directUrl.isEmpty || !directUrl.startsWith('http')) continue;

            final String sourceName = s['name']?.toString() ?? sName;
            final String rawTitle = s['title']?.toString() ?? widget.item['title'] ?? 'Stream';
            final String displayTitle = rawTitle.split('\n').first.trim();
            final bool isHindi = _isHindiAudioStream(rawTitle) || sourceName.toLowerCase().contains('hindi');

            out.add({
              'title': displayTitle,
              'server': '$sName ($sourceName)',
              'url': directUrl,
              'isHindi': isHindi,
              'isStremio': true,
            });
          }
        }
      } catch (_) {}
    }
    return out;
  }

  Future<List>> _searchXtreamStreams() async {
    final List> out = [];
    final title = widget.item['title'] ?? widget.item['name'] ?? '';
    final tmdbId = widget.item['tmdb_id']?.toString() ?? widget.item['id']?.toString();
    final year = widget.item['year']?.toString();
    final q = _clean(title);
    final bool isTv = widget.season != null || widget.item['isTv'] == true;

    for (final p in widget.providers) {
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
            final uri = Uri.parse('$host/player_api.php').replace(
              queryParameters: {'username': user, 'password': pass, 'action': 'get_vod_streams'},
            );
            final r = await http.get(uri, headers: _iptvHeaders).timeout(const Duration(seconds: 20));
            if (r.statusCode == 200 && jsonDecode(r.body) is List) {
              vodList = jsonDecode(r.body);
              _vodCache[host] = vodList!;
            }
          }
          if (vodList != null && vodList.isNotEmpty) {
            final List<dynamic> allM = [];
            for (final v in vodList) {
              final vN = v['name']?.toString() ?? '';
              if (tmdbId != null && v['tmdb_id']?.toString() == tmdbId) {
                allM.add(v);
              } else if (_isStrictMatch(vN, q, year)) {
                allM.add(v);
              }
            }
            if (allM.isNotEmpty) {
              allM.sort((a, b) {
                final aH = _isHindiAudioStream(a['name']?.toString() ?? '');
                final bH = _isHindiAudioStream(b['name']?.toString() ?? '');
                return (aH && !bH) ? -1 : ((!aH && bH) ? 1 : 0);
              });
              for (final m in allM.take(2)) {
                final realN = m['name']?.toString() ?? title;
                out.add({
                  'title': realN,
                  'server': sName,
                  'url': '$host/movie/$user/$pass/${m['stream_id']}.${m['container_extension'] ?? 'mp4'}',
                  'isHindi': _isHindiAudioStream(realN) || sName.toLowerCase().contains('hindi'),
                  'isXtream': true,
                });
              }
            }
          }
        } else {
          final sNum = widget.season ?? 1;
          final epNum = widget.episode ?? 1;
          List<dynamic>? sList = _seriesCache[host];
          if (sList == null) {
            final uri = Uri.parse('$host/player_api.php').replace(
              queryParameters: {'username': user, 'password': pass, 'action': 'get_series'},
            );
            final r = await http.get(uri, headers: _iptvHeaders).timeout(const Duration(seconds: 20));
            if (r.statusCode == 200 && jsonDecode(r.body) is List) {
              sList = jsonDecode(r.body);
              _seriesCache[host] = sList!;
            }
          }
          if (sList != null && sList.isNotEmpty) {
            final target = sList.firstWhere(
              (s) => _clean(s['name']?.toString() ?? '').contains(q),
              orElse: () => null,
            );
            if (target != null) {
              final infoUri = Uri.parse('$host/player_api.php').replace(
                queryParameters: {
                  'username': user,
                  'password': pass,
                  'action': 'get_series_info',
                  'series_id': target['series_id'].toString(),
                },
              );
              final iR = await http.get(infoUri, headers: _iptvHeaders).timeout(const Duration(seconds: 15));
              if (iR.statusCode == 200) {
                final eps = jsonDecode(iR.body)['episodes'];
                if (eps is Map && eps[sNum.toString()] != null) {
                  final ep = (eps[sNum.toString()] as List).firstWhere(
                    (e) => e['episode_num'].toString() == epNum.toString(),
                    orElse: () => null,
                  );
                  if (ep != null) {
                    final isH = _isHindiAudioStream(target['name']?.toString() ?? '') || sName.toLowerCase().contains('hindi');
                    out.add({
                      'title': '${target['name']} - S$sNum E$epNum',
                      'server': sName,
                      'url': '$host/series/$user/$pass/${ep['id']}.${ep['container_extension'] ?? 'mp4'}',
                      'isHindi': isH,
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
    return out;
  }

  Future<void> _fetchEverythingInParallel() async {
    final itemData = Map<String, dynamic>.from(widget.item);
    if (itemData['id'] == null && itemData['tmdb_id'] != null) itemData['id'] = itemData['tmdb_id'];
    if (itemData['tmdb_id'] == null && itemData['id'] != null) itemData['tmdb_id'] = itemData['id'];

    final List<dynamic> activeList = List.from(widget.providers);
    List<dynamic> xtreamStreams = [];
    List<dynamic> stremioStreams = [];
    List<dynamic> cloudStreams = [];

    final xtreamTask = _searchXtreamStreams().then((r) {
      if (r.isNotEmpty && mounted) {
        xtreamStreams = r;
        setState(() {
          streams = [...xtreamStreams, ...stremioStreams, ...cloudStreams];
          loading = false;
        });
      }
    }).catchError((_) {});

    final stremioTask = _searchStremioStreams().then((r) {
      if (r.isNotEmpty && mounted) {
        stremioStreams = r;
        setState(() {
          streams = [...xtreamStreams, ...stremioStreams, ...cloudStreams];
          loading = false;
        });
      }
    }).catchError((_) {});

    final cloudTask = MobileStreamService.getDirectStreams(
      item: itemData,
      providers: activeList,
      season: widget.season,
      episode: widget.episode,
    ).then((r) {
      if (r is List && r.isNotEmpty && mounted) {
        cloudStreams = r;
        setState(() {
          streams = [...xtreamStreams, ...stremioStreams, ...cloudStreams];
          loading = false;
        });
      }
    }).catchError((_) {});

    await Future.wait([xtreamTask, stremioTask, cloudTask]);
    if (mounted) {
      setState(() {
        streams = [...xtreamStreams, ...stremioStreams, ...cloudStreams];
        loading = false;
      });
    }
  }

  Future<void> _saveContinueWatching() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final decoded = jsonDecode(p.getString('continue_watching_mobile') ?? '[]');
      if (decoded is List) {
        var c = List<dynamic>.from(decoded);
        c.removeWhere((item) => item['tmdb_id'].toString() == widget.item['tmdb_id'].toString());
        c.insert(0, {
          'tmdb_id': widget.item['tmdb_id'],
          'title': widget.item['title'] ?? 'Untitled',
          'poster': widget.item['poster'] ?? '',
          'backdrop': widget.item['backdrop'] ?? '',
          'year': widget.item['year'] ?? '',
          'rating': widget.item['rating'] ?? '8.0',
          'isTv': widget.item['isTv'] ?? false,
        });
        if (c.length > 15) c = c.sublist(0, 15);
        await p.setString('continue_watching_mobile', jsonEncode(c));
        widget.onPlaySaved();
      }
    } catch (_) {}
  }

  Future<void> _playStream(String url) async {
    await _saveContinueWatching();
    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    final cleanUrl = url.trim();
    final title = widget.season != null
        ? '${widget.item['title']} (S${widget.season} E${widget.episode})'
        : widget.item['title'] ?? 'Playing';

    try {
      final opened = await _kMedia3PlayerChannel.invokeMethod<bool>('playMedia', {
        'url': cleanUrl,
        'title': title,
        'userAgent': 'VLC/3.0.18 LibVLC/3.0.18 (Linux; Android 13)',
      });
      if (opened == true && mounted) {
        nav.pop();
        return;
      }
    } catch (_) {}

    nav.pop();
    nav.push(
      MaterialPageRoute(
        builder: (_) => InternalPlayerScreen(
          videoUrl: cleanUrl,
          title: title,
        ),
      ),
    );
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
            widget.season != null
                ? '${widget.item['title']} - S${widget.season} E${widget.episode}'
                : widget.item['title'] ?? 'Select Server',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
            const Expanded(
              child: Center(child: Text('No active streams found on servers.', style: TextStyle(color: Colors.white54))),
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
                  final isStremio = s['isStremio'] == true;
                  final String streamTitle = s['title'] ?? '';

                  return InkWell(
                    onTap: () => _playStream(s['url']),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: EdgeInsets.all(isTv ? 14 : 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2029),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isStremio
                              ? const Color(0xFF8B5CF6)
                              : (isHindi ? const Color(0xFF10B981) : (isXtream ? const Color(0xFF0072D2) : Colors.white10)),
                          width: (isStremio || isHindi || isXtream) ? 1.5 : 1.0,
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
                                    if (isStremio)
                                      Container(
                                        margin: const EdgeInsets.only(right: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(color: const Color(0xFF8B5CF6), borderRadius: BorderRadius.circular(3)),
                                        child: const Text('STREMIO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
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
                                    Expanded(
                                      child: Text(
                                        streamTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: isTv ? 15 : 13),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  s['server'] ?? '',
                                  style: TextStyle(
                                    color: isStremio ? const Color(0xFFA78BFA) : (isXtream ? const Color(0xFF38BDF8) : Colors.white54),
                                    fontSize: isTv ? 13 : 11,
                                    fontWeight: (isStremio || isXtream) ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.play_circle_fill,
                            color: isStremio ? const Color(0xFF8B5CF6) : const Color(0xFF0072D2),
                            size: isTv ? 32 : 26,
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