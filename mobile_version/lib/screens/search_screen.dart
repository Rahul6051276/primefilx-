import 'package:flutter/material.dart';
import '../services/tmdb_service.dart';
import '../services/stream_service.dart';
import '../internal_player.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  List<dynamic> _searchResults = [];
  bool _isLoading = false;
  final TextEditingController _searchController = TextEditingController();

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isLoading = true);
    final results = await TmdbService.searchMovies(query);
    setState(() {
      _searchResults = results;
      _isLoading = false;
    });
  }

  Future<void> _handleItemTap(dynamic item) async {
    var streams = await MobileStreamService.getDirectStreams(item: item);
    if (streams.isNotEmpty && mounted) {
      final streamUrl = streams.first['url']!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InternalPlayerScreen(
            streamUrl: streamUrl,
            title: item['title'] ?? item['name'] ?? 'Movie',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white),
          autofocus: true,
          onChanged: _performSearch,
          decoration: const InputDecoration(
            hintText: 'Search movies, shows...',
            hintStyle: TextStyle(color: Colors.grey),
            border: InputBorder.none,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.65,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final item = _searchResults[index];
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
