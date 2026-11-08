import 'package:flutter/material.dart';
import 'screens/mobile_home_screen.dart';

void main() {
  runApp(const PrimeFilxApp());
}

class PrimeFilxApp extends StatelessWidget {
  const PrimeFilxApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'primefilx',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.red,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const MobileHomeScreen(),
    );
  }
}
