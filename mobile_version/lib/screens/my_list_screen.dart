import 'package:flutter/material.dart';

class MyListScreen extends StatelessWidget {
  const MyListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1014),
      appBar: AppBar(
        title: const Text('My Watchlist', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF16181F),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: const Center(
        child: Text('My List screen placeholder', style: TextStyle(color: Colors.white70)),
      ),
    );
  }
}
