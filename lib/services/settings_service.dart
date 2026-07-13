// lib/services/settings_service.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static final SettingsService _instance = SettingsService._internal();
  static SettingsService get instance => _instance;

  SettingsService._internal() {
    _loadSettings();
  }

  SharedPreferences? _prefs;
  Timer? _autoThemeTimer;

  // Default values
  String _themeModeString = 'system';
  Color _accentColor = const Color(0xFF9C27B0);
  String _fontSize = 'normal';
  bool _soundEnabled = true;
  bool _hapticEnabled = true;
  bool _goalBannerEnabled = true;
  String _wheelSpeed = 'normal';
  bool _reducedMotion = false;
  bool _highContrast = false;
  bool _colorBlindMode = false;
  bool _distractionFreeMode = false;
  String _childAvatar = '👤';
  double _pointsPerVerify = 1.0;
  double _pointsPerCorrect = 0.5;

  // Getters
  String get themeModeString => _themeModeString;

  ThemeMode get effectiveThemeMode {
    if (_themeModeString == 'auto') {
      final hour = DateTime.now().hour;
      return (hour >= 6 && hour < 18) ? ThemeMode.light : ThemeMode.dark;
    }
    return _parseThemeMode(_themeModeString);
  }

  Color get accentColor => _accentColor;
  String get fontSize => _fontSize;
  double get fontScale {
    switch (_fontSize) {
      case 'large':
        return 1.15;
      case 'extra_large':
        return 1.3;
      default:
        return 1.0;
    }
  }

  bool get soundEnabled => _soundEnabled;
  bool get hapticEnabled => _hapticEnabled;
  bool get goalBannerEnabled => _goalBannerEnabled;
  String get wheelSpeed => _wheelSpeed;
  bool get reducedMotion => _reducedMotion;
  bool get highContrast => _highContrast;
  bool get colorBlindMode => _colorBlindMode;
  bool get distractionFreeMode => _distractionFreeMode;
  String get childAvatar => _childAvatar;
  double get pointsPerVerify => _pointsPerVerify;
  double get pointsPerCorrect => _pointsPerCorrect;

  ThemeData get themeData {
    final scheme = ColorScheme.fromSeed(
      seedColor: _accentColor,
      brightness: Brightness.light,
      contrastLevel: _highContrast ? 1.0 : 0.0,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _highContrast ? Colors.white : const Color(0xFFF8F9FA),
      fontFamily: 'Roboto',
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  ThemeData get darkThemeData {
    final scheme = ColorScheme.fromSeed(
      seedColor: _accentColor,
      brightness: Brightness.dark,
      contrastLevel: _highContrast ? 1.0 : 0.0,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _highContrast ? Colors.black : const Color(0xFF121212),
      fontFamily: 'Roboto',
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade700),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade700),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade900,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    _themeModeString = _prefs?.getString('theme_mode') ?? 'system';
    _accentColor = Color(_prefs?.getInt('accent_color') ?? const Color(0xFF9C27B0).value);
    _fontSize = _prefs?.getString('font_size') ?? 'normal';
    _soundEnabled = _prefs?.getBool('sound_enabled') ?? true;
    _hapticEnabled = _prefs?.getBool('haptic_enabled') ?? true;
    _goalBannerEnabled = _prefs?.getBool('goal_banner_enabled') ?? true;
    _wheelSpeed = _prefs?.getString('wheel_speed') ?? 'normal';
    _reducedMotion = _prefs?.getBool('reduced_motion') ?? false;
    _highContrast = _prefs?.getBool('high_contrast') ?? false;
    _colorBlindMode = _prefs?.getBool('color_blind_mode') ?? false;
    _distractionFreeMode = _prefs?.getBool('distraction_free_mode') ?? false;
    _childAvatar = _prefs?.getString('child_avatar') ?? '👤';
    _pointsPerVerify = _prefs?.getDouble('points_per_verify') ?? 1.0;
    _pointsPerCorrect = _prefs?.getDouble('points_per_correct') ?? 0.5;
    _manageAutoThemeTimer();
    notifyListeners();
  }

  Future<void> _save() async {
    if (_prefs == null) return;
    await _prefs!.setString('theme_mode', _themeModeString);
    await _prefs!.setInt('accent_color', _accentColor.value);
    await _prefs!.setString('font_size', _fontSize);
    await _prefs!.setBool('sound_enabled', _soundEnabled);
    await _prefs!.setBool('haptic_enabled', _hapticEnabled);
    await _prefs!.setBool('goal_banner_enabled', _goalBannerEnabled);
    await _prefs!.setString('wheel_speed', _wheelSpeed);
    await _prefs!.setBool('reduced_motion', _reducedMotion);
    await _prefs!.setBool('high_contrast', _highContrast);
    await _prefs!.setBool('color_blind_mode', _colorBlindMode);
    await _prefs!.setBool('distraction_free_mode', _distractionFreeMode);
    await _prefs!.setString('child_avatar', _childAvatar);
    await _prefs!.setDouble('points_per_verify', _pointsPerVerify);
    await _prefs!.setDouble('points_per_correct', _pointsPerCorrect);
    notifyListeners();
  }

  set themeModeString(String value) {
    _themeModeString = value;
    _manageAutoThemeTimer();
    _save();
  }

  set accentColor(Color value) { _accentColor = value; _save(); }
  set fontSize(String value) { _fontSize = value; _save(); }
  set soundEnabled(bool value) { _soundEnabled = value; _save(); }
  set hapticEnabled(bool value) { _hapticEnabled = value; _save(); }
  set goalBannerEnabled(bool value) { _goalBannerEnabled = value; _save(); }
  set wheelSpeed(String value) { _wheelSpeed = value; _save(); }
  set reducedMotion(bool value) { _reducedMotion = value; _save(); }
  set highContrast(bool value) { _highContrast = value; _save(); }
  set colorBlindMode(bool value) { _colorBlindMode = value; _save(); }
  set distractionFreeMode(bool value) { _distractionFreeMode = value; _save(); }
  set childAvatar(String value) { _childAvatar = value; _save(); }
  set pointsPerVerify(double value) { _pointsPerVerify = value; _save(); }
  set pointsPerCorrect(double value) { _pointsPerCorrect = value; _save(); }

  void _manageAutoThemeTimer() {
    _autoThemeTimer?.cancel();
    if (_themeModeString == 'auto') {
      _autoThemeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        notifyListeners();
      });
    }
  }

  ThemeMode _parseThemeMode(String value) {
    switch (value) {
      case 'light': return ThemeMode.light;
      case 'dark': return ThemeMode.dark;
      default: return ThemeMode.system;
    }
  }

  static const List<Map<String, dynamic>> presetColors = [
    {'name': 'Ocean Blue', 'color': Color(0xFF2196F3)},
    {'name': 'Forest Green', 'color': Color(0xFF4CAF50)},
    {'name': 'Royal Purple', 'color': Color(0xFF9C27B0)},
    {'name': 'Sunset Orange', 'color': Color(0xFFFF9800)},
    {'name': 'Golden Yellow', 'color': Color(0xFFFFC107)},
    {'name': 'Bubblegum Pink', 'color': Color(0xFFE91E63)},
    {'name': 'Teal Cyan', 'color': Color(0xFF009688)},
    {'name': 'Coral Red', 'color': Color(0xFFF44336)},
    {'name': 'Deep Indigo', 'color': Color(0xFF3F51B5)},
    {'name': 'Mint Green', 'color': Color(0xFF00E676)},
  ];

  static const List<String> presetAvatars = [
    '👤', '🦁', '🐯', '🐻', '🐼', '🐨', '🐸', '🐙', '🦄', '🦊', '🐰', '🐱'
  ];
}