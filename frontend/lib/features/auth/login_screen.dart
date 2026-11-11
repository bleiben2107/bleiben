import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import 'auth_controller.dart';
import 'auth_models.dart';

enum _Mode { login, signup }

/// Passwordless auth, matching the reference flow:
/// * Log in — one "Email or phone number" field, OTP by email (or SMS).
/// * Sign up — full name + email (required) + phone (optional), OTP by email.
/// The account is only created once the emailed OTP is verified.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.auth,
    this.initialRegister = false,
  });

  final AuthController auth;

  /// Opens on "Sign up" instead of "Log in".
  final bool initialRegister;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _countryCodes = ['+91', '+971', '+1', '+44', '+61', '+65'];
  static final _emailRe =
      RegExp(r'^(?!.*\.\.)[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
  static final _nameRe = RegExp(r'^[a-zA-Z]+(?: [a-zA-Z]+)*$');

  final _formKey = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  late _Mode _mode = widget.initialRegister ? _Mode.signup : _Mode.login;
  String _countryCode = '+91';
  CodeSent? _sent; // non-null while on the OTP step
  int _resendIn = 0;
  Timer? _timer;

  AuthController get auth => widget.auth;

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [
      _identifierCtrl,
      _nameCtrl,
      _emailCtrl,
      _phoneCtrl,
      _otpCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _switchMode(_Mode mode) {
    // Carry the email across so the user doesn't retype it.
    if (mode == _Mode.signup &&
        _emailRe.hasMatch(_identifierCtrl.text.trim())) {
      _emailCtrl.text = _identifierCtrl.text.trim();
    } else if (mode == _Mode.login && _emailCtrl.text.trim().isNotEmpty) {
      _identifierCtrl.text = _emailCtrl.text.trim();
    }
    auth.error = null;
    auth.suggestedAction = null;
    _timer?.cancel();
    setState(() {
      _mode = mode;
      _sent = null;
      _resendIn = 0;
      _otpCtrl.clear();
    });
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    setState(() => _resendIn = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendIn = (_resendIn - 1).clamp(0, 999));
      if (_resendIn == 0) t.cancel();
    });
  }

  Future<void> _requestOtp() async {
    if (_sent == null && !(_formKey.currentState?.validate() ?? false)) return;
    final sent = _mode == _Mode.login
        ? await auth.requestLoginOtp(
            identifier: _identifierCtrl.text.trim(), countryCode: _countryCode)
        : await auth.requestSignupOtp(
            name: _nameCtrl.text.trim().replaceAll(RegExp(r'\s+'), ' '),
            email: _emailCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            countryCode: _countryCode,
          );
    if (sent == null || !mounted) return;
    setState(() {
      _sent = sent;
      _otpCtrl.clear();
    });
    _startCountdown(sent.resendIn);
  }

  Future<void> _verify() async {
    final code = _otpCtrl.text.trim();
    if (code.length != 6) {
      setState(() => auth.error = 'OTP is required');
      return;
    }
    _mode == _Mode.login
        ? await auth.verifyLoginOtp(
            identifier: _identifierCtrl.text.trim(),
            code: code,
            countryCode: _countryCode)
        : await auth.verifySignupOtp(email: _emailCtrl.text.trim(), code: code);
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: _sent != null
              ? BackButton(onPressed: () => setState(() => _sent = null))
              : (Navigator.canPop(context) ? const BackButton() : null),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Bleiben',
                        style: GoogleFonts.fraunces(
                            fontSize: 44,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.forest),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _mode == _Mode.signup
                            ? 'Create your account'
                            : 'Welcome back',
                        style: TextStyle(
                            color: AppTheme.ink.withValues(alpha: 0.6),
                            fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      if (_sent == null) ..._formBody() else ..._otpBody(),
                      if (auth.error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8D7DA),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            auth.error!,
                            key: const Key('auth-error'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Color(0xFFA22029), fontSize: 13.5),
                          ),
                        ),
                        if (auth.suggestedAction == 'login' &&
                            _mode == _Mode.signup)
                          TextButton(
                              onPressed: () => _switchMode(_Mode.login),
                              child: const Text('Log in instead')),
                        if (auth.suggestedAction == 'signup' &&
                            _mode == _Mode.login)
                          TextButton(
                              onPressed: () => _switchMode(_Mode.signup),
                              child: const Text('Sign up instead')),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _formBody() {
    final isLogin = _mode == _Mode.login;
    return [
      Text(isLogin ? 'Log in' : 'Sign up',
          style: _heading, textAlign: TextAlign.center),
      const SizedBox(height: 18),
      if (isLogin)
        TextFormField(
          controller: _identifierCtrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [
            AutofillHints.email,
            AutofillHints.telephoneNumber
          ],
          decoration:
              const InputDecoration(labelText: 'Email or phone number *'),
          onFieldSubmitted: (_) => _requestOtp(),
          validator: (v) {
            final value = (v ?? '').trim();
            if (value.isEmpty) return 'Email or phone number is required';
            final digits = value.replaceAll(RegExp(r'[\s-]'), '');
            if (RegExp(r'^\+?\d+$').hasMatch(digits)) {
              return digits.replaceAll('+', '').length >= 10
                  ? null
                  : 'Enter a valid phone number';
            }
            return _emailRe.hasMatch(value) ? null : 'Enter a valid email';
          },
        )
      else ...[
        TextFormField(
          controller: _nameCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z ]'))
          ],
          decoration: const InputDecoration(labelText: 'Full name *'),
          validator: (v) {
            final value = (v ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
            if (value.isEmpty) return 'Name is required';
            if (!_nameRe.hasMatch(value)) return 'Only alphabets are allowed';
            return value.length > 75
                ? 'Name is too long (75 characters max)'
                : null;
          },
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Email *'),
          validator: (v) {
            final value = (v ?? '').trim();
            if (value.isEmpty) return 'Email is required';
            return _emailRe.hasMatch(value) ? null : 'Invalid email';
          },
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 104,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _countryCode,
                decoration: const InputDecoration(labelText: 'Code'),
                items: [
                  for (final c in _countryCodes)
                    DropdownMenuItem(value: c, child: Text(c))
                ],
                onChanged: (v) => setState(() => _countryCode = v ?? '+91'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(15)
                ],
                decoration: const InputDecoration(
                    labelText: 'Phone number', helperText: 'Optional'),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return null;
                  return value.length < 10
                      ? 'Phone number must be at least 10 digits'
                      : null;
                },
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 22),
      _primary(isLogin ? 'Continue' : 'Send OTP', _requestOtp),
      const SizedBox(height: 14),
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(isLogin ? "Don't have an account?" : 'Already have an account?'),
          TextButton(
            onPressed: auth.busy
                ? null
                : () => _switchMode(isLogin ? _Mode.signup : _Mode.login),
            child: Text(isLogin ? 'Sign up' : 'Log in'),
          ),
        ],
      ),
      if (!isLogin)
        Text(
          'By signing up, you agree to the Terms & Conditions and Privacy policy.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 12, color: AppTheme.ink.withValues(alpha: 0.5)),
        ),
    ];
  }

  List<Widget> _otpBody() {
    final sent = _sent!;
    final viaSms = sent.channel == 'phone';
    return [
      Text('Enter OTP', style: _heading, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(
        'Please enter the OTP sent to ${sent.sentTo}${viaSms ? ' by SMS' : ''}',
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 14.5, color: AppTheme.ink.withValues(alpha: 0.7)),
      ),
      if (!viaSms)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'From team@bleiben.co.in — check spam if you don’t see it.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5, color: AppTheme.ink.withValues(alpha: 0.5)),
          ),
        ),
      if (sent.devCode != null)
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.clay.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Development mode — ${viaSms ? 'no SMS provider' : 'no mail server'} yet. Your OTP is ${sent.devCode}.',
            style: const TextStyle(fontSize: 13, color: AppTheme.clay),
          ),
        ),
      const SizedBox(height: 18),
      TextField(
        controller: _otpCtrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        textAlign: TextAlign.center,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(
            fontSize: 26, letterSpacing: 12, fontWeight: FontWeight.w600),
        decoration: const InputDecoration(counterText: '', hintText: '••••••'),
        onChanged: (v) {
          if (v.length == 6) _verify();
        },
      ),
      const SizedBox(height: 18),
      _primary('Verify', _verify),
      const SizedBox(height: 6),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: () => setState(() {
              _sent = null;
              auth.error = null;
            }),
            child: Text(viaSms ? 'Change number' : 'Change email'),
          ),
          TextButton(
            onPressed: _resendIn > 0 || auth.busy ? null : _requestOtp,
            child: Text(
                _resendIn > 0 ? 'Resend OTP (${_resendIn}s)' : 'Resend OTP'),
          ),
        ],
      ),
    ];
  }

  TextStyle get _heading => GoogleFonts.outfit(
      fontSize: 22, fontWeight: FontWeight.w600, color: AppTheme.ink);

  Widget _primary(String label, VoidCallback onPressed) => ElevatedButton(
        onPressed: auth.busy ? null : onPressed,
        child: auth.busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(label),
      );
}
