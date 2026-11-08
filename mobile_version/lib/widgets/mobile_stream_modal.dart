import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../services/stream_service.dart';
import '../services/tmdb_service.dart';
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

  @override
  void initState() {
    super.initState();
    _fetchDirectStreams();
  }

  Future<void> _fetchDirectStreams() async {
    final results = await MobileStreamService.getDirectStreams(
      item: widget.item,
      providers: widget.providers,
      season: widget.season,
      episode: widget.episode,
    );

    if (mounted) {
      List rawList = results is List ? results : [];
      
      // Strict filter to remove any unwanted IPTV or Xtream sources completely
      var filteredStreams = rawList.where((s) {
        final title = (s['title'] ?? '').toString().toLowerCase();
        final server = (s['server'] ?? '').toString().toLowerCase();
        if (title.contains('iptv') || title.contains('xtream') || server.contains('iptv') || server.contains('xtream')) {
          return false;
        }
        return true;
      }).toList();

      setState(() {
        streams = filteredStreams;
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
      height: MediaQuery.of(context).size.height * 0.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.season != null
                ? '${widget.item['title']} - S${widget.season} E${widget.episode}'
                : widget.item['title'],
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (loading)
            const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFF0072D2))))
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
                  return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2029),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isHindi ? const Color(0xFF10B981) : Colors.white10,
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
                                      s['title'],
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
                              const SizedBox(height: 2),
                              Text(s['server'], style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11)),
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
