import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class InternalPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String tmdbId;
  final String tmdbKey;
  final String gistUrl;
  final bool isTv;
  final int season;
  final int episode;
  final String userAgent;

  const InternalPlayerScreen({
    super.key,
    required this.videoUrl,
    required this.title,
    this.tmdbId = '',
    this.tmdbKey = '',
    this.gistUrl = '',
    this.isTv = false,
    this.season = 1,
    this.episode = 1,
    this.userAgent = 'VLC/3.0.18 LibVLC/3.0.18 (Linux; Android 13)',
  });

  @override
  State<InternalPlayerScreen> createState() => _InternalPlayerScreenState();
}

class _InternalPlayerScreenState extends State<InternalPlayerScreen> {
  static const MethodChannel _exoChannel = MethodChannel('com.primeflix/media3');

  bool _isLaunching = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _launchExoPlayer();
  }

  Future<void> _launchExoPlayer() async {
    final cleanUrl = widget.videoUrl.trim();
    final cleanTitle = widget.title.trim().isEmpty ? 'Primeflix' : widget.title.trim();

    if (cleanUrl.isEmpty && widget.tmdbId.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _isLaunching = false;
          _errorMessage = 'ExoPlayer stream URL या TMDB ID उपलब्ध नहीं है।';
        });
      }
      return;
    }

    setState(() {
      _isLaunching = true;
      _errorMessage = null;
    });

    try {
      final result = await _exoChannel.invokeMethod<bool>('playMedia', {
        'url': cleanUrl,
        'title': cleanTitle,
        'tmdbId': widget.tmdbId.trim(),
        'tmdbKey': widget.tmdbKey.trim(),
        'gistUrl': widget.gistUrl.trim(),
        'isTv': widget.isTv,
        'season': widget.season,
        'episode': widget.episode,
        'userAgent': widget.userAgent.trim().isEmpty
            ? 'VLC/3.0.18 LibVLC/3.0.18 (Linux; Android 13)'
            : widget.userAgent.trim(),
      });

      if (!mounted) return;

      if (result == true) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _isLaunching = false;
          _errorMessage = 'ExoPlayer activity शुरू नहीं हो सकी।';
        });
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLaunching = false;
        _errorMessage = 'ExoPlayer error: ${e.message ?? e.code}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLaunching = false;
        _errorMessage = 'ExoPlayer launch failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _isLaunching
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Color(0xFFE50914)),
                  const SizedBox(height: 14),
                  Text(
                    'Opening ExoPlayer...',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _errorMessage ?? 'ExoPlayer open nahi ho paya.',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: _launchExoPlayer,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE50914),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Retry ExoPlayer'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                          ),
                          child: const Text('Back'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}