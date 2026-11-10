import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../stays/stays_controller.dart';
import 'auth_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth, required this.stays});

  final AuthController auth;
  final StaysController stays;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _isRegister = false;
  bool _obscure = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    bool ok;
    if (_isRegister) {
      ok = await widget.auth.register(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
    } else {
      ok = await widget.auth.login(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
    }

    if (ok && mounted) {
      await widget.stays.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Logo / wordmark ──────────────────────────────────
                  Text(
                    'Bleiben',
                    style: GoogleFonts.fraunces(
                      fontSize: 48,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.forest,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isRegister ? 'Create your account' : 'Welcome back',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppTheme.ink.withValues(alpha: 0.6),
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  // ── Form ─────────────────────────────────────────────
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_isRegister) ...[
                          TextFormField(
                            controller: _nameCtrl,
                            textCapitalization: TextCapitalization.words,
                            decoration:
                                const InputDecoration(labelText: 'Full name'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Name is required'
                                : null,
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Email'),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Email is required';
                            }
                            if (!v.contains('@')) return 'Enter a valid email';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            suffixIcon: IconButton(
                              icon: Icon(_obscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Password is required';
                            }
                            if (_isRegister && v.length < 8) {
                              return 'At least 8 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),

                        // ── API error message ─────────────────────────
                        if (auth.error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            auth.error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],

                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: auth.busy ? null : _submit,
                          child: auth.busy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(_isRegister ? 'Create account' : 'Sign in'),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Toggle register / login ───────────────────────────
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _isRegister
                            ? 'Already have an account? '
                            : "Don't have an account? ",
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isRegister = !_isRegister;
                            _formKey.currentState?.reset();
                            widget.auth.error = null;
                          });
                        },
                        child: Text(
                          _isRegister ? 'Sign in' : 'Register',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.forest,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

