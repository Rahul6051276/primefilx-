import 'package:flutter/material.dart';
import 'screens/mobile_home_screen.dart';

void main() {
  runApp(const primefilx());
}

class primefilx extends StatelessWidget {
  const primefilx({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Primefilx',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.red,
      ),
      home: const MobileHomeScreen(),
    );
  }
}
