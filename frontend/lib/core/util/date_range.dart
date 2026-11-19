import 'package:flutter/material.dart';

/// One date-range picker for the whole product: a compact dialog (not a
/// full-screen page) with clear From / To labels, so a range always reads
/// the same way — calendar, dashboard, reservations, expenses, bookings.
Future<DateTimeRange?> pickDateRange(
  BuildContext context, {
  DateTimeRange? initial,
  required DateTime firstDate,
  required DateTime lastDate,
  String help = 'Select dates',
  String startLabel = 'From',
  String endLabel = 'To',
  String save = 'Apply',
}) {
  DateTime clamp(DateTime d) => d.isBefore(firstDate) ? firstDate : d.isAfter(lastDate) ? lastDate : d;
  final init = initial == null ? null : DateTimeRange(start: clamp(initial.start), end: clamp(initial.end));
  return showDateRangePicker(
    context: context,
    initialDateRange: init != null && !init.end.isBefore(init.start) ? init : null,
    firstDate: firstDate,
    lastDate: lastDate,
    helpText: help,
    saveText: save,
    fieldStartLabelText: startLabel,
    fieldEndLabelText: endLabel,
    fieldStartHintText: 'dd/mm/yyyy',
    fieldEndHintText: 'dd/mm/yyyy',
    builder: (ctx, child) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 640),
        child: ClipRRect(borderRadius: BorderRadius.circular(20), child: child),
      ),
    ),
  );
}
