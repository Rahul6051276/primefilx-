import 'package:flutter/material.dart';
import '../services/tmdb_service.dart';
import '../services/stream_service.dart';
import '../internal_player.dart';

class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({Key? key}) : super(key: key);

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  List<dynamic> _trendingMovies = [];
  bool _isLoading = true;
  String _selectedTab = 'Recommend';

  final List<String> _tabs = ['Recommend', 'Movies', 'TV Shows', '18+'];
  
  // Streaming Category Providers Row
  final List> _providers = [
    {'name': 'Netflix', 'color': Colors.red, 'logo': 'NETFLIX'},
    {'name': 'JioHotstar', 'color': Colors.deepPurple, 'logo': 'JioHotstar'},
    {'name': 'Prime Video', 'color': Colors.cyan, 'logo': 'prime video'},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final results = await TmdbService.fetchTrending();
    setState(() {
      _trendingMovies = results;
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Search & Icons Bar
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey[900],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const TextField(
                                style: TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Search',
                                  hintStyle: TextStyle(color: Colors.grey),
                                  icon: Icon(Icons.search, color: Colors.grey),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.notifications_outlined, color: Colors.white),
                          const SizedBox(width: 12),
                          const Icon(Icons.download_outlined, color: Colors.white),
                        ],
                      ),
                    ),
                    // Tabs Row
                    SizedBox(
                      height: 40,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _tabs.length,
                        itemBuilder: (context, index) {
                          final tab = _tabs[index];
                          final isSelected = tab == _selectedTab;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedTab = tab),
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                border: isSelected
                                    ? const Border(bottom: BorderSide(color: Colors.white, width: 2))
                                    : null,
                              ),
                              child: Text(
                                tab,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.grey,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Featured Banner Section
                    if (_trendingMovies.isNotEmpty)
                      Container(
                        height: 200,
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                'https://image.tmdb.org/t/p/original${_trendingMovies[0]['backdrop_path'] ?? _trendingMovies[0]['poster_path']}',
                                fit: BoxFit.cover,
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 12,
                                left: 12,
                                child: Text(
                                  _trendingMovies[0]['title'] ?? _trendingMovies[0]['name'] ?? '',
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    // Streaming Category Icons Row (Netflix, JioHotstar, etc.)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12.0),
                      child: Text('Streaming', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 70,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _providers.length,
                        itemBuilder: (context, index) {
                          final provider = _providers[index];
                          return Container(
                            width: 130,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey[900],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[800]!),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              provider['logo'],
                              style: TextStyle(color: provider['color'], fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Trending Now Section
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12.0),
                      child: Text('Trending Now', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 160,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _trendingMovies.length,
                        itemBuilder: (context, index) {
                          final movie = _trendingMovies[index];
                          final posterPath = movie['poster_path'];
                          final posterUrl = posterPath != null ? 'https://image.tmdb.org/t/p/w500$posterPath' : '';
                          return GestureDetector(
                            onTap: () => _handleItemTap(movie),
                            child: Container(
                              width: 105,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: posterUrl.isNotEmpty
                                    ? Image.network(posterUrl, fit: BoxFit.cover)
                                    : Container(color: Colors.grey),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }
}
