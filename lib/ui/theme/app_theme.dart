import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light & Dark monochrome theme colors faithful to FluxOrigin's literary paper aesthetic.
class AppColors {
  // Light Mode (Literary Paper & Forest Ink)
  static const Color lightPrimary = Color(0xFF043222);
  static const Color lightAccent = Color(0xFF13503D);
  static const Color lightPaper = Color(0xFFFDFCF8);
  static const Color lightSidebar = Color(0xFFF4F2ED);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE6E4DC);

  // Dark Mode (High-Contrast Ink Obsidian)
  static const Color darkPaper = Color(0xFF111111);
  static const Color darkSidebar = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF1A1A1A);
  static const Color darkBorder = Color(0xFF2A2A2A);
}

/// Theme notifier to persist and toggle Dark / Light mode.
class ThemeNotifier extends ChangeNotifier {
  static const String _darkModeKey = 'is_dark_mode';
  bool _isDark = false;

  ThemeNotifier() {
    _loadTheme();
  }

  bool get isDark => _isDark;

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_darkModeKey);
      if (saved != null && saved != _isDark) {
        _isDark = saved;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> toggleTheme() async {
    _isDark = !_isDark;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_darkModeKey, _isDark);
    } catch (_) {}
  }

  ThemeData get currentTheme => _isDark ? darkTheme : lightTheme;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightPaper,
      primaryColor: AppColors.lightPrimary,
      colorScheme: const ColorScheme.light(
        primary: AppColors.lightPrimary,
        secondary: AppColors.lightAccent,
        surface: AppColors.lightSurface,
      ),
      textTheme: GoogleFonts.interTextTheme().copyWith(
        bodyLarge: GoogleFonts.inter(color: AppColors.lightPrimary),
        bodyMedium: GoogleFonts.inter(color: AppColors.lightPrimary),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkPaper,
      primaryColor: Colors.white,
      colorScheme: const ColorScheme.dark(
        primary: Colors.white,
        secondary: Colors.white70,
        surface: AppColors.darkSurface,
      ),
      textTheme:
          GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
        bodyLarge: GoogleFonts.inter(color: Colors.white),
        bodyMedium: GoogleFonts.inter(color: Colors.grey[300]),
      ),
    );
  }
}
