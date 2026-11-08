import 'package:flutter/material.dart';

class HomeDrawer extends StatelessWidget {
  final Function(String type, String title) onSelectCategory;
  final VoidCallback onOpenSports;

  const HomeDrawer({
    super.key,
    required this.onSelectCategory,
    required this.onOpenSports,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF07080B),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF0F1014)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE50914), Color(0xFF831010)],
                    ),
                    border: Border.all(color: const Color(0xFFFF4D4D), width: 1.5),
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      'PRIME',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        'FLX',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.sports_cricket, color: Color(0xFFE50914)),
            title: const Text('Live Sports & Cricket', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: const Text('Star Sports, Sony Ten & Matches', style: TextStyle(color: Colors.white54, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              onOpenSports();
            },
          ),
          const Divider(color: Colors.white12),
          ListTile(
            leading: const Icon(Icons.movie_filter_rounded, color: Color(0xFFE50914)),
            title: const Text('Bollywood Movies', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(context);
              onSelectCategory('bollywood', 'Bollywood Movies');
            },
          ),
          ListTile(
            leading: const Icon(Icons.local_movies_rounded, color: Color(0xFFE50914)),
            title: const Text('South Indian (Hindi Dubbed)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(context);
              onSelectCategory('south', 'South Indian Movies');
            },
          ),
          ListTile(
            leading: const Icon(Icons.theaters_rounded, color: Color(0xFFE50914)),
            title: const Text('Hollywood Movies (Hindi Dubbed)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(context);
              onSelectCategory('hollywood_movies', 'Hollywood Movies');
            },
          ),
          ListTile(
            leading: const Icon(Icons.live_tv_rounded, color: Color(0xFFE50914)),
            title: const Text('Hindi Web Series', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(context);
              onSelectCategory('hindi_series', 'Hindi Web Series');
            },
          ),
          ListTile(
            leading: const Icon(Icons.connected_tv_rounded, color: Color(0xFFE50914)),
            title: const Text('English Web Series', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(context);
              onSelectCategory('english_series', 'English Web Series');
            },
          ),
        ],
      ),
    );
  }
}
