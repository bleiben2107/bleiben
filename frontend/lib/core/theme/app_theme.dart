import 'package:flutter/material.dart';

import 'app_fonts.dart';

/// Bleiben "calm stays" palette (bleiben-calm-stays reference site).
/// Existing names are kept so every screen picks up the new look.
class AppTheme {
  /// Primary — buttons, logo mark, offer bar (`--forest`).
  static const Color forest = Color(0xFF1B4435);

  /// Secondary green for accents and charts.
  static const Color moss = Color(0xFF6C965D);

  /// Page background (`--paper`).
  static const Color cream = Color(0xFFF8F7F2);
  static const Color paper = cream;

  /// Warm accent — italic headline words, asterisks, highlights (`--terra`).
  static const Color clay = Color(0xFFBC7457);
  static const Color terra = clay;

  /// Text colour (`--ink`).
  static const Color ink = Color(0xFF203C31);

  /// Soft tinted surfaces (`--sage`) and hairlines (`--border`).
  static const Color sage = Color(0xFFE6EBDF);
  static const Color sand = Color(0xFFF1E9DF);
  static const Color border = Color(0xFFDEDFD4);
  static const Color borderStrong = Color(0xFFC9CEC0);
  static const Color muted = Color(0xFF6A7369);

  /// Placeholder / disabled text.
  static const Color hint = Color(0xFF9AA396);

  /// Slightly lighter ink for secondary headings.
  static const Color inkSoft = Color(0xFF34503F);

  // Status colours, toned to the palette.
  static const Color success = Color(0xFF4E8A4F);
  static const Color successSoft = Color(0xFFE3EDDC);
  static const Color danger = Color(0xFFB4483A);
  static const Color dangerSoft = Color(0xFFF6E3DE);
  static const Color warningSoft = Color(0xFFF4E8D6);
  static const Color warningInk = Color(0xFF7A5524);

  static const double radiusButton = 8;
  static const double radiusCard = 14;
  static const double radiusField = 10;

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: forest,
        primary: forest,
        onPrimary: const Color(0xFFFFFEF7),
        secondary: terra,
        surface: paper,
        outline: border,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: paper,
      dividerColor: border,
    );
    final buttonText = AppFonts.sans(fontWeight: FontWeight.w500, fontSize: 15);
    return base.copyWith(
      textTheme: AppFonts.textTheme(base.textTheme).apply(bodyColor: ink, displayColor: ink),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppFonts.display(fontSize: 24, fontWeight: FontWeight.w600, color: ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: const BorderSide(color: forest, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: forest,
          foregroundColor: const Color(0xFFFFFEF7),
          elevation: 0,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusButton)),
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusButton)),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: forest, textStyle: buttonText),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: const BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard)),
        titleTextStyle: AppFonts.display(fontSize: 22, fontWeight: FontWeight.w600, color: ink),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: forest,
        contentTextStyle: AppFonts.sans(color: const Color(0xFFFFFEF7)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusButton)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: forest,
        unselectedLabelColor: muted,
        indicatorColor: terra,
        labelStyle: AppFonts.sans(fontWeight: FontWeight.w600, fontSize: 14.5),
        unselectedLabelStyle: AppFonts.sans(fontSize: 14.5),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: sage,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusButton)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: forest),
    );
  }
}
