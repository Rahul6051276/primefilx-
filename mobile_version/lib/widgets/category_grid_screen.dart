import 'package:flutter/material.dart';

class MobileCategoryGridScreen extends StatefulWidget {
  final String title;
  final List rawItems;
  final Function(dynamic) onItemTapped;

  const MobileCategoryGridScreen({
    super.key,
    required this.title,
    required this.rawItems,
    required this.onItemTapped,
  });

  @override
  State<MobileCategoryGridScreen> createState() => _MobileCategoryGridScreenState();
}

class _MobileCategoryGridScreenState extends State<MobileCategoryGridScreen> {
  late List _items;
  bool _isLatest = false;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.rawItems);
    _applySort();
  }

  void _applySort() {
    if (_isLatest) {
      _items.sort((a, b) {
        final yearA = int.tryParse(a['year']?.toString() ?? '0') ?? 0;
        final yearB = int.tryParse(b['year']?.toString() ?? '0') ?? 0;
        return yearB.compareTo(yearA);
      });
    } else {
      _items.sort((a, b) {
        final rateA = double.tryParse(a['rating']?.toString() ?? '0') ?? 0.0;
        final rateB = double.tryParse(b['rating']?.toString() ?? '0') ?? 0.0;
        return rateB.compareTo(rateA);
      });
    }
  }

  void _toggleFilter() {
    setState(() {
      _isLatest = !_isLatest;
      _applySort();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1014),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1014),
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 10, bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _toggleFilter,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E222D),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE50914), width: 1.2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.swap_vert_rounded, size: 16, color: Color(0xFFFF4D4D)),
                    const SizedBox(width: 4),
                    Text(
                      _isLatest ? 'Latest' : 'Popular',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: _items.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.65,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _items.length,
              itemBuilder: (ctx, i) {
                final item = _items[i];
                return GestureDetector(
                  onTap: () => widget.onItemTapped(item),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          item['poster'] ?? item['backdrop'] ?? '',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1E2029)),
                        ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            color: Colors.black87,
                            child: Text(
                              item['title'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
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
