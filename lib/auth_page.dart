import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'main.dart'; // Idagdag ito para makita ang HomePage
import 'inventory_data.dart';
import 'admin_dashboard.dart';
import 'my_orders_page.dart';
import 'customer_profile_page.dart';

class AuthPage extends StatefulWidget {
  final bool returnAfterLogin;
  final VoidCallback? onLoginSuccess;
  const AuthPage(
      {super.key, this.returnAfterLogin = false, this.onLoginSuccess});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  DateTime? _selectedBirthday;
  String _selectedSex = 'Male';

  bool _isPhoneAuth = false;
  String? _verificationId;
  bool _isOtpSent = false;
  bool _isLoading = false;
  bool _isExistingUser = false;
  bool _showPasswordField = false;
  bool _isSettingPassword = false;
  bool _obscurePassword = true;
  bool _isSigningUp = false;

  String? _generatedOtp;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  Future<void> _checkExistingSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      final email = user.email;
      final phone = user.phoneNumber;
      if (email == null && phone == null) return;
      final identifier = email ?? phone ?? '';

      // 1. Try to find the customer document by the CURRENT UID
      final customerDoc =
          await _firestore.collection('customers').doc(user.uid).get();

      if (customerDoc.exists) {
        // Doc already exists at the correct ID
        if (mounted) {
          if (widget.returnAfterLogin) {
            widget.onLoginSuccess?.call();
            Navigator.pop(context, true);
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (context) => CustomerProfilePage(
                      email: identifier, customerId: user.uid)),
            );
          }
        }
        return;
      } else {
        // 2. FALLBACK: Direct UID lookup failed. Search by EMAIL or PHONE.
        QuerySnapshot? emailQuery;
        if (email != null) {
          emailQuery = await _firestore
              .collection('customers')
              .where('email', isEqualTo: email.toLowerCase())
              .limit(1)
              .get();
        }

        QuerySnapshot? phoneQuery;
        if (phone != null) {
          phoneQuery = await _firestore
              .collection('customers')
              .where('phone', isEqualTo: phone)
              .limit(1)
              .get();
        }

        final docs = (emailQuery != null && emailQuery.docs.isNotEmpty)
            ? emailQuery.docs
            : (phoneQuery != null && phoneQuery.docs.isNotEmpty)
                ? phoneQuery.docs
                : null;

        if (docs != null && docs.isNotEmpty) {
          final existingDoc = docs.first;
          final userData = existingDoc.data() as Map<String, dynamic>;
          final oldDocId = existingDoc.id;

          // Migrate data to the current UID
          await _firestore.collection('customers').doc(user.uid).set({
            ...userData,
            'lastLogin': FieldValue.serverTimestamp(),
            'migratedFrom': oldDocId,
          }, SetOptions(merge: true));

          // Delete old doc ID if it's different
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
                MaterialPageRoute(
                    builder: (context) => CustomerProfilePage(
                        email: identifier, customerId: user.uid)),
              );
            }
          }
          return;
        } else {
          // No record found at all. This might be a fresh user or a deletion happened.
          // We can proceed to profile but it will show 0 points or allow fresh setup.
        }
      }
    }
  }

  void _showTestPhoneGuideDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFFFFFDF9),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.phonelink_setup_rounded,
                  color: Color(0xFFF4B400), size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Firebase Test Phone Guide',
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF121212),
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Paano mag-add ng Test Phone Number sa Firebase Console (LIBRE):',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF121212)),
                ),
                const SizedBox(height: 10),
                const Text(
                  '1️⃣ Pumunta sa Firebase Console:\n   https://console.firebase.google.com/\n\n'
                  '2️⃣ Buksan ang iyong Project ➔ Authentication ➔ Sign-in method tab.\n\n'
                  '3️⃣ I-click ang "Phone" provider.\n\n'
                  '4️⃣ Sa pinaka-ibaba, i-expand ang "Phone numbers for testing".\n\n'
                  '5️⃣ Maglagay ng Phone Number (Halimbawa: +639983082080) at Test Code (Halimbawa: 123456).\n\n'
                  '6️⃣ I-click ang "Save".',
                  style: TextStyle(
                      fontSize: 13, color: Color(0xFF444444), height: 1.4),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121212).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFF4B400).withOpacity(0.4)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '💡 Paano gagamitin sa App?',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF121212)),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Pagkatapos mong ilagay sa Firebase Console, i-type lang ang iyong test number sa app. Lalabas ang OTP screen at i-enter ang preset code (hal. 123456) para makapasok agad!',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF666666)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Naintindihan Ko',
                  style: TextStyle(
                      color: Color(0xFF121212), fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showBillingErrorDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFFFFFDF9),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.amber, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'SMS Billing Not Enabled',
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF121212),
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Naka-disable ang SMS Billing sa Firebase project backend. Kakailanganin ng Firebase Blaze Plan upang makapagpadala ng totoong SMS.',
                style: TextStyle(
                    fontSize: 14, color: Color(0xFF333333), height: 1.4),
              ),
              const SizedBox(height: 12),
              const Text(
                'Mga Libreng Alternatibo:',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF121212)),
              ),
              const SizedBox(height: 6),
              const Text(
                '• Mag-add ng Test Phone Number sa Firebase Console.\n• O gamitin ang Email OTP (Gumagana agad).',
                style: TextStyle(
                    fontSize: 13, color: Color(0xFF555555), height: 1.4),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showTestPhoneGuideDialog();
              },
              child: const Text('Paano Mag-add ng Test Number?',
                  style: TextStyle(
                      color: Color(0xFFF4B400), fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF121212),
                foregroundColor: const Color(0xFFF4B400),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(context);
                _showOtpTargetSelectionSheet();
              },
              child: const Text('Gamitin ang Email OTP'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendSmsOtp() async {
    String rawPhone = _phoneController.text.trim();
    if (rawPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a phone number')),
      );
      return;
    }

    // Format the phone number. Prepend +63 if it doesn't start with + and starts with 9 or 09
    String phoneNumber = rawPhone;
    if (!phoneNumber.startsWith('+')) {
      if (phoneNumber.startsWith('09')) {
        phoneNumber = '+63${phoneNumber.substring(2)}';
      } else if (phoneNumber.startsWith('9')) {
        phoneNumber = '+63$phoneNumber';
      } else {
        // Assume default +63
        phoneNumber = '+63$phoneNumber';
      }
    }

    // Validate Philippine phone number digit count
    final digitsOnly = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (phoneNumber.startsWith('+63')) {
      final numberAfter63 =
          digitsOnly.startsWith('63') ? digitsOnly.substring(2) : digitsOnly;
      if (numberAfter63.length != 10) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Kulang o sobra ang digit ng phone number (${numberAfter63.length} digits lang). Dapat 10 digits pagkatapos ng +63 (halimbawa: 09171234567 o +639171234567).',
            ),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            final userCredential =
                await FirebaseAuth.instance.signInWithCredential(credential);
            final uid = userCredential.user!.uid;
            await _onPhoneLoginSuccess(uid, phoneNumber);
          } catch (e) {
            setState(() => _isLoading = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Auto-Verification failed: $e')));
            }
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isLoading = false);
          String message = e.message ?? 'Verification failed';
          final errStr = '${e.message ?? ''} ${e.code}';
          if (errStr.contains('BILLING_NOT_ENABLED') ||
              errStr.toLowerCase().contains('billing')) {
            if (mounted) {
              _showBillingErrorDialog();
            }
            return;
          }

          if (e.code == 'invalid-phone-number') {
            message = 'The provided phone number is not valid.';
          } else if (e.code == 'too-many-requests') {
            message =
                'SMS traffic is blocked due to too many requests. Please try again later.';
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(message), backgroundColor: Colors.redAccent));
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _isOtpSent = true;
            _isLoading = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Verification code sent to $phoneNumber!'),
                backgroundColor: const Color(0xFF121212),
              ),
            );
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        if (e.toString().contains('BILLING_NOT_ENABLED') ||
            e.toString().toLowerCase().contains('billing')) {
          _showBillingErrorDialog();
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _verifySmsOtp() async {
    final enteredOtp = _otpController.text.trim();
    if (enteredOtp.isEmpty || _verificationId == null) return;

    setState(() => _isLoading = true);

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: enteredOtp,
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final uid = userCredential.user!.uid;
      final phone =
          userCredential.user!.phoneNumber ?? _phoneController.text.trim();

      await _onPhoneLoginSuccess(uid, phone);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid code. Please try again: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _onPhoneLoginSuccess(String uid, String phone) async {
    setState(() => _isLoading = true);
    try {
      final customerDoc =
          await _firestore.collection('customers').doc(uid).get();
      if (customerDoc.exists) {
        await _firestore.collection('users').doc(uid).set({
          'role': 'customer',
          'phone': phone,
          'customerId': uid,
        }, SetOptions(merge: true));

        if (mounted) {
          if (widget.returnAfterLogin) {
            widget.onLoginSuccess?.call();
            Navigator.pop(context, true);
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (context) =>
                      CustomerProfilePage(email: phone, customerId: uid)),
            );
          }
        }
      } else {
        final fName = _firstNameController.text.trim();
        final lName = _lastNameController.text.trim();
        if (fName.isNotEmpty && lName.isNotEmpty) {
          final mName = _middleNameController.text.trim();
          final fullName =
              '$fName ${mName.isNotEmpty ? '$mName ' : ''}$lName'.trim();
          final email = _emailController.text.trim().toLowerCase();

          await _firestore.collection('customers').doc(uid).set({
            'firstName': fName,
            'middleName': mName,
            'lastName': lName,
            'fullName': fullName,
            'name': fullName,
            'birthday': _selectedBirthday?.toIso8601String().split('T')[0],
            'sex': _selectedSex,
            'phone': phone,
            'email': email,
            'points': 0,
            'createdAt': FieldValue.serverTimestamp(),
            'created_at': FieldValue.serverTimestamp(),
            'lastLogin': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          await _firestore.collection('users').doc(uid).set({
            'role': 'customer',
            'phone': phone,
            'customerId': uid,
          }, SetOptions(merge: true));

          if (mounted) {
            if (widget.returnAfterLogin) {
              widget.onLoginSuccess?.call();
              Navigator.pop(context, true);
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                        CustomerProfilePage(email: phone, customerId: uid)),
              );
            }
          }
        } else {
          final query = await _firestore
              .collection('customers')
              .where('phone', isEqualTo: phone)
              .limit(1)
              .get();
          if (query.docs.isNotEmpty) {
            final existingDoc = query.docs.first;
            final userData = existingDoc.data();
            final oldId = existingDoc.id;

            if (oldId != uid) {
              await _firestore.collection('customers').doc(uid).set({
                ...userData,
                'lastLogin': FieldValue.serverTimestamp(),
                'migratedFrom': oldId,
              }, SetOptions(merge: true));
              await _firestore.collection('customers').doc(oldId).delete();
            }

            await _firestore.collection('users').doc(uid).set({
              'role': 'customer',
              'phone': phone,
              'customerId': uid,
            }, SetOptions(merge: true));

            if (mounted) {
              if (widget.returnAfterLogin) {
                widget.onLoginSuccess?.call();
                Navigator.pop(context, true);
              } else {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (context) =>
                          CustomerProfilePage(email: phone, customerId: uid)),
                );
              }
            }
          } else {
            setState(() {
              _isOtpSent = false;
              _isSettingPassword = true;
              _isLoading = false;
            });
          }
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Session Error: $e')));
      }
    }
  }

  Future<void> _handleContinue() async {
    if (_isPhoneAuth) {
      final rawPhone = _phoneController.text.trim();
      if (rawPhone.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter a phone number')));
        return;
      }

      if (_isSigningUp) {
        final fName = _firstNameController.text.trim();
        final lName = _lastNameController.text.trim();

        if (fName.isEmpty || lName.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Please enter your first and last name')));
          return;
        }
        if (_selectedBirthday == null) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please select your birthday')));
          return;
        }
        await _sendSmsOtp();
      } else {
        _showOtpTargetSelectionSheetForPhone();
      }
      return;
    }

    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid email')));
      return;
    }

    if (_isSigningUp) {
      final fName = _firstNameController.text.trim();
      final lName = _lastNameController.text.trim();
      final password = _passwordController.text.trim();
      final confirmPassword = _confirmPasswordController.text.trim();

      if (fName.isEmpty || lName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Please enter your first and last name')));
        return;
      }
      if (_selectedBirthday == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select your birthday')));
        return;
      }
      if (password.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Password must be at least 6 characters')));
        return;
      }
      if (password != confirmPassword) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Passwords do not match')));
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      // Prevent admin/staff/employee/delivery from using the customer portal, as it can cause session confusion or role overwriting
      final employeeQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (employeeQuery.docs.isNotEmpty) {
        final role = employeeQuery.docs.first.data()['role'];
        if (role != null && role != 'customer') {
          setState(() => _isLoading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'This email is registered as an Employee/Admin ($role). Please use the Employee Portal on the Home screen to log in.'),
                backgroundColor: Colors.orangeAccent,
              ),
            );
          }
          return;
        }
      }

      if (_isSigningUp) {
        // Mode: Explicit Sign Up
        // Check if email ALREADY exists
        final query = await _firestore
            .collection('customers')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          setState(() {
            _isSigningUp = false;
            _isExistingUser = true;
            _showPasswordField = true;
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Email already exists. Please sign in.')));
          return;
        }
        _sendOtp();
      } else {
        // Mode: Login Check
        final query = await _firestore
            .collection('customers')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          setState(() {
            _isExistingUser = true;
            _showPasswordField = true;
            _isLoading = false;
          });
        } else {
          // If not found in login mode, we can either automatically start signup or ask
          _sendOtp(); // Auto-start signup with OTP
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enter your email to reset password.')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset link sent to your email!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithPassword() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (password.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      // 1. PROPER LOGIN using Firebase Auth
      UserCredential userCredential;
      try {
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } catch (authError) {
        // FALLBACK: Legacy user check (Firestore-only accounts)
        final query = await _firestore
            .collection('customers')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          final userData = query.docs.first.data();
          final storedPassword = userData['password'];
          if (storedPassword == password) {
            userCredential =
                await FirebaseAuth.instance.createUserWithEmailAndPassword(
              email: email,
              password: password,
            );
          } else {
            throw Exception('Incorrect password.');
          }
        } else {
          rethrow;
        }
      }

      final uid = userCredential.user!.uid;

      // 2. SELF-REPAIR / MIGRATION CHECK
      final customerDoc =
          await _firestore.collection('customers').doc(uid).get();
      if (!customerDoc.exists) {
        final emailQuery = await _firestore
            .collection('customers')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();

        if (emailQuery.docs.isNotEmpty) {
          final existingDoc = emailQuery.docs.first;
          final userData = existingDoc.data();
          final oldId = existingDoc.id;

          if (oldId != uid) {
            await _firestore.collection('customers').doc(uid).set({
              ...userData,
              'password': 'migrated_to_auth',
              'lastLogin': FieldValue.serverTimestamp(),
              'migratedFrom': oldId,
            }, SetOptions(merge: true));
            await _firestore.collection('customers').doc(oldId).delete();
          }
        } else {
          final fallbackFName = _firstNameController.text.trim().isNotEmpty
              ? _firstNameController.text.trim()
              : 'Floral';
          final fallbackLName = _lastNameController.text.trim().isNotEmpty
              ? _lastNameController.text.trim()
              : 'Enthusiast';
          final fallbackMName = _middleNameController.text.trim();
          final fallbackFullName =
              '$fallbackFName ${fallbackMName.isNotEmpty ? '$fallbackMName ' : ''}$fallbackLName'
                  .trim();

          await _firestore.collection('customers').doc(uid).set({
            'firstName': fallbackFName,
            'lastName': fallbackLName,
            'middleName': fallbackMName,
            'fullName': fallbackFullName,
            'name': fallbackFullName,
            'birthday': _selectedBirthday?.toIso8601String().split('T')[0],
            'sex': _selectedSex,
            'email': email,
            'points': 0,
            'createdAt': FieldValue.serverTimestamp(),
            'created_at': FieldValue.serverTimestamp(),
            'lastLogin': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }

      // 3. Ensure User Role Sync (Only for non-employees to prevent role downgrading/overwriting)
      final existingUserDoc =
          await _firestore.collection('users').doc(uid).get();
      final existingDocData = existingUserDoc.data();
      final existingRole =
          existingDocData != null ? existingDocData['role'] : null;
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
            MaterialPageRoute(
                builder: (context) =>
                    CustomerProfilePage(email: email, customerId: uid)),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
    }
  }

  // ... (Keep existing EmailJS and OTP generation methods)

  // EmailJS Credentials matching dashboard screenshot
  final String _emailJsServiceId = 'service_o3ezmmu';
  final String _emailJsTemplateId = 'template_xxvpjru';
  final String _emailJsPublicKey = 'Mm9xloWH69DjgykmX';

  // Generate a random 6-digit PIN
  String _generatePin() {
    var rng = Random();
    var code = rng.nextInt(900000) + 100000;
    return code.toString();
  }

  Future<void> _sendEmailJS(String email, String otp) async {
    final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'origin': 'http://localhost',
        },
        body: jsonEncode({
          'service_id': _emailJsServiceId,
          'template_id': _emailJsTemplateId,
          'user_id': _emailJsPublicKey,
          'template_params': {
            'email': email,
            'passcode': otp,
            'time': '15 minutes',
          },
        }),
      );

      if (response.statusCode != 200) {
        // Ipakita ang totoong error message mula sa EmailJS
        throw Exception(
            'EmailJS Error (${response.statusCode}): ${response.body}');
      }
      print('Email sent successfully via EmailJS');
    } catch (e) {
      print('EmailJS Error: $e');
      rethrow; // I-pasa ang totoong error sa _sendOtp
    }
  }

  void _showEnterPhoneDialog(String? customerDocId) {
    final TextEditingController tempPhoneController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFFFFFDF9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Enter Phone Number',
            style: GoogleFonts.cormorantGaramond(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF121212),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter your phone number to receive a 6-digit verification code.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF666666),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: tempPhoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Color(0xFF121212)),
                decoration: InputDecoration(
                  hintText: 'e.g., 09171234567',
                  hintStyle: const TextStyle(color: Color(0xFF999999)),
                  prefixIcon:
                      const Icon(Icons.phone_android, color: Color(0xFFF4B400)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: const Color(0xFF121212).withOpacity(0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Color(0xFFF4B400), width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF666666)),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final phone = tempPhoneController.text.trim();
                if (phone.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Please enter a phone number')),
                  );
                  return;
                }

                // Format phone number
                String formattedPhone = phone;
                if (!formattedPhone.startsWith('+')) {
                  if (formattedPhone.startsWith('09')) {
                    formattedPhone = '+63${formattedPhone.substring(2)}';
                  } else if (formattedPhone.startsWith('9')) {
                    formattedPhone = '+63$formattedPhone';
                  } else {
                    formattedPhone = '+63$formattedPhone';
                  }
                }

                Navigator.pop(context); // Close dialog

                setState(() => _isLoading = true);

                // Save to Firestore if customer document exists
                if (customerDocId != null) {
                  try {
                    await _firestore
                        .collection('customers')
                        .doc(customerDocId)
                        .update({
                      'phone': formattedPhone,
                    });
                    print(
                        "Updated customer record with phone: $formattedPhone");
                  } catch (e) {
                    print("Error updating phone number: $e");
                  }
                }

                setState(() {
                  _isPhoneAuth = true;
                  _phoneController.text = formattedPhone;
                  _showPasswordField = false;
                  _isExistingUser = false;
                  _isLoading = false;
                });

                _sendSmsOtp();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF121212),
                foregroundColor: const Color(0xFFF4B400),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Send OTP'),
            ),
          ],
        );
      },
    );
  }

  void _showOtpTargetSelectionSheet() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an email address first')),
      );
      return;
    }

    setState(() => _isLoading = true);

    String? registeredPhone;
    String? customerDocId;
    try {
      final query = await _firestore
          .collection('customers')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        customerDocId = query.docs.first.id;
        registeredPhone = query.docs.first.data()['phone'] as String?;
      }
    } catch (e) {
      print("Error looking up phone number: $e");
    }

    setState(() => _isLoading = false);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor:
          const Color(0xFFFFFDF9), // Beautiful warm/cream background
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Select OTP Delivery Method',
                textAlign: TextAlign.center,
                style: GoogleFonts.cormorantGaramond(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF121212),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Where would you like to receive your 6-digit verification code?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF666666),
                ),
              ),
              const SizedBox(height: 24),

              // Option 1: Email
              _buildOtpChoiceButton(
                icon: Icons.email_outlined,
                title: 'Send to Email',
                subtitle: email,
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _isPhoneAuth = false;
                    _showPasswordField = false;
                    _isExistingUser = false;
                  });
                  _sendOtp();
                },
              ),

              const SizedBox(height: 12),

              // Option 2: Phone Number (SMS)
              _buildOtpChoiceButton(
                icon: Icons.phone_android_outlined,
                title: 'Send to Phone (SMS)',
                subtitle:
                    (registeredPhone != null && registeredPhone.isNotEmpty)
                        ? registeredPhone
                        : 'No registered phone number found. Tap to enter.',
                disabled: false,
                onTap: () {
                  Navigator.pop(context);
                  if (registeredPhone != null && registeredPhone.isNotEmpty) {
                    setState(() {
                      _isPhoneAuth = true;
                      _phoneController.text = registeredPhone!;
                      _showPasswordField = false;
                      _isExistingUser = false;
                    });
                    _sendSmsOtp();
                  } else {
                    _showEnterPhoneDialog(customerDocId);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showOtpTargetSelectionSheetForPhone() async {
    final phoneInput = _phoneController.text.trim();
    if (phoneInput.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a phone number first')),
      );
      return;
    }

    // Format phone number
    String formattedPhone = phoneInput;
    if (!formattedPhone.startsWith('+')) {
      if (formattedPhone.startsWith('09')) {
        formattedPhone = '+63${formattedPhone.substring(2)}';
      } else if (formattedPhone.startsWith('9')) {
        formattedPhone = '+63$formattedPhone';
      } else {
        formattedPhone = '+63$formattedPhone';
      }
    }

    setState(() => _isLoading = true);

    String? registeredEmail;
    try {
      final query = await _firestore
          .collection('customers')
          .where('phone', isEqualTo: formattedPhone)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        registeredEmail = query.docs.first.data()['email'] as String?;
      }
    } catch (e) {
      print("Error looking up email: $e");
    }

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (registeredEmail == null || registeredEmail.isEmpty) {
      // Try fallback search with raw or '09' prefix if user has registered with that
      try {
        String rawNumber = phoneInput;
        if (rawNumber.startsWith('+63')) {
          rawNumber = '0' + rawNumber.substring(3);
        }
        final fallbackQuery = await _firestore
            .collection('customers')
            .where('phone', isEqualTo: rawNumber)
            .limit(1)
            .get();
        if (fallbackQuery.docs.isNotEmpty) {
          registeredEmail = fallbackQuery.docs.first.data()['email'] as String?;
        }
      } catch (e) {
        print("Error in fallback lookup: $e");
      }
    }

    if (registeredEmail == null || registeredEmail.isEmpty) {
      // If no email is associated, send SMS directly
      _sendSmsOtp();
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor:
          const Color(0xFFFFFDF9), // Beautiful warm/cream background
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Select OTP Delivery Method',
                textAlign: TextAlign.center,
                style: GoogleFonts.cormorantGaramond(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF121212),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Where would you like to receive your 6-digit verification code?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF666666),
                ),
              ),
              const SizedBox(height: 24),

              // Option 1: Phone (SMS)
              _buildOtpChoiceButton(
                icon: Icons.phone_android_outlined,
                title: 'Send to Phone (SMS)',
                subtitle: formattedPhone,
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _isPhoneAuth = true;
                    _showPasswordField = false;
                    _isExistingUser = false;
                  });
                  _sendSmsOtp();
                },
              ),

              const SizedBox(height: 12),

              // Option 2: Email
              _buildOtpChoiceButton(
                icon: Icons.email_outlined,
                title: 'Send to Email',
                subtitle: registeredEmail!,
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _isPhoneAuth = false;
                    _emailController.text = registeredEmail!;
                    _showPasswordField = false;
                    _isExistingUser = false;
                  });
                  _sendOtp();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOtpChoiceButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool disabled = false,
  }) {
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Opacity(
        opacity: disabled ? 0.5 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: disabled
                  ? const Color(0xFFE0E0E0)
                  : const Color(0xFF121212).withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4B400).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: const Color(0xFFF4B400)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF121212),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF666666),
                      ),
                    ),
                  ],
                ),
              ),
              if (!disabled)
                const Icon(Icons.arrow_forward_ios,
                    size: 14, color: Color(0xFF666666)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. CHECK IF A VALID OTP ALREADY EXISTS
      final existingDoc =
          await _firestore.collection('customer_otps').doc(email).get();

      if (existingDoc.exists) {
        final data = existingDoc.data() as Map<String, dynamic>;
        final expiresAtStr = data['expiresAt'] as String?;

        if (expiresAtStr != null) {
          final expiresAt = DateTime.parse(expiresAtStr);

          // Kung hindi pa expired ang lumang PIN, gamitin muna iyon
          if (DateTime.now().isBefore(expiresAt)) {
            setState(() {
              _isOtpSent = true;
              _isLoading = false;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'A valid PIN was already sent. Please check your inbox.'),
                  backgroundColor: Color(0xFF121212),
                ),
              );
            }
            return;
          }
        }
      }

      // 2. IF NO VALID OTP, GENERATE AND SEND A NEW ONE
      final otp = _generatePin();
      _generatedOtp = otp;

      // Store OTP in Firestore with expiration (5 minutes)
      await _firestore.collection('customer_otps').doc(email).set({
        'otp': otp,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt':
            DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
      });

      // SEND REAL EMAIL VIA EMAILJS
      await _sendEmailJS(email, otp);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification PIN sent to your email!'),
            backgroundColor: Color(0xFF121212),
          ),
        );
      }

      setState(() {
        _isOtpSent = true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      print("OTP Send Error: $e");
      if (mounted) {
        // Fallback to mock dialog if real sending fails (for testing purposes)
        _showMockDialog(email, _generatedOtp ?? '000000', e.toString());
      }
    }
  }

  void _showMockDialog(String email, String otp, String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFF8DC),
        title: const Text('Email Connection Error',
            style: TextStyle(color: Colors.red, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Real email failed: $error',
                style: const TextStyle(fontSize: 12)),
            const Divider(),
            const Text('For testing, use this PIN:'),
            const SizedBox(height: 8),
            Text(otp,
                style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    color: Color(0xFF5D4037))),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isOtpSent = true;
              });
            },
            child: const Text('Use PIN anyway',
                style: TextStyle(color: Color(0xFF5D4037))),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyOtp() async {
    if (_isPhoneAuth) {
      await _verifySmsOtp();
      return;
    }

    final email = _emailController.text.trim().toLowerCase();
    final enteredOtp = _otpController.text.trim();

    if (enteredOtp.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final doc = await _firestore.collection('customer_otps').doc(email).get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final correctOtp = data['otp'];
        final expiresAtStr = data['expiresAt'] as String?;

        if (expiresAtStr != null) {
          final expiresAt = DateTime.parse(expiresAtStr);
          if (DateTime.now().isAfter(expiresAt)) {
            throw Exception('PIN has expired. Please request a new one.');
          }
        }

        if (enteredOtp == correctOtp) {
          // OTP Verified!
          if (_isSigningUp) {
            // If they are signing up, we already have the password, so register them
            await _registerNewUser();
          } else {
            // For forgot password or other flow
            setState(() {
              _isOtpSent = false;
              _isSettingPassword = true;
              _isLoading = false;
            });
          }
        } else {
          throw Exception('Invalid PIN. Please try again.');
        }
      } else {
        throw Exception('No PIN found for $email. Please try sending it muna.');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  bool _isDisposableEmail(String email) {
    if (!email.contains('@')) return true;
    final domain = email.split('@')[1].toLowerCase().trim();
    const disposableDomains = [
      'mailinator.com',
      'tempmail.com',
      'guerrillamail.com',
      '10minutemail.com',
      'trashmail.com',
      'dispostable.com',
      'getnada.com',
      'sharklasers.com',
      'yopmail.com',
      'temp-mail.org',
      'fakeinbox.com'
    ];
    return disposableDomains.contains(domain);
  }

  Future<void> _checkDeviceAndNetworkSecurity(String email) async {
    if (_isDisposableEmail(email)) {
      throw Exception(
          'Disposable / temporary email addresses are restricted. Please use a valid active email.');
    }

    final domain = email.contains('@') ? email.split('@')[1].toLowerCase() : '';
    final bannedSnap = await _firestore.collection('banned_devices').get();
    for (var doc in bannedSnap.docs) {
      final data = doc.data();
      final bannedEmail = (data['email'] ?? '').toString().toLowerCase();
      final bannedDomain = (data['emailDomain'] ?? '').toString().toLowerCase();

      if ((bannedEmail.isNotEmpty && bannedEmail == email.toLowerCase()) ||
          (bannedDomain.isNotEmpty &&
              bannedDomain == domain &&
              !['gmail.com', 'yahoo.com', 'outlook.com', 'hotmail.com']
                  .contains(domain))) {
        throw Exception(
            'Security Warning: This device or network signature is flagged for fraud violations. Registration restricted.');
      }
    }
  }

  Future<void> _registerNewUser() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    final fName = _firstNameController.text.trim();
    final lName = _lastNameController.text.trim();
    final mName = _middleNameController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (fName.isEmpty || lName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('First name and Last name are required')));
      return;
    }

    if (_selectedBirthday == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Birthday is required')));
      return;
    }

    if (!_isPhoneAuth) {
      if (password.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Password must be at least 6 characters')));
        return;
      }

      if (password != confirmPassword) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Passwords do not match')));
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      if (!_isPhoneAuth) {
        await _checkDeviceAndNetworkSecurity(email);
      }

      String uid;
      String identifier;
      String? phone;

      if (_isPhoneAuth) {
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) {
          throw Exception(
              'No active session found. Please try verifying again.');
        }
        uid = currentUser.uid;
        phone = currentUser.phoneNumber ?? _phoneController.text.trim();
        identifier = phone;
      } else {
        // PROPER REGISTRATION using Firebase Auth
        UserCredential userCredential =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        uid = userCredential.user!.uid;
        identifier = email;
      }

      // FIX: Recover points if customer with this email or phone already exists
      int existingPoints = 0;
      final existingQuery = _isPhoneAuth
          ? await _firestore
              .collection('customers')
              .where('phone', isEqualTo: phone)
              .limit(1)
              .get()
          : await _firestore
              .collection('customers')
              .where('email', isEqualTo: email)
              .limit(1)
              .get();

      if (existingQuery.docs.isNotEmpty) {
        final existingDoc = existingQuery.docs.first;
        existingPoints = existingDoc.data()['points'] ?? 0;

        if (existingDoc.id != uid) {
          await _firestore.collection('customers').doc(existingDoc.id).delete();
        }
      }

      final fullName =
          '$fName ${mName.isNotEmpty ? '$mName ' : ''}$lName'.trim();

      // Create/Update Firestore record
      final customerData = {
        'firstName': fName,
        'middleName': mName,
        'lastName': lName,
        'fullName': fullName,
        'name': fullName,
        'birthday': _selectedBirthday?.toIso8601String().split('T')[0],
        'sex': _selectedSex,
        'points': existingPoints, // Restore points
        'createdAt': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
      };

      if (_isPhoneAuth) {
        customerData['phone'] = phone!;
        if (email.isNotEmpty) {
          customerData['email'] = email;
        }
      } else {
        customerData['email'] = email;
        customerData['password'] = password;
      }

      await _firestore
          .collection('customers')
          .doc(uid)
          .set(customerData, SetOptions(merge: true));

      // Also ensure the 'users' collection has the role for this UID
      final existingUserDoc =
          await _firestore.collection('users').doc(uid).get();
      final existingDocData = existingUserDoc.data();
      final existingRole =
          existingDocData != null ? existingDocData['role'] : null;
      if (existingRole == null || existingRole == 'customer') {
        final userData = {
          'role': 'customer',
          'customerId': uid,
        };
        if (_isPhoneAuth) {
          userData['phone'] = phone!;
          if (email.isNotEmpty) {
            userData['email'] = email;
          }
        } else {
          userData['email'] = email;
        }
        await _firestore
            .collection('users')
            .doc(uid)
            .set(userData, SetOptions(merge: true));
      }

      if (!_isPhoneAuth) {
        await _firestore.collection('customer_otps').doc(email).delete();
      }

      if (mounted) {
        if (widget.returnAfterLogin) {
          widget.onLoginSuccess?.call();
          Navigator.pop(context, true);
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (context) =>
                    CustomerProfilePage(email: identifier, customerId: uid)),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    String title = _isSigningUp ? 'Join\nUs' : 'Welcome\nBack';
    if (_isOtpSent) title = _isPhoneAuth ? 'Verify\nPhone' : 'Verify\nEmail';
    if (_isSettingPassword) title = 'Complete\nProfile';
    if (_showPasswordField && _isExistingUser) title = 'Enter\nPassword';

    return PopScope(
      canPop: !_isOtpSent && !_isSettingPassword && !_showPasswordField,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isOtpSent) {
          setState(() => _isOtpSent = false);
        } else if (_isSettingPassword) {
          setState(() => _isSettingPassword = false);
        } else if (_showPasswordField) {
          setState(() => _showPasswordField = false);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFFF8E1), // Soft Cream
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF121212)),
            onPressed: () {
              if (_isOtpSent) {
                setState(() => _isOtpSent = false);
              } else if (_isSettingPassword) {
                setState(() => _isSettingPassword = false);
              } else if (_showPasswordField) {
                setState(() => _showPasswordField = false);
              } else {
                Navigator.pop(context);
              }
            },
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Text(
                title,
                style: GoogleFonts.cormorantGaramond(
                  fontSize: 64,
                  height: 0.9,
                  color: const Color(0xFF121212),
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isOtpSent
                    ? (_isPhoneAuth
                        ? 'Enter the 6-digit SMS code sent to your phone number.'
                        : 'Enter the 6-digit PIN sent to your email.')
                    : _isSettingPassword
                        ? 'Help us know you better.'
                        : _isSigningUp
                            ? 'Begin your floral journey today.'
                            : 'Sign in to continue your floral journey.',
                style: GoogleFonts.cormorantGaramond(
                  fontSize: 18,
                  color: const Color(0xFF333333),
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 60),
              if (!_isOtpSent &&
                  !_showPasswordField &&
                  !_isSettingPassword) ...[
                // ChoiceChips to select Email or Phone
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChoiceChip(
                      label: Text(
                        'Email',
                        style: TextStyle(
                          color: !_isPhoneAuth
                              ? const Color(0xFFF4B400)
                              : const Color(0xFF121212),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      selected: !_isPhoneAuth,
                      selectedColor: const Color(0xFF121212),
                      backgroundColor: Colors.white,
                      checkmarkColor: const Color(0xFFF4B400),
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _isPhoneAuth = false;
                            _isOtpSent = false;
                          });
                        }
                      },
                    ),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: Text(
                        'Phone (SMS)',
                        style: TextStyle(
                          color: _isPhoneAuth
                              ? const Color(0xFFF4B400)
                              : const Color(0xFF121212),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      selected: _isPhoneAuth,
                      selectedColor: const Color(0xFF121212),
                      backgroundColor: Colors.white,
                      checkmarkColor: const Color(0xFFF4B400),
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _isPhoneAuth = true;
                            _isOtpSent = false;
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // NAME (Sign Up only)
                if (_isSigningUp) ...[
                  _buildTextField(
                    controller: _firstNameController,
                    hint: 'First Name',
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _middleNameController,
                    hint: 'Middle Name',
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _lastNameController,
                    hint: 'Last Name',
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 12),
                  // Birthday Picker
                  GestureDetector(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime(2000),
                        firstDate: DateTime(1950),
                        lastDate: DateTime.now(),
                      );
                      if (date != null)
                        setState(() => _selectedBirthday = date);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE0E0E0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              size: 20, color: Color(0xFF121212)),
                          const SizedBox(width: 12),
                          Text(
                            _selectedBirthday == null
                                ? 'Select Birthday'
                                : 'Birthday: ${_selectedBirthday!.toIso8601String().split('T')[0]}',
                            style: const TextStyle(color: Color(0xFF121212)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Sex Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedSex,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'Male', child: Text('Male')),
                          DropdownMenuItem(
                              value: 'Female', child: Text('Female')),
                        ],
                        onChanged: (val) => setState(() => _selectedSex = val!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // DYNAMIC INPUT: EMAIL OR PHONE
                if (!_isPhoneAuth) ...[
                  _buildTextField(
                    controller: _emailController,
                    hint: 'Email Address',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                ] else ...[
                  _buildTextField(
                    controller: _phoneController,
                    hint: 'Phone Number (e.g. 09171234567)',
                    icon: Icons.phone_android_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                ],
                const SizedBox(height: 16),

                // PASSWORD & CONFIRM (Sign Up only, email only)
                if (_isSigningUp && !_isPhoneAuth) ...[
                  _buildTextField(
                    controller: _passwordController,
                    hint: 'Password',
                    icon: Icons.lock_outline,
                    isPassword: true,
                    obscureText: _obscurePassword,
                    onToggleVisibility: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _confirmPasswordController,
                    hint: 'Confirm Password',
                    icon: Icons.lock_clock_outlined,
                    isPassword: true,
                    obscureText: _obscurePassword,
                  ),
                ],

                const SizedBox(height: 40),

                // CONTINUE BUTTON
                _buildPrimaryButton(
                  onPressed: _isLoading ? null : _handleContinue,
                  text: _isSigningUp ? 'Sign Up' : 'Continue',
                  isLoading: _isLoading,
                ),

                const SizedBox(height: 40),
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                          _isSigningUp
                              ? 'Already have an account? '
                              : 'New to Bloom? ',
                          style: const TextStyle(color: Color(0xFF333333))),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isSigningUp = !_isSigningUp;
                          });
                        },
                        child: Text(_isSigningUp ? 'Sign In' : 'Create One',
                            style: const TextStyle(
                              color: Color(0xFF121212),
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            )),
                      ),
                    ],
                  ),
                ),
              ] else if (_isOtpSent) ...[
                // OTP INPUT
                _buildTextField(
                  controller: _otpController,
                  hint: '000000',
                  icon: Icons.lock_outline,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  isOtp: true,
                ),
                const SizedBox(height: 40),

                // VERIFY BUTTON
                _buildPrimaryButton(
                  onPressed: _isLoading ? null : _verifyOtp,
                  text: 'Verify PIN',
                  isLoading: _isLoading,
                ),

                const SizedBox(height: 24),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => _isOtpSent = false),
                    child: Text(_isPhoneAuth ? 'Change Phone' : 'Change Email',
                        style: const TextStyle(
                          color: Color(0xFF333333),
                          decoration: TextDecoration.underline,
                        )),
                  ),
                ),
              ] else if (_showPasswordField && _isExistingUser) ...[
                // PASSWORD INPUT
                _buildTextField(
                  controller: _passwordController,
                  hint: 'Password',
                  icon: Icons.lock_outline,
                  isPassword: true,
                  obscureText: _obscurePassword,
                  onToggleVisibility: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                const SizedBox(height: 40),

                // SIGN IN BUTTON
                _buildPrimaryButton(
                  onPressed: _isLoading ? null : _loginWithPassword,
                  text: 'Sign In',
                  isLoading: _isLoading,
                ),

                const SizedBox(height: 24),
                Center(
                  child: Column(
                    children: [
                      TextButton(
                        onPressed: _forgotPassword,
                        child: const Text('Forgot Password?',
                            style: TextStyle(
                              color: Color(0xFF333333),
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            )),
                      ),
                      TextButton(
                        onPressed: _showOtpTargetSelectionSheet,
                        child: const Text('Login with OTP instead',
                            style: TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 12,
                              decoration: TextDecoration.underline,
                            )),
                      ),
                    ],
                  ),
                ),
              ] else if (_isSettingPassword) ...[
                // SET NAME INPUT
                _buildTextField(
                  controller: _firstNameController,
                  hint: 'First Name',
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _middleNameController,
                  hint: 'Middle Name',
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _lastNameController,
                  hint: 'Last Name',
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 12),
                // Birthday Picker
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 20, color: Color(0xFF121212)),
                        const SizedBox(width: 12),
                        Text(
                          _selectedBirthday == null
                              ? 'Select Birthday'
                              : 'Birthday: ${_selectedBirthday!.toIso8601String().split('T')[0]}',
                          style: const TextStyle(color: Color(0xFF121212)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Sex Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedSex,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'Male', child: Text('Male')),
                        DropdownMenuItem(
                            value: 'Female', child: Text('Female')),
                      ],
                      onChanged: (val) => setState(() => _selectedSex = val!),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // SET PASSWORD INPUT (Email auth only)
                if (!_isPhoneAuth) ...[
                  _buildTextField(
                    controller: _passwordController,
                    hint: 'Create Password',
                    icon: Icons.lock_outline,
                    isPassword: true,
                    obscureText: _obscurePassword,
                    onToggleVisibility: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _confirmPasswordController,
                    hint: 'Confirm Password',
                    icon: Icons.lock_clock_outlined,
                    isPassword: true,
                    obscureText: _obscurePassword,
                  ),
                ],
                const SizedBox(height: 40),

                // COMPLETE REGISTRATION BUTTON
                _buildPrimaryButton(
                  onPressed: _isLoading ? null : _registerNewUser,
                  text: 'Complete Registration',
                  isLoading: _isLoading,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    bool isOtp = false,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLength: maxLength,
        obscureText: obscureText,
        textAlign: isOtp ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          fontSize: isOtp ? 28 : 16,
          fontWeight: isOtp ? FontWeight.bold : FontWeight.normal,
          letterSpacing: isOtp ? 8 : 0,
          color: const Color(0xFF121212),
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.black26, letterSpacing: 0),
          prefixIcon: isOtp ? null : Icon(icon, color: const Color(0xFF121212)),
          suffixIcon: isPassword && onToggleVisibility != null
              ? IconButton(
                  icon: Icon(
                    obscureText ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                  ),
                  onPressed: onToggleVisibility,
                )
              : null,
          counterText: '',
          border: InputBorder.none,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFF4B400), width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required VoidCallback? onPressed,
    required String text,
    bool isLoading = false,
  }) {
    return Container(
      width: double.infinity,
      height: 65,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF121212).withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF121212),
          foregroundColor: const Color(0xFFF4B400),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: isLoading
            ? const CircularProgressIndicator(color: Color(0xFFF4B400))
            : Text(text,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
      ),
    );
  }
}

// The CustomerProfilePage class and its helpers have been moved to lib/customer_profile_page.dart
