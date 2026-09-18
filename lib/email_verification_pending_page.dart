import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'email_verification_service.dart';
import 'customer_profile_page.dart';
import 'auth_page.dart';

/// Blocking gate shown after email/password registration, and re-shown
/// on every login attempt, until the customer's Firebase emailVerified
/// flag is true. Tries the branded custom email FIRST, falling back to
/// Firebase's native sendEmailVerification() if that fails — same
/// defensive reasoning as _registerNewUser() in auth_page.dart.
class EmailVerificationPendingPage extends StatefulWidget {
  final String customerId;
  const EmailVerificationPendingPage({super.key, required this.customerId});

  @override
  State<EmailVerificationPendingPage> createState() =>
      _EmailVerificationPendingPageState();
}

class _EmailVerificationPendingPageState
    extends State<EmailVerificationPendingPage> with WidgetsBindingObserver {
  final EmailVerificationService _service = EmailVerificationService();
  bool _isResending = false;
  bool _isChecking = false;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cooldownTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _silentCheckVerified();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _silentCheckVerified();
    });
  }

  Future<void> _silentCheckVerified() async {
    if (_isChecking) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await user.reload();
      final refreshed = FirebaseAuth.instance.currentUser;
      if (refreshed != null && refreshed.emailVerified && mounted) {
        _pollTimer?.cancel();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CustomerProfilePage(
                email: refreshed.email ?? '', customerId: widget.customerId),
          ),
        );
      }
    } catch (e) {
      // Fail silently — the next poll tick tries again.
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (_resendCooldown > 0) {
          _resendCooldown--;
        } else {
          t.cancel();
        }
      });
    });
  }

  /// Tries the branded custom email first (send_verification_email.php).
  /// If that fails for ANY reason — thrown exception, or a
  /// success:false result — falls back to Firebase Auth's own native
  /// sendEmailVerification(), which runs entirely on Google's
  /// infrastructure and bypasses Hostinger/PHP/CDN. This guarantees the
  /// person always gets SOME verification email.
  Future<void> _resend() async {
    setState(() => _isResending = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed: No signed-in user found.')),
        );
        setState(() => _isResending = false);
      }
      return;
    }

    bool primarySucceeded = false;
    String? primaryMessage;
    try {
      final result = await _service.sendVerificationEmail();
      primarySucceeded = result.success;
      primaryMessage = result.message;
    } catch (e) {
      primaryMessage = e.toString();
    }

    if (!primarySucceeded) {
      try {
        await user.sendEmailVerification();
        primarySucceeded = true; // fallback succeeded
      } catch (fallbackError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed: ${primaryMessage ?? fallbackError.toString()}'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 6),
          ));
          setState(() => _isResending = false);
        }
        return;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Verification email sent! Check your inbox.'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 6),
      ));
      setState(() => _isResending = false);
      _startCooldown();
    }
  }

  Future<void> _checkVerified() async {
    setState(() => _isChecking = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        Navigator.pushAndRemoveUntil(context,
            MaterialPageRoute(builder: (_) => const AuthPage()), (r) => false);
      }
      return;
    }

    await user.reload();
    final refreshed = FirebaseAuth.instance.currentUser;

    if (refreshed != null && refreshed.emailVerified) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CustomerProfilePage(
                email: refreshed.email ?? '', customerId: widget.customerId),
          ),
        );
      }
    } else {
      if (mounted) {
        setState(() => _isChecking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Still not verified. Please tap the link in the email first.')),
        );
      }
    }
  }

  Future<void> _signOutAndLeave() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
          context, MaterialPageRoute(builder: (_) => const AuthPage()), (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'your email';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFFFF8E1),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4B400).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mark_email_unread_rounded,
                    size: 56, color: Color(0xFFF4B400)),
              ),
              const SizedBox(height: 28),
              Text(
                'Verify Your Email',
                style: GoogleFonts.cormorantGaramond(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF121212)),
              ),
              const SizedBox(height: 12),
              Text(
                'We sent a verification link to $email. Please check your inbox (and spam folder), then tap the link to confirm — this screen will update automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, color: isDark ? Colors.grey[400] : Colors.grey[700]),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isDark ? Colors.grey[600] : Colors.grey[400],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Waiting for confirmation...',
                    style: TextStyle(
                        fontSize: 11, color: isDark ? Colors.grey[500] : Colors.grey[500]),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isChecking ? null : _checkVerified,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF121212),
                    foregroundColor: const Color(0xFFF4B400),
                  ),
                  child: _isChecking
                      ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFFF4B400)))
                      : const Text("I'VE VERIFIED — CHECK NOW",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: (_isResending || _resendCooldown > 0) ? null : _resend,
                child: Text(_resendCooldown > 0
                    ? 'Resend available in ${_resendCooldown}s'
                    : (_isResending ? 'Sending...' : 'Resend Verification Email')),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _signOutAndLeave,
                child: Text('Sign out and use a different account',
                    style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600])),
              ),
            ],
          ),
        ),
      ),
    );
  }
}