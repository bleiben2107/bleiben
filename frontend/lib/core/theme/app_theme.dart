import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color forest = Color(0xFF1F4D3A);
  static const Color moss = Color(0xFF3E7A5E);
  static const Color cream = Color(0xFFF6F1E7);
  static const Color clay = Color(0xFFC46B4A);
  static const Color ink = Color(0xFF1C241F);

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: forest,
        primary: forest,
        secondary: clay,
        surface: cream,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: cream,
    );
    return base.copyWith(
      textTheme: GoogleFonts.outfitTextTheme(base.textTheme).apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: cream,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.fraunces(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: forest,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
