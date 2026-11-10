import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import 'home_widgets.dart';

/// A booking channel shown in the product mockups.
class Channel {
  const Channel(this.name, this.color, this.icon);

  final String name;
  final Color color;
  final IconData icon;
}

const List<Channel> kChannels = [
  Channel('Airbnb', Color(0xFFE8505B), Icons.house_rounded),
  Channel('Booking.com', Color(0xFF1E4FA0), Icons.bed_rounded),
  Channel('Vrbo', Color(0xFF2B6CB8), Icons.villa_rounded),
  Channel('Agoda', Color(0xFF7A4FCF), Icons.apartment_rounded),
  Channel('Direct site', AppTheme.forest, Icons.language_rounded),
];

const Color _walkIn = Color(0xFFD99A2B);
const Color _blocked = Color(0xFF9AA59F);

String _compactPrice(int rupees) {
  final k = rupees / 1000;
  final text =
      k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
  return '₹${text}k';
}

TextStyle _tiny(
        {Color color = HomeColors.muted,
        FontWeight weight = FontWeight.w500}) =>
    GoogleFonts.outfit(fontSize: 11.5, fontWeight: weight, color: color);

// ── Hero: channel sync board ─────────────────────────────────────────────────

/// Shows what happens to a two-night booking with and without channel sync.
/// Flips automatically every few seconds; the toggle lets visitors flip it.
class ChannelSyncBoard extends StatefulWidget {
  const ChannelSyncBoard({super.key, this.autoPlay = true});

  final bool autoPlay;

  @override
  State<ChannelSyncBoard> createState() => _ChannelSyncBoardState();
}

