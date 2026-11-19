import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_fonts.dart';
import '../theme/app_theme.dart';

/// Distinct slice colours for donut charts (dashboard, expenses).
const chartPalette = [
  Color(0xFF00A699), // teal
  Color(0xFFE8452C), // red
  Color(0xFFF2994A), // orange
  Color(0xFF6C4CD8), // purple
  Color(0xFF3F7DD8), // blue
  Color(0xFF4CAF7A), // green
  Color(0xFFE9B949), // yellow
  Color(0xFFE06AA6), // pink
  Color(0xFF9AA0A6), // grey (other)
];

class DonutSlice {
  const DonutSlice(this.label, this.value, {this.color});

  final String label;
  final double value;
  final Color? color;
}

/// A donut with a total in the middle and a legend with each share.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    required this.centerValue,
    required this.centerLabel,
    this.size = 150,
    this.maxLegend = 7,
    this.showLegend = true,
  });

  final List<DonutSlice> slices;
  final String centerValue;
  final String centerLabel;
  final double size;
  final int maxLegend;
  final bool showLegend;

  /// Slice colour by position (keeps chart, legend and tables in step).
  static Color colorAt(int i) => chartPalette[i % (chartPalette.length - 1)];

  List<DonutSlice> get _shown {
    final list = [for (final (i, s) in slices.where((s) => s.value > 0).indexed) DonutSlice(s.label, s.value, color: s.color ?? colorAt(i))];
    if (list.length <= maxLegend) return list;
    final head = list.take(maxLegend - 1).toList();
    final rest = list.skip(maxLegend - 1).toList();
    return [
      ...head,
      DonutSlice('Other ${rest.length} ${rest.length == 1 ? 'item' : 'items'}', rest.fold(0.0, (s, x) => s + x.value), color: chartPalette.last),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final total = shown.fold(0.0, (s, x) => s + x.value);
    String pct(double v) {
      if (total <= 0) return '0%';
      final p = v / total * 100;
      return p > 0 && p < 1 ? '<1%' : '${p.round()}%';
    }

    final donut = SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(size: Size.square(size), painter: _DonutPainter(shown, total)),
        Padding(
          padding: EdgeInsets.all(size * 0.2),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FittedBox(child: Text(centerValue, style: AppFonts.sans(fontSize: 20, fontWeight: FontWeight.w700))),
            Text(centerLabel, style: AppFonts.sans(fontSize: 11.5, color: AppTheme.muted)),
          ]),
        ),
      ]),
    );
    if (!showLegend) return donut;
    final legend = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (final s in shown)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Expanded(child: Text(s.label, overflow: TextOverflow.ellipsis, style: AppFonts.sans(fontSize: 13))),
            Text(pct(s.value), style: AppFonts.sans(fontSize: 13, color: AppTheme.muted)),
          ]),
        ),
    ]);
    // No LayoutBuilder: charts sit inside IntrinsicHeight rows on the dashboard.
    if (MediaQuery.sizeOf(context).width < 520) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Center(child: donut), const SizedBox(height: 12), legend]);
    }
    return Row(children: [donut, const SizedBox(width: 20), Expanded(child: legend)]);
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices, this.total);

  final List<DonutSlice> slices;
  final double total;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.16;
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    if (total <= 0) {
      canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = AppTheme.sage);
      return;
    }
    var start = -math.pi / 2;
    final gap = slices.length > 1 ? 0.025 : 0.0;
    for (final s in slices) {
      final sweep = s.value / total * math.pi * 2;
      canvas.drawArc(rect, start + gap / 2, math.max(0.001, sweep - gap), false, paint..color = s.color!);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.slices != slices || old.total != total;
}
