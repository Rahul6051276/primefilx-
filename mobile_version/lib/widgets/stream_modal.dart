import 'package:flutter/material.dart';
import '../services/stream_service.dart';
import '../internal_player.dart';

class StreamModal extends StatefulWidget {
  final dynamic item;

  const StreamModal({Key? key, required this.item}) : super(key: key);

  @override
  State<StreamModal> createState() => _StreamModalState();
}

class _StreamModalState extends State<StreamModal> {
  bool _isLoading = true;
  List> _streams = [];

  @override
  void initState() {
    super.initState();
    _fetchStreams();
  }

  Future<void> _fetchStreams() async {
    final streams = await MobileStreamService.getDirectStreams(item: widget.item);
    if (mounted) {
      setState(() {
        _streams = streams;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.item['title'] ?? widget.item['name'] ?? 'Details';
    final overview = widget.item['overview'] ?? 'No overview available.';
    final posterPath = widget.item['poster_path'];
    final posterUrl = posterPath != null ? 'https://image.tmdb.org/t/p/w500$posterPath' : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (posterUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(posterUrl, width: 100, height: 150, fit: BoxFit.cover),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        overview,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Available Streams', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.red))
                : _streams.isEmpty
                    ? const Text('No streams found.', style: TextStyle(color: Colors.grey))
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _streams.length,
                        itemBuilder: (context, index) {
                          final stream = _streams[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(stream['source'] ?? 'Stream', style: const TextStyle(color: Colors.white)),
                            subtitle: Text(stream['quality'] ?? '', style: const TextStyle(color: Colors.grey)),
                            trailing: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => InternalPlayerScreen(
                                      streamUrl: stream['url'],
                                      title: title,
                                    ),
                                  ),
                                );
                              },
                              child: const Text('Play', style: TextStyle(color: Colors.white)),
                            ),
                          );
                        },
                      ),
          ],
        ),
      ),
    );
  }
}
