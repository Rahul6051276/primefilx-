import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tmdb_service.dart';
import '../widgets/mobile_stream_modal.dart';

class MyListScreen extends StatefulWidget {
  const MyListScreen({super.key});

  @override
  State<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends State<MyListScreen> {
  static const Color _primeBlue = Color(0xFF00A8E1);
  static const Color _darkBg = Color(0xFF0B1118);
  static const Color _cardBg = Color(0xFF15202B);

  List> _myList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    loadMyList();
  }

  Future<void> loadMyList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('my_list_mobile') ?? '[]';
      final List decoded = jsonDecode(raw);
      if (!mounted) return;
      setState(() {
        _myList = decoded
            .whereType()
            .map>((e) => Map<String, dynamic>.from(e))
            .toList();
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removeFromList(Map<String, dynamic> item) async {
    try {
      final id = (item['tmdb_id'] ?? item['id'])?.toString() ?? '';
      _myList.removeWhere(
        (element) => ((element['tmdb_id'] ?? element['id'])?.toString() ?? '') == id,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('my_list_mobile', jsonEncode(_myList));
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _cardBg,
          content: Text('${item['title'] ?? 'Item'} removed from My List'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkBg,
      appBar: AppBar(
        backgroundColor: _darkBg,
        title: const Text(
          'My Watchlist',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primeBlue))
          : _myList.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Aapki Watchlist khali hai.\nKisi bhi movie ya series ke modal mein "My List" dabayein.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(14),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.64,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _myList.length,
                  itemBuilder: (ctx, index) {
                    final item = _myList[index];
                    final posterUrl = TmdbService.getPosterUrl(
                      item['poster_path'] ?? item['poster'],
                    );
                    return GestureDetector(
                      onTap: () => MobileStreamModal.show(
                        context,
                        item,
                        onListChanged: loadMyList,
                      ),
                      onLongPress: () => _removeFromList(item),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _cardBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(10),
                                ),
                                child: posterUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: posterUrl,
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                        color: _cardBg,
                                        child: const Icon(
                                          Icons.movie,
                                          color: Colors.white38,
                                        ),
                                      ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(6),
                              child: Text(
                                (item['title'] ?? item['name'] ?? '').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}