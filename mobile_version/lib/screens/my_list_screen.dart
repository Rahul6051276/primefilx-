import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/mobile_stream_modal.dart';

class MyListScreen extends StatefulWidget {
  const MyListScreen({Key? key}) : super(key: key);

  @override
  State<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends State<MyListScreen> {
  List<dynamic> _myListItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMyList();
  }

  Future<void> _loadMyList() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> rawList = prefs.getStringList('primefilx_my_list') ?? [];
    
    setState(() {
      _myListItems = rawList.map((item) => jsonDecode(item)).toList();
      _isLoading = false;
    });
  }

  void _handleItemTap(dynamic item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => MobileQualitySelectorSheet(
        item: Map<String, dynamic>.from(item),
        providers: const [],
        onPlaySaved: () => _loadMyList(),
      ),
    ).then((_) {
      // Reload list when modal closes in case items were removed
      _loadMyList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('My List', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
          : _myListItems.isEmpty
              ? const Center(
                  child: Text(
                    'No saved movies or shows in your list.',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.65,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _myListItems.length,
                  itemBuilder: (context, index) {
                    final item = _myListItems[index];
                    final posterPath = item['poster_path'] ?? item['poster'];
                    final posterUrl = posterPath != null 
                        ? (posterPath.startsWith('http') ? posterPath : 'https://image.tmdb.org/t/p/w500$posterPath') 
                        : '';

                    return GestureDetector(
                      onTap: () => _handleItemTap(item),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: posterUrl.isNotEmpty
                            ? Image.network(
                                posterUrl, 
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(color: Colors.grey[900], child: const Icon(Icons.movie, color: Colors.white54)),
                              )
                            : Container(color: Colors.grey[900], child: const Center(child: Icon(Icons.movie, color: Colors.white54))),
                      ),
                    );
                  },
                ),
    );
  }
}
