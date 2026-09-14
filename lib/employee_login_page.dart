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

  // --- Fraud/Lockout state (mirrors AuthPage's customer-side logic,
  // but scoped separately so a customer's failed attempts never lock
  // out this admin/employee portal, and vice versa) ---
  final DeviceSecurityService _securityService =
  DeviceSecurityService(scope: 'employee');
  int _remainingLockoutSeconds = 0;
  bool _superAdminLocked = false;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    _isRateLimited(); // Check on screen open in case this device is already locked out
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel(); // prevent setState-after-dispose crash / leak
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // --- FRAUD & RATE LIMITING HELPERS ---
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
  // -------------------------------------

  /// New-device visibility for the admin portal, matching the soft
  /// notification-only approach already used for flagged customer
  /// accounts (see set_session.php) — this NEVER blocks login. A
  /// staff/admin account's own known devices are tracked separately
  /// from `banned_devices`, which exists for CUSTOMER fraud and has
  /// nothing to do with credential-theft risk on a trusted account.
  ///
  /// The very first login after this feature ships gets treated as
  /// baseline setup (no alert, just starts tracking) — otherwise every
  /// existing staff account would trigger a false alarm the next time
  /// they log in, purely because they'd never had a device recorded
  /// before.
  Future<void> _checkAndTrackDevice(String uid, String displayEmail) async {
    try {
      final deviceHash = await _securityService.getDeviceHash();
      final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = userDoc.data();
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
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'deviceHashes': FieldValue.arrayUnion([deviceHash]),
        });
      }
    } catch (e) {
      // Best-effort, same philosophy as every other fraud-adjacent
      // logging call in this project — a tracking failure must never
      // stop a legitimate staff member from getting into the dashboard.
      debugPrint('Device tracking failed (login still proceeds): $e');
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    if (await _isRateLimited()) return; // Blocks the call entirely while locked out

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
          await _securityService.recordFailedAttempt(); // A customer probing the admin portal still counts as a strike
          await _isRateLimited(); // refresh countdown UI immediately
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

        // Successful, authorized login — clear the strike counter.
        await _securityService.resetAttempts();

        // New-device visibility check — runs for every authorized
        // portal role (admin, super-admin, staff, employee, delivery),
        // since this is the one shared login point for all of them.
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
      setState(() => isLoading = false);
      await _securityService.recordFailedAttempt();
      await _isRateLimited();

      String message = 'Login failed';
      if (e.code == 'user-not-found') {
        message = 'No user found for that email.';
      } else if (e.code == 'wrong-password') {
        message = 'Wrong password provided.';
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
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An unexpected error occurred: $e')),
        );
      }
    } finally {
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo Container
                  Container(
                    width: 100,
                    height: 100,
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
                  const SizedBox(height: 24),
                  const Text(
                    'ADMIN PORTAL',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Login Card
                  Container(
                    padding: const EdgeInsets.all(24),
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
                          const SizedBox(height: 32),
                          _buildTextField(
                            controller: emailController,
                            label: 'Email Address',
                            icon: Icons.alternate_email_rounded,
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value == null || value.isEmpty)
                                return 'Email is required';
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
                              if (value == null || value.isEmpty)
                                return 'Password is required';
                              if (value.length < 6)
                                return 'Password must be at least 6 characters';
                              return null;
                            },
                          ),

                          // --- LOCKOUT WARNING UI ---
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
                          // ---------------------------------------------------------------

                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
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
                          const SizedBox(height: 32),
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

                  const SizedBox(height: 40),
                  Text(
                    '© 2026 BloomyPro Inventory System',
                    style: TextStyle(color: Colors.grey[400], fontSize: 10),
                  ),
                ],
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