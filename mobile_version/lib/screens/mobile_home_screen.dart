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
  List _streams = [];

  @override
  void initState() {
    super.initState();
    _fetchStreams();
  }

  Future<void> _fetchStreams() async {
    final streams = await MobileStreamService.getDirectStreams(item: widget.item);
    setState(() {
      _streams = streams;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.item['title'] ?? widget.item['name'] ?? 'Select Stream',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _isLoading
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(color: Colors.red),
                ))
              : _streams.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Text('No streams available.', style: TextStyle(color: Colors.grey)),
                    )
                  : SizedBox(
                      height: 250,
                      child: ListView.builder(
                        itemCount: _streams.length,
                        itemBuilder: (context, index) {
                          final stream = _streams[index];
                          return ListTile(
                            title: Text(stream['source'] ?? 'Stream', style: const TextStyle(color: Colors.white)),
                            subtitle: Text('${stream['quality']} - ${stream['language']}', style: const TextStyle(color: Colors.grey)),
                            trailing: const Icon(Icons.play_arrow, color: Colors.red),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => InternalPlayerScreen(videoUrl: stream['url']),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
        ],
      ),
    );
  }
}
