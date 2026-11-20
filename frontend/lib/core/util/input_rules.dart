import 'package:flutter/services.dart';

/// Shared field rules: what a field accepts while typing, and how its value
/// is checked. Number fields take only digits, name fields only letters, etc.
class InputRules {
  InputRules._();

  /// Whole numbers (counts, OTP codes, prices in whole rupees, PIN codes).
  static final digits = <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly];

  /// Amounts: digits with at most one decimal point and 2 decimals.
  static final amount = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
    TextInputFormatter.withFunction((old, next) => RegExp(r'^\d*\.?\d{0,2}$').hasMatch(next.text) ? next : old),
  ];

  /// Signed amounts / percentages (e.g. -15 or 10.5).
  static final signedAmount = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
    TextInputFormatter.withFunction((old, next) => RegExp(r'^-?\d*\.?\d{0,2}$').hasMatch(next.text) ? next : old),
  ];

  /// Phone numbers: digits, a leading +, spaces and dashes; max 16 characters.
  static final phone = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')),
    LengthLimitingTextInputFormatter(16),
  ];

  /// People's names: letters (any language), spaces, dot, apostrophe, hyphen.
  static final name = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r"[\p{L}\p{M} .'\-]", unicode: true)),
    LengthLimitingTextInputFormatter(80),
  ];

  /// Upper-case letters and digits only (IFSC, PAN, GSTIN).
  static List<TextInputFormatter> code(int max) => [
        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
        TextInputFormatter.withFunction((_, next) => next.copyWith(text: next.text.toUpperCase())),
        LengthLimitingTextInputFormatter(max),
      ];

  static final _email = RegExp(r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$');
  static final _phone = RegExp(r'^\+?[0-9][0-9 \-]{8,15}$');
  static final _name = RegExp(r"^[\p{L}\p{M}][\p{L}\p{M} .'\-]*$", unicode: true);

  static bool isEmail(String v) => _email.hasMatch(v.trim());

  static bool isPhone(String v) {
    final t = v.trim();
    final count = t.replaceAll(RegExp(r'\D'), '').length;
    return _phone.hasMatch(t) && count >= 10 && count <= 13;
  }

  static bool isName(String v) => v.trim().length >= 2 && _name.hasMatch(v.trim());

  // Form validators (return an error message or null).
  static String? requiredName(String? v, {String what = 'your full name'}) =>
      (v ?? '').trim().isEmpty ? 'Enter $what' : isName(v!) ? null : 'Use letters only';

  static String? requiredPhone(String? v) =>
      (v ?? '').trim().isEmpty ? 'Enter a phone number' : isPhone(v!) ? null : 'Enter a valid 10-digit phone number';

  static String? optionalPhone(String? v) => (v ?? '').trim().isEmpty ? null : requiredPhone(v);

  static String? requiredEmail(String? v) =>
      (v ?? '').trim().isEmpty ? 'Enter an email address' : isEmail(v!) ? null : 'Enter a valid email address (name@example.com)';

  static String? optionalEmail(String? v) => (v ?? '').trim().isEmpty ? null : requiredEmail(v);
}
