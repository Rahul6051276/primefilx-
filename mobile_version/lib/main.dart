import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/mobile_home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF15202B),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const PrimeFlixApp());
}

class PrimeFlixApp extends StatelessWidget {
  const PrimeFlixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PrimeFlix',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B1118),
        primaryColor: const Color(0xFF00A8E1),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00A8E1),
          secondary: Color(0xFF00A8E1),
          surface: Color(0xFF15202B),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B1118),
          elevation: 0,
        ),
      ),
      home: const PrimeFlixIntroScreen(),
    );
  }
}

class PrimeFlixIntroScreen extends StatefulWidget {
  const PrimeFlixIntroScreen({super.key});

  @override
  State<PrimeFlixIntroScreen> createState() => _PrimeFlixIntroScreenState();
}

class _PrimeFlixIntroScreenState extends State<PrimeFlixIntroScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _scaleAnim = Tween<double>(begin: 0.78, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.65, curve: Curves.easeIn),
      ),
    );

    _controller.forward();

    _navTimer = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 450),
          pageBuilder: (_, __, ___) => const MobileHomeScreen(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    });
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060B10),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'PRIMEFLIX',
                  style: TextStyle(
                    color: const Color(0xFF00A8E1),
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 5,
                    shadows: [
                      Shadow(
                        color: const Color(0xFF00A8E1).withOpacity(0.7),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: 84,
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00A8E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}