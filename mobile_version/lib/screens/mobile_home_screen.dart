import 'dart:async';
import 'package:flutter/material.dart';
import '../services/tmdb_service.dart';
import '../widgets/stream_modal.dart';
import 'search_screen.dart';
import 'my_list_screen.dart';

class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({Key? key}) : super(key: key);

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  List<dynamic> _trendingMovies = [];
  bool _isLoading = true;
  int _currentIndex = 0; // Bottom nav index
  
  final PageController _pageController = PageController();
  Timer? _sliderTimer;

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

  @override
  void dispose() {
    _sliderTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final results = await TmdbService.fetchTrending();
    setState(() {
      _trendingMovies = results;
      _isLoading = false;
    });

    if (_trendingMovies.isNotEmpty) {
      _startAutoSlider();
    }
  }

  void _startAutoSlider() {
    _sliderTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_pageController.hasClients && _trendingMovies.isNotEmpty) {
        int nextPage = (_pageController.page?.round() ?? 0) + 1;
        if (nextPage >= 5 || nextPage >= _trendingMovies.length) {
          nextPage = 0;
        }
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _handleItemTap(dynamic item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StreamModal(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentIndex == 3) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const MyListScreen(),
        bottomNavigationBar: _buildBottomNavigationBar(),
      );
    }

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
                            child: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const SearchScreen()),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[900],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.search, color: Colors.grey),
                                    SizedBox(width: 8),
                                    Text('Search', style: TextStyle(color: Colors.grey, fontSize: 16)),
                                  ],
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
                    const SizedBox(height: 10),
                    // Auto-Sliding Featured Banner Section (Clean, without top tabs)
                    if (_trendingMovies.isNotEmpty)
                      SizedBox(
                        height: 220,
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: _trendingMovies.length > 5 ? 5 : _trendingMovies.length,
                          itemBuilder: (context, index) {
                            final movie = _trendingMovies[index];
                            final backdrop = movie['backdrop_path'] ?? movie['poster_path'];
                            return GestureDetector(
                              onTap: () => _handleItemTap(movie),
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 12),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (backdrop != null)
                                        Image.network(
                                          'https://image.tmdb.org/t/p/original$backdrop',
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
                                          movie['title'] ?? movie['name'] ?? '',
                                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 20),
                    // Streaming Category Providers Row
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
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      backgroundColor: Colors.black,
      selectedItemColor: Colors.red,
      unselectedItemColor: Colors.grey,
      currentIndex: _currentIndex,
      type: BottomNavigationBarType.fixed,
      onTap: (index) {
        setState(() {
          _currentIndex = index;
        });
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.sort), label: 'Sort'),
        BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Ranking'),
        BottomNavigationBarItem(icon: Icon(Icons.list), label: 'My List'),
      ],
    );
  }
}
