import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'password_reset_service.dart';

/// Account recovery screen. Mirrors the web's forgot_password.php:
/// the customer enters an email, the server emails a secure reset link
/// from the shop's Gmail, and the new password is chosen on Firebase's
/// own page (opened from that email).
class ForgotPasswordPage extends StatefulWidget {
  /// Optional: pre-fill the email the customer already typed on the login screen.
  final String? initialEmail;

  const ForgotPasswordPage({super.key, this.initialEmail});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  static const Color _accent = Color(0xFFF4B400);

  // Courtesy cooldown between requests from this screen. The REAL limits
  // are on the server (request_password_reset.php).
  static const int _cooldownSeconds = 60;

  final TextEditingController _emailController = TextEditingController();
  final PasswordResetService _resetService = PasswordResetService();

  bool _isSending = false;
  bool _hasSent = false;
  int _cooldownLeft = 0;
  Timer? _cooldownTimer;

  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEmail?.trim();
    if (initial != null && initial.isNotEmpty) {
      _emailController.text = initial;
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_isSending && _cooldownLeft == 0;

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownLeft = _cooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _cooldownLeft--;
        if (_cooldownLeft <= 0) {
          _cooldownLeft = 0;
          timer.cancel();
        }
      });
    });
  }

  void _showStatus(String message, {required bool isError}) {
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim().toLowerCase();
    if (!PasswordResetService.isValidEmail(email)) {
      _showStatus('Please enter a valid email address.', isError: true);
      return;
    }

    setState(() {
      _isSending = true;
      _statusMessage = null;
    });

    try {
      await _resetService.requestReset(email);
      if (!mounted) return;
      // Same message whether or not the account exists.
      _showStatus(
        "If an account exists for $email, we've sent a password reset link. "
            'Check your inbox and spam folder, then follow the link to choose a new password. '
            'After that, come back and sign in with your new password.',
        isError: false,
      );
      setState(() => _hasSent = true);
      _startCooldown();
    } on PasswordResetException catch (e) {
      if (!mounted) return;
      _showStatus(e.message, isError: true);
      if (e.code == 'RATE_LIMITED') _startCooldown();
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String get _buttonLabel {
    if (_cooldownLeft > 0) return 'RESEND IN ${_cooldownLeft}s';
    return _hasSent ? 'RESEND RESET LINK' : 'SEND RESET LINK';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isDark ? Colors.white : Colors.black,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.withOpacity(0.12)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.3 : 0.03),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'BLOOM',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.cormorantGaramond(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 6,
                        color: _accent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Account Recovery',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.cormorantGaramond(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _hasSent ? 'CHECK YOUR INBOX' : 'RESET YOUR PASSWORD',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: isDark ? Colors.grey[500] : Colors.grey[500],
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (_statusMessage != null) ...[
                      _buildStatusBox(isDark),
                      const SizedBox(height: 20),
                    ],

                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      enabled: !_isSending,
                      onSubmitted: (_) => _submit(),
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      decoration: InputDecoration(
                        labelText: 'Email Address',
                        labelStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600], fontSize: 13),
                        prefixIcon: const Icon(Icons.email_outlined, color: _accent, size: 20),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF8F8F6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: _accent, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
                      ),
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        // null = disabled while sending or cooling down
                        onPressed: _canSubmit ? _submit : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: const Color(0xFF121212),
                          disabledBackgroundColor: isDark ? Colors.grey[800] : Colors.grey[300],
                          disabledForegroundColor: Colors.grey[500],
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: _isSending
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF121212)),
                        )
                            : Text(
                          _buttonLabel,
                          style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      "We'll email you a secure link to choose a new password. "
                          'The link works once and expires after about an hour.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, height: 1.5, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'RETURN TO SIGN IN',
                        style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBox(bool isDark) {
    final color = _statusIsError ? const Color(0xFFE91E63) : const Color(0xFF15803D);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.15 : 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_statusIsError ? Icons.error_outline : Icons.mark_email_read_outlined, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusMessage!,
              style: TextStyle(fontSize: 12, height: 1.5, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}