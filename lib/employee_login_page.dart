import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'admin_dashboard.dart';
import 'delivery_dashboard.dart';
import 'inventory_data.dart';
import 'device_security_service.dart';

class EmployeeLoginPage extends StatefulWidget {
  const EmployeeLoginPage({Key? key}) : super(key: key);

  @override
  State<EmployeeLoginPage> createState() => _EmployeeLoginPageState();
}

class _EmployeeLoginPageState extends State<EmployeeLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;

  final DeviceSecurityService _securityService =
  DeviceSecurityService(scope: 'employee');
  int _remainingLockoutSeconds = 0;
  bool _superAdminLocked = false;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    _isRateLimited();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<bool> _isRateLimited() async {
    final rateLimit = await _securityService.checkRateLimit();
    if (rateLimit['locked'] == true) {
      if (mounted) {
        setState(() {
          _superAdminLocked = rateLimit['superAdminLock'] == true;
          _remainingLockoutSeconds = rateLimit['remainingSeconds'] ?? 0;
        });
        _startTimer();
      }
      return true;
    }
    return false;
  }

  void _startTimer() {
    _lockoutTimer?.cancel();
    if (_remainingLockoutSeconds > 0 && !_superAdminLocked) {
      _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            if (_remainingLockoutSeconds > 0) {
              _remainingLockoutSeconds--;
            } else {
              _lockoutTimer?.cancel();
            }
          });
        }
      });
    }
  }

  // Reads/writes 'employees/{uid}' (deviceHashes and branchId live there).
  // .set(..., merge: true) creates the doc if missing and merges if present,
  // so it never throws the way .update() does on a missing document.
  Future<void> _checkAndTrackDevice(String uid, String displayEmail) async {
    try {
      final deviceHash = await _securityService.getDeviceHash();
      final employeeDoc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(uid)
          .get();
      final data = employeeDoc.data();
      final rawHashes = data?['deviceHashes'];
      final hasNoDeviceHistoryYet = rawHashes == null;
      final knownHashes = rawHashes is List
          ? rawHashes.map((e) => e.toString()).toList()
          : <String>[];
      final isRecognized = knownHashes.contains(deviceHash);

      if (!isRecognized && !hasNoDeviceHistoryYet) {
        await FirebaseFirestore.instance.collection('notifications').add({
          'title': 'Staff Login — New Device',
          'message':
          '$displayEmail logged into the admin portal from a device not previously seen on this account.',
          'type': 'fraud',
          'branchId': data?['branchId'],
          'created_at': FieldValue.serverTimestamp(),
          'read': false,
        });
      }

      if (!isRecognized) {
        await FirebaseFirestore.instance
            .collection('employees')
            .doc(uid)
            .set({
          'deviceHashes': FieldValue.arrayUnion([deviceHash]),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Device tracking failed (login still proceeds): $e');
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    if (await _isRateLimited()) return;

    setState(() => isLoading = true);
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      if (credential.user != null) {
        final role = await InventoryData.getUserRole(credential.user!.uid);
        if (role == null || role == 'customer') {
          await FirebaseAuth.instance.signOut();
          await _securityService.recordFailedAttempt();
          await _isRateLimited();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.white),
                    SizedBox(width: 12),
                    Expanded(
                        child: Text(
                            'Unauthorized access. Only staff and employees are allowed.')),
                  ],
                ),
                backgroundColor: Colors.redAccent,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
          return;
        }

        await _securityService.resetAttempts();

        await _checkAndTrackDevice(
            credential.user!.uid, emailController.text.trim());

        if (mounted) {
          if (role == 'delivery') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const DeliveryDashboard(),
              ),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => AdminDashboard(role: role),
              ),
            );
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      await _securityService.recordFailedAttempt();
      await _isRateLimited();

      String message = 'Login failed';
      if (e.code == 'user-not-found') {
        message = 'No user found for that email.';
      } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        // Newer Firebase versions report a bad email/password combo as
        // 'invalid-credential' instead of 'wrong-password'.
        message = 'Incorrect email or password.';
      } else if (e.code == 'invalid-email') {
        message = 'The email address is badly formatted.';
      } else if (e.code == 'user-disabled') {
        message = 'This account has been disabled.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An unexpected error occurred: $e')),
        );
      }
    } finally {
      // Runs after success, failure, or the early return above, so the
      // spinner can never get stuck.
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    if (emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email first')),
      );
      return;
    }

    if (await _isRateLimited()) return;

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: emailController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset link sent to your email'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      await _securityService.recordFailedAttempt();
      await _isRateLimited();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- Responsive sizing ---------------------------------------------
    // Read the screen once, then scale spacing and sizes from it so small
    // phones (and phones with the keyboard open) never run out of room.
    final size = MediaQuery.of(context).size;
    final bool narrow = size.width < 360;
    final bool short = size.height < 640;
    final double sidePadding = narrow ? 16.0 : 24.0;
    final double cardPadding = narrow ? 18.0 : 24.0;
    final double logoSize = (narrow || short) ? 76.0 : 100.0;
    final double gapAfterTitle = short ? 24.0 : 40.0;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFDF7), // Lighter Cream
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF121212),
              const Color(0xFF121212).withOpacity(0.9),
              const Color(0xFFFFFDF7),
              const Color(0xFFFFFDF7),
            ],
            stops: const [0.0, 0.3, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              // Dragging the page closes the keyboard instead of fighting it.
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding:
              EdgeInsets.symmetric(horizontal: sidePadding, vertical: 16),
              // On tablets/landscape, keep the form a sensible width.
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: logoSize,
                      height: logoSize,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF4B400).withOpacity(0.4),
                            blurRadius: 30,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(15.0),
                        child: Image.asset(
                          'assets/images/logo.jpg',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.business_center,
                              size: 40, color: Color(0xFFF4B400)),
                        ),
                      ),
                    ),
                    SizedBox(height: short ? 16 : 24),
                    // FittedBox shrinks the title only if it would not fit.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'ADMIN PORTAL',
                        style: TextStyle(
                          fontSize: narrow ? 24 : 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ),
                    SizedBox(height: gapAfterTitle),

                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(cardPadding),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          )
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Welcome Back',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF121212),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Please sign in to continue to your dashboard',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                            SizedBox(height: short ? 20 : 32),
                            _buildTextField(
                              controller: emailController,
                              label: 'Email Address',
                              icon: Icons.alternate_email_rounded,
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Email is required';
                                }
                                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                                    .hasMatch(value)) {
                                  return 'Enter a valid email address';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            _buildTextField(
                              controller: passwordController,
                              label: 'Password',
                              icon: Icons.lock_outline_rounded,
                              obscureText: _obscurePassword,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: Colors.grey,
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                        () => _obscurePassword = !_obscurePassword),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Password is required';
                                }
                                if (value.length < 6) {
                                  return 'Password must be at least 6 characters';
                                }
                                return null;
                              },
                            ),

                            if (_superAdminLocked || _remainingLockoutSeconds > 0)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(top: 16),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: Colors.red.withOpacity(0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.lock_clock,
                                        color: Colors.redAccent),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _superAdminLocked
                                            ? 'Account locked. Please coordinate with a Super Admin to reset access.'
                                            : 'Too many attempts. Please wait $_remainingLockoutSeconds seconds.',
                                        style: const TextStyle(
                                          color: Colors.redAccent,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            const SizedBox(height: 12),

                            // WAS a Row: on narrow phones its two halves were
                            // wider than the card and overflowed (the
                            // yellow/black warning stripe). A Wrap puts the
                            // second item on its own line when there is no
                            // room, instead of overflowing.
                            SizedBox(
                              width: double.infinity,
                              child: Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                runSpacing: 4,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: Checkbox(
                                          value: _rememberMe,
                                          onChanged: (val) => setState(
                                                  () => _rememberMe = val ?? false),
                                          activeColor: const Color(0xFFF4B400),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                              BorderRadius.circular(4)),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text('Remember me',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF333333))),
                                    ],
                                  ),
                                  TextButton(
                                    onPressed: _forgotPassword,
                                    child: const Text(
                                      'Forgot Password?',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFFF4B400),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: short ? 20 : 32),
                            if (isLoading)
                              const Center(
                                  child: CircularProgressIndicator(
                                      color: Color(0xFFF4B400)))
                            else
                              ElevatedButton(
                                onPressed: (_superAdminLocked ||
                                    _remainingLockoutSeconds > 0)
                                    ? null
                                    : _login,
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 56),
                                  backgroundColor: const Color(0xFF121212),
                                  foregroundColor: const Color(0xFFF4B400),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                ),
                                child: const Text(
                                  'SIGN IN',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: short ? 24 : 40),
                    Text(
                      '© 2026 BloomyPro Inventory System',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[400], fontSize: 10),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Color(0xFF121212), fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 14),
        prefixIcon: Icon(icon, color: const Color(0xFF121212), size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF8F9FA),
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
          borderSide: const BorderSide(color: Color(0xFFF4B400), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1),
        ),
        contentPadding:
        const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      ),
    );
  }
}