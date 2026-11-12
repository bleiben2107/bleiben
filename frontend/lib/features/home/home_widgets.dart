import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:bleiben/core/theme/app_fonts.dart';

import '../../core/theme/app_theme.dart';

/// Breakpoints and spacing shared by every homepage section.
class HomeLayout {
  static const double maxWidth = 1200;

  static double width(BuildContext context) => MediaQuery.sizeOf(context).width;
  static bool isWide(BuildContext context) => width(context) >= 980;
  static bool isMedium(BuildContext context) => width(context) >= 640;
  static double gutter(BuildContext context) => isMedium(context) ? 32 : 18;
}

/// Neutral palette used alongside [AppTheme] on the marketing pages.
class HomeColors {
  /// Card surface (white on the paper page background).
  static const Color paper = Colors.white;

  /// Soft sage tint for chips, inputs and highlighted rows.
  static const Color mist = Color(0xFFEDF0E5);
  static const Color line = Color(0xFFDFE3D8);
  static const Color muted = Color(0xFF6A7369);

  /// Dark sections (offer bar, CTA band): deep forest.
  static const Color night = Color(0xFF173A2D);
  static const Color danger = Color(0xFFC0503A);
  static const Color success = Color(0xFF4E8A4F);
}

/// Full-width band with a centred, width-capped content column.
class SectionShell extends StatelessWidget {
  const SectionShell({
    super.key,
    required this.child,
    this.background = HomeColors.paper,
    this.gradient,
    this.vertical = 96,
  });

  final Widget child;
  final Color background;
  final Gradient? gradient;
  final double vertical;

  @override
  Widget build(BuildContext context) {
    final medium = HomeLayout.isMedium(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: background, gradient: gradient),
      padding: EdgeInsets.symmetric(
        horizontal: HomeLayout.gutter(context),
        vertical: medium ? vertical : vertical * 0.6,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: HomeLayout.maxWidth),
          child: child,
        ),
      ),
    );
  }
}

/// Small uppercase label shown above section headlines.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color = AppTheme.clay});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('✳', style: AppFonts.sans(fontSize: 18, color: color, height: 1)),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text.toUpperCase(),
            style: AppFonts.sans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.4,
              color: color == AppTheme.clay ? AppTheme.ink : color,
            ),
          ),
        ),
      ],
    );
  }
}

/// Bold sans headline with an italic serif accent phrase.
class AccentHeadline extends StatelessWidget {
  const AccentHeadline({
    super.key,
    required this.lead,
    required this.accent,
    this.trail = '',
    this.size = 44,
    this.align = TextAlign.start,
    this.dark = false,
    this.accentColor = AppTheme.clay,
  });

  final String lead;
  final String accent;
  final String trail;
  final double size;
  final TextAlign align;
  final bool dark;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final scale = HomeLayout.isMedium(context) ? 1.0 : 0.66;
    final fontSize = size * scale;
    final base = AppFonts.display(
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      height: 1.1,
      color: dark ? Colors.white : AppTheme.ink,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: lead, style: base),
          TextSpan(
            text: accent,
            style: AppFonts.display(
              fontSize: fontSize,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
              height: 1.12,
              color: accentColor,
            ),
          ),
          if (trail.isNotEmpty) TextSpan(text: trail, style: base),
        ],
      ),
      textAlign: align,
    );
  }
}

/// Eyebrow + headline + supporting paragraph.
class SectionIntro extends StatelessWidget {
  const SectionIntro({
    super.key,
    required this.eyebrow,
    required this.lead,
    required this.accent,
    this.trail = '',
    this.subtitle,
    this.centered = true,
    this.dark = false,
  });

  final String eyebrow;
  final String lead;
  final String accent;
  final String trail;
  final String? subtitle;
  final bool centered;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final align = centered ? TextAlign.center : TextAlign.start;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Column(
        crossAxisAlignment:
            centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Eyebrow(eyebrow),
          const SizedBox(height: 16),
          AccentHeadline(
            lead: lead,
            accent: accent,
            trail: trail,
            align: align,
            dark: dark,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 16),
            Text(
              subtitle!,
              textAlign: align,
              style: AppFonts.sans(
                fontSize: 16.5,
                height: 1.75,
                color: dark ? Colors.white70 : HomeColors.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Rounded call-to-action button used across the page.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = true,
    this.icon,
    this.dense = false,
    this.background = AppTheme.forest,
    this.foreground = Colors.white,
  });

  final String label;
  final VoidCallback onPressed;
  final bool filled;
  final IconData? icon;
  final bool dense;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.symmetric(
      horizontal: dense ? 18 : 26,
      vertical: dense ? 12 : 18,
    );
    final textStyle = AppFonts.sans(
      fontSize: dense ? 14 : 15.5,
      fontWeight: FontWeight.w500,
    );
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        if (icon != null) ...[
          const SizedBox(width: 8),
          Icon(icon, size: dense ? 16 : 18),
        ],
      ],
    );
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusButton));
    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          padding: padding,
          shape: shape,
          textStyle: textStyle,
          minimumSize: Size.zero,
        ),
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: background,
        side: BorderSide(color: background.withValues(alpha: 0.35)),
        padding: padding,
        shape: shape,
        textStyle: textStyle,
        minimumSize: Size.zero,
      ),
      child: child,
    );
  }
}

/// White card with a hairline border and soft shadow.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color = HomeColors.paper,
    this.radius = AppTheme.radiusCard,
    this.borderColor = HomeColors.line,
    this.elevated = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radius;
  final Color borderColor;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: AppTheme.ink.withValues(alpha: 0.08),
                  blurRadius: 38,
                  offset: const Offset(0, 24),
                ),
              ]
            : null,
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// Icon + text row used for feature bullets.
class BulletLine extends StatelessWidget {
  const BulletLine(
    this.text, {
    super.key,
    this.icon = Icons.check_rounded,
    this.iconColor = AppTheme.forest,
    this.textColor = AppTheme.ink,
  });

  final String text;
  final IconData icon;
  final Color iconColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: AppFonts.sans(
                fontSize: 15.5,
                height: 1.45,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tinted rounded square holding an icon.
class IconBadge extends StatelessWidget {
  const IconBadge(
    this.icon, {
    super.key,
    this.color = AppTheme.forest,
    this.size = 44,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// Lays children out in equal-width columns that collapse on narrow screens.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 260,
    this.maxColumns = 3,
    this.spacing = 20,
  });

  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fit = ((width + spacing) / (minItemWidth + spacing)).floor();
        final columns = math.max(1, math.min(maxColumns, fit));
        final itemWidth = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

/// Gives a fixed-size mockup horizontal scrolling when the screen is narrower.
class MinWidthScroll extends StatelessWidget {
  const MinWidthScroll(
      {super.key, required this.minWidth, required this.child});

  final double minWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= minWidth) return child;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: minWidth, child: child),
        );
      },
    );
  }
}
