import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';

import 'main.dart';
import 'inventory_data.dart';
import 'admin_dashboard.dart';
import 'my_orders_page.dart';
import 'customer_profile_page.dart';
import 'device_security_service.dart';
import 'registration_risk_service.dart';
import 'email_verification_service.dart';
import 'email_verification_pending_page.dart';
import 'forgot_password_page.dart';

class AuthPage extends StatefulWidget {
  final bool returnAfterLogin;
  final VoidCallback? onLoginSuccess;

  const AuthPage({
    super.key,
    this.returnAfterLogin = false,
    this.onLoginSuccess,
  });

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();

  DateTime? _selectedBirthday;
  String _selectedSex = 'Male';

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isSigningUp = false;

  bool _agreedToTerms = false;

  late final TapGestureRecognizer _termsTapRecognizer;

  int _remainingLockoutSeconds = 0;
  bool _superAdminLocked = false;
  Timer? _lockoutTimer;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DeviceSecurityService _securityService = DeviceSecurityService();
  final RegistrationRiskService _registrationRiskService = RegistrationRiskService();
  final EmailVerificationService _emailVerificationService = EmailVerificationService();

  final Color _primaryGold = const Color(0xFFF39C12);

  @override
  void initState() {
    super.initState();
    _termsTapRecognizer = TapGestureRecognizer()..onTap = _showTermsDialog;
    _checkExistingSession();
    _isRateLimited();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _termsTapRecognizer.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
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
        } else {
          timer.cancel();
        }
      });
    }
  }

  Future<void> _checkExistingSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      final email = user.email;
      if (email == null) return;

      final customerDoc = await _firestore.collection('customers').doc(user.uid).get();

      if (customerDoc.exists) {
        final requiresVerification = customerDoc.data()?['requireEmailVerification'] == true;
        if (requiresVerification && !user.emailVerified) {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => EmailVerificationPendingPage(customerId: user.uid)),
            );
          }
          return;
        }
        if (mounted) {
          if (widget.returnAfterLogin) {
            widget.onLoginSuccess?.call();
            Navigator.pop(context, true);
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => CustomerProfilePage(email: email, customerId: user.uid)),
            );
          }
        }
        return;
      } else {
        QuerySnapshot? emailQuery = await _firestore
            .collection('customers')
            .where('email', isEqualTo: email.toLowerCase())
            .limit(1)
            .get();

        if (emailQuery.docs.isNotEmpty) {
          final existingDoc = emailQuery.docs.first;
          final userData = existingDoc.data() as Map<String, dynamic>;
          final oldDocId = existingDoc.id;

          final sanitizedUserData = Map<String, dynamic>.from(userData)..remove('password');

          await _firestore.collection('customers').doc(user.uid).set({
            ...sanitizedUserData,
            'lastLogin': FieldValue.serverTimestamp(),
            'migratedFrom': oldDocId,
          }, SetOptions(merge: true));

          if (oldDocId != user.uid) {
            await _firestore.collection('customers').doc(oldDocId).delete();
          }

          if (mounted) {
            if (widget.returnAfterLogin) {
              widget.onLoginSuccess?.call();
              Navigator.pop(context, true);
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => CustomerProfilePage(email: email, customerId: user.uid)),
              );
            }
          }
          return;
        }
      }
    }
  }

  Future<void> _handleContinue() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid email')));
      return;
    }

    if (_isSigningUp) {
      final fName = _firstNameController.text.trim();
      final lName = _lastNameController.text.trim();
      final password = _passwordController.text.trim();
      final confirmPassword = _confirmPasswordController.text.trim();

      if (fName.isEmpty || lName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your first and last name')));
        return;
      }
      if (_selectedBirthday == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select your birthday')));
        return;
      }
      if (password.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password must be at least 6 characters')));
        return;
      }
      if (password != confirmPassword) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
        return;
      }
      if (!_agreedToTerms) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must agree to the Terms and Conditions to create an account.')),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final employeeQuery = await _firestore.collection('users').where('email', isEqualTo: email).limit(1).get();
      if (employeeQuery.docs.isNotEmpty) {
        final role = employeeQuery.docs.first.data()['role'];
        if (role != null && role != 'customer') {
          setState(() => _isLoading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('This email is registered as an Employee/Admin ($role). Please use the Employee Portal.'),
                backgroundColor: Colors.orangeAccent,
              ),
            );
          }
          return;
        }
      }

      if (_isSigningUp) {
        final query = await _firestore.collection('customers').where('email', isEqualTo: email).limit(1).get();
        if (query.docs.isNotEmpty) {
          setState(() {
            _isSigningUp = false;
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email already exists. Please sign in.')));
          return;
        }
        await _registerNewUser();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  /// Opens the account-recovery screen, pre-filled with whatever email is
  /// already typed. The reset email itself is requested there, through
  /// request_password_reset.php (same endpoint as the web), so it is sent
  /// from the shop's Gmail in the BLOOM design.
  ///
  /// Deliberately NOT blocked by the login lockout, and it no longer counts
  /// as a failed login attempt: a locked-out customer is exactly the person
  /// who needs a reset. The server has its own reset-specific rate limits.
  void _openForgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ForgotPasswordPage(initialEmail: _emailController.text.trim()),
      ),
    );
  }

  Future<void> _loginWithPassword() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter email and password')));
      return;
    }

    if (await _isRateLimited()) return;

    setState(() => _isLoading = true);

    try {
      UserCredential userCredential;
      try {
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } catch (authError) {
        // A network failure during Auth itself means we genuinely don't
        // know whether the password was right or wrong — Firebase never got
        // far enough to check. Rethrow the ORIGINAL exception so the outer
        // catch below can still see its .code and recognize it as a
        // connectivity failure, instead of falling into the Firestore
        // fallback query, which needs the same connection that just failed.
        if (authError is FirebaseAuthException && authError.code == 'network-request-failed') {
          rethrow;
        }

        final query = await _firestore.collection('customers').where('email', isEqualTo: email).limit(1).get();
        if (query.docs.isNotEmpty) {
          throw Exception('Incorrect password. If this is an older account, please use "Forgot Password?" to reset it securely.');
        } else {
          throw Exception('Account not found. Please click "REGISTER HERE" to sign up.');
        }
      }

      final uid = userCredential.user!.uid;

      String deviceHash = await _securityService.getDeviceHash();
      final deviceBannedSnap = await _firestore.collection('banned_devices').doc(deviceHash).get();
      if (deviceBannedSnap.exists) {
        await FirebaseAuth.instance.signOut();
        throw Exception('This device has been banned due to suspicious activity.');
      }

      await _securityService.resetAttempts();

      final customerDoc = await _firestore.collection('customers').doc(uid).get();
      if (!customerDoc.exists) {
        final emailQuery = await _firestore.collection('customers').where('email', isEqualTo: email).limit(1).get();

        if (emailQuery.docs.isNotEmpty) {
          final existingDoc = emailQuery.docs.first;
          final userData = existingDoc.data();
          final oldId = existingDoc.id;

          if (oldId != uid) {
            final sanitizedUserData = Map<String, dynamic>.from(userData)..remove('password');

            await _firestore.collection('customers').doc(uid).set({
              ...sanitizedUserData,
              'lastLogin': FieldValue.serverTimestamp(),
              'migratedFrom': oldId,
            }, SetOptions(merge: true));
            await _firestore.collection('customers').doc(oldId).delete();
          }
        }
      }

      final verificationCheckDoc = await _firestore.collection('customers').doc(uid).get();
      final requiresVerification = verificationCheckDoc.data()?['requireEmailVerification'] == true;
      if (requiresVerification) {
        await userCredential.user!.reload();
        final refreshedUser = FirebaseAuth.instance.currentUser;
        if (refreshedUser != null && !refreshedUser.emailVerified) {
          setState(() => _isLoading = false);
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => EmailVerificationPendingPage(customerId: uid)),
            );
          }
          return;
        }
      }

      final existingUserDoc = await _firestore.collection('users').doc(uid).get();
      final existingDocData = existingUserDoc.data();
      final existingRole = existingDocData != null ? existingDocData['role'] : null;
      if (existingRole == null || existingRole == 'customer') {
        await _firestore.collection('users').doc(uid).set({
          'role': 'customer',
          'email': email,
          'customerId': uid,
        }, SetOptions(merge: true));
      }

      if (mounted) {
        if (widget.returnAfterLogin) {
          widget.onLoginSuccess?.call();
          Navigator.pop(context, true);
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => CustomerProfilePage(email: email, customerId: uid)),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);

      // Distinguish "couldn't verify your credentials because
      // Firebase/Firestore is unreachable" from "credentials are actually
      // wrong" — same logic as web's index.php. Neither connectivity error
      // means the password was wrong, so neither should burn a lockout
      // attempt or show the generic credential-failure message.
      final isConnectivityError =
          (e is FirebaseAuthException && e.code == 'network-request-failed') ||
              (e is FirebaseException && e.code == 'unavailable');

      if (isConnectivityError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Couldn't reach the server. Check your internet connection and try again."),
              backgroundColor: Colors.orangeAccent,
            ),
          );
        }
        return;
      }

      await _securityService.recordFailedAttempt();
      await _isRateLimited();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.redAccent));
    }
  }

  bool _isDisposableEmail(String email) {
    if (!email.contains('@')) return true;
    final domain = email.split('@')[1].toLowerCase().trim();
    const disposableDomains = [
      'mailinator.com', 'tempmail.com', 'guerrillamail.com', '10minutemail.com',
      'trashmail.com', 'dispostable.com', 'getnada.com', 'sharklasers.com',
      'yopmail.com', 'temp-mail.org', 'fakeinbox.com'
    ];
    return disposableDomains.contains(domain);
  }

  Future<void> _checkDeviceAndNetworkSecurity(String email) async {
    if (_isDisposableEmail(email)) {
      throw Exception('Disposable / temporary email addresses are restricted.');
    }

    final blocklistSnap = await _firestore.collection('blocked_emails').doc(email).get();
    if (blocklistSnap.exists) {
      throw Exception('Security Restriction: This email address is permanently blacklisted.');
    }

    final domain = email.contains('@') ? email.split('@')[1].toLowerCase() : '';
    final bannedSnap = await _firestore.collection('banned_devices').get();
    for (var doc in bannedSnap.docs) {
      final data = doc.data();
      final bannedEmail = (data['email'] ?? '').toString().toLowerCase();
      final bannedDomain = (data['emailDomain'] ?? '').toString().toLowerCase();

      if ((bannedEmail.isNotEmpty && bannedEmail == email.toLowerCase()) ||
          (bannedDomain.isNotEmpty && bannedDomain == domain && !['gmail.com', 'yahoo.com', 'outlook.com', 'hotmail.com'].contains(domain))) {
        throw Exception('Security Warning: This device or network signature is flagged. Registration restricted.');
      }
    }
  }

  Future<void> _registerNewUser() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    final fName = _firstNameController.text.trim();
    final lName = _lastNameController.text.trim();
    final mName = _middleNameController.text.trim();

    setState(() => _isLoading = true);

    try {
      String deviceHash = await _securityService.getDeviceHash();
      final deviceBannedSnap = await _firestore.collection('banned_devices').doc(deviceHash).get();
      if (deviceBannedSnap.exists) {
        throw Exception('Security Warning: This device has been banned due to suspicious activity.');
      }

      await _checkDeviceAndNetworkSecurity(email);

      RegistrationRiskResult? riskResult = await _registrationRiskService.checkEmail(email);
      if (riskResult.blocked) {
        throw Exception(riskResult.reason ?? 'This email could not be verified.');
      }

      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      String uid = userCredential.user!.uid;

      int existingPoints = 0;
      final existingQuery = await _firestore.collection('customers').where('email', isEqualTo: email).limit(1).get();

      if (existingQuery.docs.isNotEmpty) {
        final existingDoc = existingQuery.docs.first;
        existingPoints = existingDoc.data()['points'] ?? 0;
        if (existingDoc.id != uid) {
          await _firestore.collection('customers').doc(existingDoc.id).delete();
        }
      }

      final fullName = '$fName ${mName.isNotEmpty ? '$mName ' : ''}$lName'.trim();

      final customerData = {
        'firstName': fName,
        'middleName': mName,
        'lastName': lName,
        'fullName': fullName,
        'name': fullName,
        'birthday': _selectedBirthday?.toIso8601String().split('T')[0],
        'sex': _selectedSex,
        'points': existingPoints,
        'createdAt': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
        'deviceHashes': [deviceHash],
        'email': email,
        'requireEmailVerification': true,
        'agreedToTermsAt': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('customers').doc(uid).set(customerData, SetOptions(merge: true));

      final existingUserDoc = await _firestore.collection('users').doc(uid).get();
      final existingDocData = existingUserDoc.data();
      final existingRole = existingDocData != null ? existingDocData['role'] : null;
      if (existingRole == null || existingRole == 'customer') {
        final userData = {
          'role': 'customer',
          'customerId': uid,
          'email': email,
        };
        await _firestore.collection('users').doc(uid).set(userData, SetOptions(merge: true));
      }

      if (riskResult.flagged && riskResult.scoreBump > 0) {
        await _registrationRiskService.recordScore(riskResult.scoreBump);
      }

      bool primarySucceeded = false;
      try {
        final result = await _emailVerificationService.sendVerificationEmail();
        primarySucceeded = result.success;
        if (!result.success) {
          debugPrint('Custom verification email failed (${result.message}) — falling back to Firebase native.');
        }
      } catch (verifyError) {
        debugPrint('Custom verification email threw an exception — falling back to Firebase native: $verifyError');
      }

      if (!primarySucceeded) {
        try {
          await userCredential.user!.sendEmailVerification();
        } catch (fallbackError) {
          debugPrint('Firebase native sendEmailVerification also failed: $fallbackError');
        }
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => EmailVerificationPendingPage(customerId: uid)),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _showTermsDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF2A241D) : Colors.white;
    final textColor = isDark ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A1A);
    final subTextColor = isDark ? const Color(0xFFA0998F) : const Color(0xFF9E9E9E);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 640),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Terms of Service',
                          style: GoogleFonts.cormorantGaramond(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: subTextColor),
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _tosParagraph(
                          'By placing an order on this website or mobile application, you are agreeing to the following terms and conditions:',
                          textColor,
                        ),
                        _tosSection('Order Acceptance Policy', textColor, subTextColor),
                        _tosParagraph(
                          'All orders and online requests received are subject to acceptance by Bloominous Flower Shop. We reserve the right, at our absolute discretion, to reject or cancel any order without giving prior reasons (e.g., due to stock depletion or system fraud flags). In the event of an order rejection by our management, any payment received will be refunded or canceled in full via the original payment method used.',
                          textColor,
                        ),
                        _tosSection('Delivery & Pickup Policy', textColor, subTextColor),
                        _tosParagraph(
                          'Flower deliveries are available from Mondays to Sundays. For online ordering, customers may select their preferred fulfillment mode: Cash on Delivery (COD), Store Pick-up, or E-Wallet payment. For same-day deliveries, orders must be placed within the available operational hours of the target branches. Specific time-slot deliveries are subject to local traffic conditions and courier availability. While we strive for punctuality, Bloominous Flower Shop cannot be held liable for late deliveries caused by severe weather conditions, extreme traffic, or factors outside our control. The sender is responsible for providing accurate recipient details (full name, complete address, and active contact number). If a delivery fails due to incorrect customer details or an uncontactable recipient, a re-delivery fee may apply.',
                          textColor,
                        ),
                        _tosSection('Changes to Your Order', textColor, subTextColor),
                        _tosParagraph(
                          'If you wish to make changes to your order (including delivery addresses or card greeting messages), please contact our team immediately through our official channels. For scheduled or pre-orders, request changes at least one day prior to the delivery date. For same-day orders, we will make every effort to accommodate modifications, but changes cannot be guaranteed once processing has begun.',
                          textColor,
                        ),
                        _tosSection('Cancellation & Refund Policy', textColor, subTextColor),
                        _tosParagraph(
                          'Advance / Pre-Orders: Cancellations requested before the order goes into the preparation pipeline may be granted and processed via store credit or account balance adjustment. Same-Day & Custom AR Orders: Orders that have already been prepared, assembled, or dispatched by our florists cannot be canceled or refunded due to the perishable nature of floral stocks. Non-Refundable Policy: Strictly no cash refund transactions are permitted once a floral arrangement has been custom-built, accepted, or successfully delivered. If an order cannot be fulfilled by our shop due to unforeseen supply issues, a full replacement or reimbursement will be issued.',
                          textColor,
                        ),
                        _tosSection('Product, AR Customization, and Substitution Policy', textColor, subTextColor),
                        _tosParagraph(
                          'Perishable Nature: Flowers are natural, perishable goods. Their actual color, shade, bouquet size, fillers and bloom stage may slightly vary from visual previews. Augmented Reality (AR) Previews: The 3D and AR customization modules within our web and mobile application serve as interactive visual references. While AR models provide a 3D preview of arrangement styles, wrappers, and ribbons, minor differences between the digital preview and the physical hand-crafted arrangement may occur. Substitutions: All items are subject to live stock availability. If specific flower species, wrapper colors, or accessories become unavailable, Bloominous Flower Shop reserves the right to substitute them with materials of equivalent or greater value and quality to maintain the design aesthetic.',
                          textColor,
                        ),
                        _tosSection('Payments', textColor, subTextColor),
                        _tosParagraph(
                          'We accept Cash on Pick-up, Cash on Delivery (COD), and digital E-Wallets (GCash, PayMaya, etc.). Online e-wallet transactions and digital receipts are validated securely through integrated payment channels. We do not store sensitive payment card credentials directly on our local servers.',
                          textColor,
                        ),
                        _tosSection('Freshness & Quality Assurance', textColor, subTextColor),
                        _tosParagraph(
                          'We are committed to delivering fresh floral arrangements. Fresh flowers are visually scanned and monitored using our integrated freshness tracking tools. If you receive flowers that are severely damaged or defective upon arrival, you must report the issue within 24 hours of receipt by providing your Order ID and clear photographs of the product. Valid reports will be reviewed by our customer support for a replacement on the next available delivery date.',
                          textColor,
                        ),
                        _tosSection('Promos & Discount Vouchers', textColor, subTextColor),
                        _tosParagraph(
                          'Discount vouchers and promotional promo codes may be issued periodically at our discretion. Promotional codes cannot be combined with other active discounts or retroactively applied to completed orders. Bloominous Flower Shop reserves the right to modify or discontinue promo offers without prior notice.',
                          textColor,
                        ),
                        _tosSection('Force Majeure & Uncontrollable Circumstances', textColor, subTextColor),
                        _tosParagraph(
                          'Bloominous Flower Shop shall not be liable for delayed performance or delivery failures resulting from severe weather conditions (typhoons, heavy floods), acts of God, government restrictions, power outages, system network disruptions, or other events beyond our reasonable control.',
                          textColor,
                        ),
                        _tosSection('Customer Information & Privacy', textColor, subTextColor),
                        _tosParagraph(
                          'We value your privacy. Personal information collected during account registration and checkout—such as your full name, contact details, email address, and recipient address—is strictly used to fulfill transactions, process orders, send status updates, and improve user service. We do not lease, sell, or rent your personal information to third parties.',
                          textColor,
                        ),
                        _tosSection('Store Details & Operating Headquarters', textColor, subTextColor),
                        _tosParagraph(
                          'Bloominous Flower Shop. Operating Hours: 12 Hours Daily (Catering to Walk-in & Online Customers).',
                          textColor,
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryGold,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('I Understand', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tosSection(String title, Color textColor, Color subTextColor) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: textColor,
        ),
      ),
    );
  }

  Widget _tosParagraph(String text, Color textColor) {
    return Text(
      text,
      style: TextStyle(fontSize: 12.5, height: 1.5, color: textColor.withOpacity(0.85)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1814) : const Color(0xFFFCF9F5);
    final cardColor = isDark ? const Color(0xFF2A241D) : Colors.white;
    final textColor = isDark ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A1A);
    final subTextColor = isDark ? const Color(0xFFA0998F) : const Color(0xFF9E9E9E);
    final borderColor = isDark ? const Color(0xFF3F382F) : const Color(0xFFE0E0E0);
    final inputFillColor = isDark ? const Color(0xFF221D17) : Colors.white;

    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 380;
    final outerHorizontalPadding = isNarrow ? 12.0 : 24.0;
    final cardHorizontalPadding = isNarrow ? 22.0 : 40.0;
    final cardVerticalPadding = isNarrow ? 36.0 : 56.0;

    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: outerHorizontalPadding, vertical: 40.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450),
            padding: EdgeInsets.symmetric(horizontal: cardHorizontalPadding, vertical: cardVerticalPadding),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.4 : 0.04),
                  blurRadius: 40,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'B L O O M',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: _primaryGold,
                    letterSpacing: 4.0,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _isSigningUp ? 'Create an Account' : 'Authenticated Access',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 34,
                    color: textColor,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isSigningUp ? 'CUSTOMER REGISTRATION' : 'MANAGEMENT CONSOLE LOGIN',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: subTextColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 48),

                if (_superAdminLocked || _remainingLockoutSeconds > 0)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(isDark ? 0.15 : 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_clock, color: Colors.redAccent, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _superAdminLocked
                                ? 'Account locked. Please coordinate with a Super Admin.'
                                : 'Too many attempts. Please wait $_remainingLockoutSeconds seconds.',
                            style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_isSigningUp) ...[
                  _buildTextField(
                    controller: _firstNameController,
                    hint: 'First Name',
                    textColor: textColor,
                    subTextColor: subTextColor,
                    borderColor: borderColor,
                    fillColor: inputFillColor,
                  ),
                  _buildTextField(
                    controller: _middleNameController,
                    hint: 'Middle Name',
                    textColor: textColor,
                    subTextColor: subTextColor,
                    borderColor: borderColor,
                    fillColor: inputFillColor,
                  ),
                  _buildTextField(
                    controller: _lastNameController,
                    hint: 'Last Name',
                    textColor: textColor,
                    subTextColor: subTextColor,
                    borderColor: borderColor,
                    fillColor: inputFillColor,
                  ),
                  GestureDetector(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime(2000),
                        firstDate: DateTime(1950),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) setState(() => _selectedBirthday = date);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                      decoration: BoxDecoration(
                        color: inputFillColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor, width: 1),
                      ),
                      child: Text(
                        _selectedBirthday == null ? 'Select Birthday' : 'Birthday: ${_selectedBirthday!.toIso8601String().split('T')[0]}',
                        style: TextStyle(color: _selectedBirthday == null ? subTextColor : textColor, fontSize: 15),
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: inputFillColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor, width: 1),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedSex,
                        isExpanded: true,
                        dropdownColor: cardColor,
                        icon: Icon(Icons.arrow_drop_down, color: subTextColor),
                        style: TextStyle(color: textColor, fontSize: 15),
                        items: const [
                          DropdownMenuItem(value: 'Male', child: Text('Male')),
                          DropdownMenuItem(value: 'Female', child: Text('Female')),
                        ],
                        onChanged: (val) => setState(() => _selectedSex = val!),
                      ),
                    ),
                  ),
                ],

                _buildTextField(
                  controller: _emailController,
                  hint: 'Email Address',
                  keyboardType: TextInputType.emailAddress,
                  textColor: textColor,
                  subTextColor: subTextColor,
                  borderColor: borderColor,
                  fillColor: inputFillColor,
                ),

                _buildTextField(
                  controller: _passwordController,
                  hint: 'Password',
                  isPassword: true,
                  obscureText: _obscurePassword,
                  onToggleVisibility: () => setState(() => _obscurePassword = !_obscurePassword),
                  textColor: textColor,
                  subTextColor: subTextColor,
                  borderColor: borderColor,
                  fillColor: inputFillColor,
                ),

                if (_isSigningUp)
                  _buildTextField(
                    controller: _confirmPasswordController,
                    hint: 'Confirm Password',
                    isPassword: true,
                    obscureText: _obscurePassword,
                    textColor: textColor,
                    subTextColor: subTextColor,
                    borderColor: borderColor,
                    fillColor: inputFillColor,
                  ),

                if (_isSigningUp)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: inputFillColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor, width: 1),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: Checkbox(
                            value: _agreedToTerms,
                            activeColor: _primaryGold,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            onChanged: (val) => setState(() => _agreedToTerms = val ?? false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(fontSize: 12.5, height: 1.45, color: textColor),
                                children: [
                                  const TextSpan(text: 'I have read and agree to the '),
                                  TextSpan(
                                    text: 'Terms and Conditions',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _primaryGold,
                                      decoration: TextDecoration.underline,
                                    ),
                                    recognizer: _termsTapRecognizer,
                                  ),
                                  const TextSpan(text: ' of Bloominous Flower Shop.'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (!_isSigningUp)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      // Only disabled while a login is in progress. NOT
                      // disabled by the login lockout: locked-out customers
                      // are the ones who most need a reset.
                      onPressed: _isLoading ? null : _openForgotPassword,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(50, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Forgot Password?',
                        style: TextStyle(color: subTextColor, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                const SizedBox(height: 32),

                _buildPrimaryButton(
                  onPressed: (_isLoading || _superAdminLocked || _remainingLockoutSeconds > 0)
                      ? null
                      : (_isSigningUp ? _handleContinue : _loginWithPassword),
                  text: _isSigningUp ? 'REGISTER' : 'LOGIN',
                  isLoading: _isLoading,
                ),

                const SizedBox(height: 32),

                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    Text(
                      _isSigningUp ? "Already have an account?  " : "Don't have an account?  ",
                      style: TextStyle(color: subTextColor, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    GestureDetector(
                      onTap: () => setState(() {
                        _isSigningUp = !_isSigningUp;
                        _emailController.clear();
                        _passwordController.clear();
                        _agreedToTerms = false;
                      }),
                      child: Text(
                        _isSigningUp ? 'LOGIN HERE' : 'REGISTER HERE',
                        style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required Color textColor,
    required Color subTextColor,
    required Color borderColor,
    required Color fillColor,
    TextInputType keyboardType = TextInputType.text,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        style: TextStyle(
          fontSize: 15,
          color: textColor,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: subTextColor, fontSize: 15),
          filled: true,
          fillColor: fillColor,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _primaryGold, width: 1.5),
          ),
          suffixIcon: isPassword && onToggleVisibility != null
              ? IconButton(
            icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility, color: subTextColor, size: 20),
            onPressed: onToggleVisibility,
          )
              : null,
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required VoidCallback? onPressed,
    required String text,
    bool isLoading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryGold,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          disabledBackgroundColor: _primaryGold.withOpacity(0.5),
        ),
        child: isLoading
            ? const SizedBox(
          width: 24, height: 24,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        )
            : Text(
          text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.white),
        ),
      ),
    );
  }
}