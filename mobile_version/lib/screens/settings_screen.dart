import 'package:flutter/material.dart';
import '../services/app_settings_service.dart';
import '../services/stalker_service.dart';
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

  // Direct Xtream Controllers
  final _xtreamUrlController = TextEditingController();
  final _xtreamUserController = TextEditingController();
  final _xtreamPassController = TextEditingController();

  // Direct Stalker Controllers
  final _stalkerUrlController = TextEditingController();
  final _stalkerMacController = TextEditingController();
  final _stalkerDev1Controller = TextEditingController();
  final _stalkerDev2Controller = TextEditingController();

  int _seekSeconds = 15;
  int _providerCount = 0;
  bool _isSaving = false;
  bool _obscureKey = true;
  bool _obscureXtreamPass = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    final gist = await AppSettingsService.getGistUrl();
    final tmdb = await AppSettingsService.getTmdbApiKey();
    final seek = await AppSettingsService.getSeekSeconds();
    final xtream = await AppSettingsService.getDirectXtream();
    final stalker = await AppSettingsService.getDirectStalker();
    final providers = await StreamService.loadProviders();

    if (!mounted) return;
    setState(() {
      _gistController.text = gist;
      _tmdbController.text = tmdb;
      _seekSeconds = seek;
      _xtreamUrlController.text = xtream['url'] ?? '';
      _xtreamUserController.text = xtream['username'] ?? '';
      _xtreamPassController.text = xtream['password'] ?? '';
      _stalkerUrlController.text = stalker['url'] ?? '';
      _stalkerMacController.text = stalker['mac'] ?? '';
      _stalkerDev1Controller.text = stalker['device_id1'] ?? '';
      _stalkerDev2Controller.text = stalker['device_id2'] ?? '';
      _providerCount = providers.length;
    });
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    await AppSettingsService.setTmdbApiKey(_tmdbController.text);
    await AppSettingsService.setSeekSeconds(_seekSeconds);
    await AppSettingsService.setDirectXtream(
      url: _xtreamUrlController.text,
      username: _xtreamUserController.text,
      password: _xtreamPassController.text,
    );
    await AppSettingsService.setDirectStalker(
      url: _stalkerUrlController.text,
      mac: _stalkerMacController.text,
      deviceId1: _stalkerDev1Controller.text,
      deviceId2: _stalkerDev2Controller.text,
    );

    String stalkerStatus = '';
    if (_stalkerUrlController.text.trim().isNotEmpty &&
        _stalkerMacController.text.trim().isNotEmpty) {
      final auth = await StalkerService.authenticate(
        portalUrl: _stalkerUrlController.text,
        mac: _stalkerMacController.text,
        deviceId1: _stalkerDev1Controller.text,
        deviceId2: _stalkerDev2Controller.text,
      );
      stalkerStatus =
          auth != null ? ' • Stalker Connected ✓' : ' • Stalker Auth Failed';
    }

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
              ? 'Saved! $count Active Servers$stalkerStatus'
              : 'Settings saved! URL / Credentials check karein.',
        ),
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 13.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
        filled: true,
        fillColor: _darkBg,
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _gistController.dispose();
    _tmdbController.dispose();
    _xtreamUrlController.dispose();
    _xtreamUserController.dispose();
    _xtreamPassController.dispose();
    _stalkerUrlController.dispose();
    _stalkerMacController.dispose();
    _stalkerDev1Controller.dispose();
    _stalkerDev2Controller.dispose();
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
          // 1. Gist / Playlist URL
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
                  'Gist mein Stremio, Xtream aur Stalker teeno ek saath rakh sakte hain:',
                  style: TextStyle(color: Colors.white60, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                _buildInput(
                  controller: _gistController,
                  hint: 'https://gist.githubusercontent.com/.../raw/...',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Direct Xtream IPTV Login
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
                    const Icon(Icons.live_tv_rounded, color: _primeBlue),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Xtream Codes IPTV (Direct)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (_xtreamUrlController.text.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _xtreamUrlController.clear();
                            _xtreamUserController.clear();
                            _xtreamPassController.clear();
                          });
                        },
                        child: const Text(
                          'Clear',
                          style: TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Direct Xtream server URL, Username aur Password dalein:',
                  style: TextStyle(color: Colors.white60, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                _buildInput(
                  controller: _xtreamUrlController,
                  hint: 'Server URL (e.g. http://example.com:8080)',
                ),
                const SizedBox(height: 10),
                _buildInput(
                  controller: _xtreamUserController,
                  hint: 'Username',
                ),
                const SizedBox(height: 10),
                _buildInput(
                  controller: _xtreamPassController,
                  hint: 'Password',
                  obscure: _obscureXtreamPass,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureXtreamPass ? Icons.visibility : Icons.visibility_off,
                      color: Colors.white54,
                    ),
                    onPressed: () =>
                        setState(() => _obscureXtreamPass = !_obscureXtreamPass),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Direct Stalker Portal (MAC + Device ID 1 & 2)
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
                    const Icon(Icons.router_rounded, color: _primeBlue),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Stalker Portal (MAC & Device ID)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (_stalkerUrlController.text.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _stalkerUrlController.clear();
                            _stalkerMacController.clear();
                            _stalkerDev1Controller.clear();
                            _stalkerDev2Controller.clear();
                          });
                        },
                        child: const Text(
                          'Clear',
                          style: TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Stalker Portal URL, MAC Address, Device ID 1 aur Device ID 2 dalein:',
                  style: TextStyle(color: Colors.white60, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                _buildInput(
                  controller: _stalkerUrlController,
                  hint: 'Portal URL (e.g. http://portal.example.com/c)',
                ),
                const SizedBox(height: 10),
                _buildInput(
                  controller: _stalkerMacController,
                  hint: 'MAC Address (e.g. 00:1A:79:XX:XX:XX)',
                ),
                const SizedBox(height: 10),
                _buildInput(
                  controller: _stalkerDev1Controller,
                  hint: 'Device ID 1 (Optional)',
                ),
                const SizedBox(height: 10),
                _buildInput(
                  controller: _stalkerDev2Controller,
                  hint: 'Device ID 2 (Optional)',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. TMDB API Key
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
                _buildInput(
                  controller: _tmdbController,
                  hint: 'Enter TMDB v3 API Key',
                  obscure: _obscureKey,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureKey ? Icons.visibility : Icons.visibility_off,
                      color: Colors.white54,
                    ),
                    onPressed: () => setState(() => _obscureKey = !_obscureKey),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 5. Seek Step
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}