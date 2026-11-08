import 'package:flutter/material.dart';
import '../services/tmdb_service.dart';
import '../services/stream_service.dart';
import '../widgets/mobile_stream_modal.dart';

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
      if (mounted) setState(() => _searchResults = []);
      return;
    }
    if (mounted) setState(() => _isLoading = true);
    
    try {
      final results = await TmdbService.searchMovies(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
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
        onPlaySaved: () {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
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
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.white54),
              onPressed: () {
                _searchController.clear();
                _performSearch('');
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
          : _searchResults.isEmpty
              ? const Center(
                  child: Text(
                    'Search for your favorite movies & shows',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
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
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final item = _searchResults[index];
                    final posterPath = item['poster_path'];
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
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.grey[900], 
                                  child: const Icon(Icons.movie, color: Colors.white54),
                                ),
                              )
                            : Container(
                                color: Colors.grey[900], 
                                child: const Center(child: Icon(Icons.movie, color: Colors.white54)),
                              ),
                      ),
                    );
                  },
                ),
    );
  }
}
