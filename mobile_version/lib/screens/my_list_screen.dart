import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/stream_modal.dart';

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
      backgroundColor: Colors.transparent,
      builder: (_) => StreamModal(item: item),
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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
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
                    final posterPath = item['poster_path'];
                    final posterUrl = posterPath != null ? 'https://image.tmdb.org/t/p/w500$posterPath' : '';

                    return GestureDetector(
                      onTap: () => _handleItemTap(item),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: posterUrl.isNotEmpty
                            ? Image.network(posterUrl, fit: BoxFit.cover)
                            : Container(color: Colors.grey, child: const Center(child: Icon(Icons.movie))),
                      ),
                    );
                  },
                ),
    );
  }
}
