import 'package:flutter/material.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1014),
      appBar: AppBar(
        title: const Text('Search Movies & Shows', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF16181F),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: const Center(
        child: Text('Search screen placeholder', style: TextStyle(color: Colors.white70)),
      ),
    );
  }
}
