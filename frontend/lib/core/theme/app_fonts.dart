import 'dart:ui' show FontFeature, Locale, Shadow;

import 'package:flutter/material.dart' show TextTheme;
import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

/// Bleiben type system (bleiben-calm-stays reference):
/// * Body / UI text: DM Sans.
/// * Headings (20px and up): Manrope 500–600 with tight negative tracking.
/// * Italic accents ("In harmony."): Instrument Serif italic.
///
/// [sans] and [display] mirror the GoogleFonts call signature so call sites
/// only change the function name.
class AppFonts {
  AppFonts._();

  /// Size at which UI text switches to the heading face.
  static const double headingFrom = 20;

  static TextStyle sans({
    TextStyle? textStyle,
    Color? color,
    Color? backgroundColor,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    TextBaseline? textBaseline,
    double? height,
    Locale? locale,
    Paint? foreground,
    Paint? background,
    List<Shadow>? shadows,
    List<FontFeature>? fontFeatures,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
  }) {
    final size = fontSize ?? textStyle?.fontSize;
    if (size != null && size >= headingFrom && fontStyle != FontStyle.italic) {
      return display(
        textStyle: textStyle,
        color: color,
        backgroundColor: backgroundColor,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        wordSpacing: wordSpacing,
        textBaseline: textBaseline,
        height: height,
        locale: locale,
        foreground: foreground,
        background: background,
        shadows: shadows,
        fontFeatures: fontFeatures,
        decoration: decoration,
        decorationColor: decorationColor,
        decorationStyle: decorationStyle,
        decorationThickness: decorationThickness,
      );
    }
    return GoogleFonts.dmSans(
      textStyle: textStyle,
      color: color,
      backgroundColor: backgroundColor,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      textBaseline: textBaseline,
      height: height,
      locale: locale,
      foreground: foreground,
      background: background,
      shadows: shadows,
      fontFeatures: fontFeatures,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationStyle: decorationStyle,
      decorationThickness: decorationThickness,
    );
  }

  /// Headings: Manrope with tight tracking; italic → Instrument Serif accent.
  static TextStyle display({
    TextStyle? textStyle,
    Color? color,
    Color? backgroundColor,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    TextBaseline? textBaseline,
    double? height,
    Locale? locale,
    Paint? foreground,
    Paint? background,
    List<Shadow>? shadows,
    List<FontFeature>? fontFeatures,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
  }) {
    final size = fontSize ?? textStyle?.fontSize ?? 24;
    if (fontStyle == FontStyle.italic) {
      return GoogleFonts.instrumentSerif(
        textStyle: textStyle,
        color: color,
        backgroundColor: backgroundColor,
        fontSize: fontSize == null ? null : fontSize * 1.08,
        fontWeight: FontWeight.w400,
        fontStyle: FontStyle.italic,
        letterSpacing: letterSpacing ?? -size * 0.03,
        height: height,
        shadows: shadows,
        decoration: decoration,
        decorationColor: decorationColor,
      );
    }
    // The reference uses medium weights for headlines; keep bold UI labels a
    // touch heavier but never as heavy as before.
    final weight = switch (fontWeight) {
      FontWeight.w800 || FontWeight.w900 || FontWeight.w700 => FontWeight.w600,
      null => FontWeight.w500,
      _ => fontWeight,
    };
    return GoogleFonts.manrope(
      textStyle: textStyle,
      color: color,
      backgroundColor: backgroundColor,
      fontSize: fontSize,
      fontWeight: weight,
      letterSpacing: letterSpacing ?? -size * (size >= 40 ? 0.05 : 0.035),
      wordSpacing: wordSpacing,
      textBaseline: textBaseline,
      height: height,
      locale: locale,
      foreground: foreground,
      background: background,
      shadows: shadows,
      fontFeatures: fontFeatures,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationStyle: decorationStyle,
      decorationThickness: decorationThickness,
    );
  }

  static TextTheme textTheme(TextTheme base) {
    final body = GoogleFonts.dmSansTextTheme(base);
    TextStyle? head(TextStyle? s) => s == null ? null : display(textStyle: s);
    return body.copyWith(
      displayLarge: head(base.displayLarge),
      displayMedium: head(base.displayMedium),
      displaySmall: head(base.displaySmall),
      headlineLarge: head(base.headlineLarge),
      headlineMedium: head(base.headlineMedium),
      headlineSmall: head(base.headlineSmall),
      titleLarge: head(base.titleLarge),
    );
  }
}