class _ChannelSyncBoardState extends State<ChannelSyncBoard> {
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  bool _synced = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.autoPlay) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (mounted) setState(() => _synced = !_synced);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _select(bool synced) {
    _timer?.cancel();
    setState(() => _synced = synced);
  }

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: MinWidthScroll(
        minWidth: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Seaside Cottage · 2 nights',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                _SyncToggle(synced: _synced, onChanged: _select),
              ],
            ),
            const SizedBox(height: 14),
            _header(),
            const SizedBox(height: 4),
            for (var i = 0; i < kChannels.length; i++) _row(i),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _status(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        const SizedBox(width: 118),
        for (var d = 0; d < _days.length; d++)
          Expanded(
            child: Center(
              child: Text(
                '${_days[d]} ${12 + d}',
                style: _tiny(weight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(int channelIndex) {
    final channel = kChannels[channelIndex];
    final cells = <Widget>[];
    for (var d = 0; d < _days.length; d++) {
      if (d == 2) {
        cells.add(Expanded(flex: 2, child: _bookedNights(channelIndex)));
        d++;
        continue;
      }
      final weekend = d >= 5;
      cells.add(Expanded(child: _priceCell(weekend ? 5400 : 4200)));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 118,
            child: Row(
              children: [
                Icon(channel.icon, size: 16, color: channel.color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    channel.name,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                        fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          ...cells,
        ],
      ),
    );
  }

  Widget _priceCell(int price) {
    return Container(
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: HomeColors.mist,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(_compactPrice(price), style: _tiny()),
    );
  }

  /// Wednesday + Thursday for one channel row.
  Widget _bookedNights(int channelIndex) {
    String label;
    Color color;
    var conflict = false;
    if (channelIndex == 0) {
      label = 'Anya · 2 nights';
      color = kChannels[0].color;
    } else if (channelIndex == 1 && !_synced) {
      label = 'Marc · 2 nights';
      color = kChannels[1].color;
      conflict = true;
    } else if (_synced) {
      label = 'Closed';
      color = _blocked;
    } else {
      return Row(
        children: [
          Expanded(child: _priceCell(4200)),
          Expanded(child: _priceCell(4200)),
        ],
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: label == 'Closed' ? 0.18 : 0.9),
        borderRadius: BorderRadius.circular(8),
        border:
            conflict ? Border.all(color: HomeColors.danger, width: 2) : null,
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: _tiny(
          color: label == 'Closed' ? HomeColors.muted : Colors.white,
          weight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _status() {
    final ok = _synced;
    final color = ok ? HomeColors.success : HomeColors.danger;
    return Container(
      key: ValueKey(ok),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded,
              color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ok
                  ? 'Synced with Bleiben — the other channels closed those nights instantly.'
                  : 'Double booking — two guests, same cottage, same nights.',
              style: GoogleFonts.outfit(
                  fontSize: 13.5, color: color, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncToggle extends StatelessWidget {
  const _SyncToggle({required this.synced, required this.onChanged});

  final bool synced;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(String label, bool value) {
      final selected = synced == value;
      return GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? (value ? AppTheme.forest : HomeColors.night)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : HomeColors.muted,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: HomeColors.mist,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [option('Without sync', false), option('With Bleiben', true)],
      ),
    );
  }
}

// ── Unified calendar mockup ──────────────────────────────────────────────────

class _Booking {
  const _Booking(this.row, this.start, this.nights, this.guest, this.color);

  final int row;
  final int start;
  final int nights;
  final String guest;
  final Color color;
}

class _Property {
  const _Property(this.name, this.place, this.basePrice);

  final String name;
  final String place;
  final int basePrice;
}

/// Multi-property timeline with colour-coded bookings from each channel.
class CalendarMock extends StatelessWidget {
  const CalendarMock({super.key});

  static const _days = 10;
  static const _dayNames = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  static const _properties = [
    _Property('Cedar Cabin', 'Coorg', 8000),
    _Property('Riverside Loft', 'Rishikesh', 5400),
    _Property('Tea Garden Villa', 'Munnar', 9200),
    _Property('Old Town Studio', 'Jaipur', 3600),
    _Property('Lake House', 'Udaipur', 7000),
  ];

  static final _bookings = [
    _Booking(0, 0, 3, 'Ishaan', kChannels[0].color),
    _Booking(0, 5, 2, 'Leah', kChannels[4].color),
    _Booking(1, 1, 4, 'Kabir', kChannels[1].color),
    const _Booking(1, 7, 2, 'Owner stay', _blocked),
    _Booking(2, 3, 3, 'Tanvi', kChannels[2].color),
    const _Booking(3, 0, 2, 'Walk-in', _walkIn),
    _Booking(3, 4, 4, 'Jonas', kChannels[3].color),
    _Booking(4, 2, 2, 'Zara', kChannels[0].color),
    _Booking(4, 6, 3, 'Dev', kChannels[4].color),
  ];

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(22),
      child: MinWidthScroll(
        minWidth: 860,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Calendar',
                  style: GoogleFonts.outfit(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                Text('12 – 21 Oct',
                    style: GoogleFonts.outfit(color: HomeColors.muted)),
                const Spacer(),
                const _MiniChip('All properties', Icons.home_work_outlined),
                const SizedBox(width: 8),
                const _MiniChip('Bulk pricing', Icons.tune_rounded),
                const SizedBox(width: 8),
                const _MiniChip('In sync', Icons.sync_rounded, highlight: true),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                for (final c in kChannels) _LegendDot(c.name, c.color),
                const _LegendDot('Walk-in', _walkIn),
                const _LegendDot('Blocked', _blocked),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const SizedBox(width: 170),
                for (var d = 0; d < _days; d++)
                  Expanded(
                    child: Column(
                      children: [
                        Text(_dayNames[d % 7], style: _tiny()),
                        Text(
                          '${12 + d}',
                          style: _tiny(
                              color: AppTheme.ink, weight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            for (var r = 0; r < _properties.length; r++) _propertyRow(r),
          ],
        ),
      ),
    );
  }

  Widget _propertyRow(int row) {
    final property = _properties[row];
    final bookings = _bookings.where((b) => b.row == row).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final segments = <Widget>[];
    var day = 0;
    for (final booking in bookings) {
      while (day < booking.start) {
        segments.add(Expanded(child: _price(property, day)));
        day++;
      }
      segments.add(Expanded(flex: booking.nights, child: _bar(booking)));
      day += booking.nights;
    }
    while (day < _days) {
      segments.add(Expanded(child: _price(property, day)));
      day++;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: HomeColors.line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 170,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: AppTheme.forest.withValues(alpha: 0.1),
                  child: Text(
                    property.name[0],
                    style: GoogleFonts.outfit(
                      color: AppTheme.forest,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        property.name,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                            fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                      Text(property.place, style: _tiny()),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ...segments,
        ],
      ),
    );
  }

  Widget _price(_Property property, int day) {
    final weekend = day % 7 >= 5;
    final price = property.basePrice + (weekend ? 1000 : 0);
    return Container(
      height: 38,
      alignment: Alignment.center,
      child: Text(
        _compactPrice(price),
        style: _tiny(color: weekend ? AppTheme.clay : HomeColors.muted),
      ),
    );
  }

  Widget _bar(_Booking booking) {
    final light = booking.color == _blocked;
    return Container(
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: light ? booking.color.withValues(alpha: 0.25) : booking.color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${booking.guest} · ${booking.nights}n',
        overflow: TextOverflow.ellipsis,
        style: _tiny(
          color: light ? AppTheme.ink : Colors.white,
          weight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip(this.label, this.icon, {this.highlight = false});

  final String label;
  final IconData icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? HomeColors.success : HomeColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlight
            ? HomeColors.success.withValues(alpha: 0.08)
            : HomeColors.mist,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: _tiny(color: color, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: _tiny()),
      ],
    );
  }
}
