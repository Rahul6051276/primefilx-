import 'package:flutter/material.dart';
import '../services/app_settings_service.dart';
import '../services/stream_service.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onSettingsUpdated;

  const SettingsScreen({super.key, this.onSettingsUpdated});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Color _primeBlue = Color(0xFF00A8E1);
  static const Color _darkBg = Color(0xFF0B1118);
  static const Color _cardBg = Color(0xFF15202B);

  final _gistController = TextEditingController();
  final _tmdbController = TextEditingController();

  int _seekSeconds = 15;
  int _providerCount = 0;
  bool _isSaving = false;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    final gist = await AppSettingsService.getGistUrl();
    final tmdb = await AppSettingsService.getTmdbApiKey();
    final seek = await AppSettingsService.getSeekSeconds();
    final providers = await StreamService.loadProviders();

    if (!mounted) return;
    setState(() {
      _gistController.text = gist;
      _tmdbController.text = tmdb;
      _seekSeconds = seek;
      _providerCount = providers.length;
    });
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    await AppSettingsService.setTmdbApiKey(_tmdbController.text);
    await AppSettingsService.setSeekSeconds(_seekSeconds);
    final count = await StreamService.saveAndConnectGistUrl(_gistController.text);

    if (!mounted) return;
    setState(() {
      _providerCount = count;
      _isSaving = false;
    });

    widget.onSettingsUpdated?.call();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: count > 0 ? Colors.green.shade700 : _cardBg,
        content: Text(
          count > 0
              ? 'Settings saved! $count stream providers connected.'
              : 'Settings saved! Gist URL / TMDB Key check karein.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _gistController.dispose();
    _tmdbController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkBg,
      appBar: AppBar(
        backgroundColor: _darkBg,
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.link, color: _primeBlue),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'External Gist / Playlist URL',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _providerCount > 0
                            ? Colors.green.withOpacity(0.2)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$_providerCount Active',
                        style: TextStyle(
                          color: _providerCount > 0
                              ? Colors.greenAccent
                              : Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Koi hardcoded URL andar nahi hai. Apna raw Gist URL yahan paste karein:',
                  style: TextStyle(color: Colors.white60, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _gistController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'https://gist.githubusercontent.com/.../raw/...',
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: _darkBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.movie_filter, color: _primeBlue),
                    SizedBox(width: 8),
                    Text(
                      'TMDB API Key',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Posters, trending movies, web series aur search ke liye apni TMDB API Key dalein:',
                  style: TextStyle(color: Colors.white60, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tmdbController,
                  obscureText: _obscureKey,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Enter TMDB v3 API Key',
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: _darkBg,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureKey ? Icons.visibility : Icons.visibility_off,
                        color: Colors.white54,
                      ),
                      onPressed: () => setState(() => _obscureKey = !_obscureKey),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.fast_forward, color: _primeBlue),
                    SizedBox(width: 8),
                    Text(
                      'Cinema Player Seek Step',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  children: [10, 15, 30].map((sec) {
                    final selected = _seekSeconds == sec;
                    return ChoiceChip(
                      label: Text('${sec}s'),
                      selected: selected,
                      selectedColor: _primeBlue,
                      backgroundColor: _darkBg,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (_) => setState(() => _seekSeconds = sec),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primeBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _isSaving ? null : _saveSettings,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: const Text(
                'Save & Connect',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}