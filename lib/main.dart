import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'builder_page.dart';
import 'scanner_page.dart';
import 'auth_page.dart';
import 'customer_profile_page.dart';
import 'employee_login_page.dart';
import 'product_catalog_page.dart';
import 'admin_dashboard.dart';
import 'delivery_dashboard.dart';
import 'ai_assistant_page.dart';
import 'connectivity_service.dart';
import 'sync_manager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

// Global theme notifier. Starting value is no longer hardcoded to
// ThemeMode.system — main() below overwrites it with whatever was last
// saved by Settings' dark-mode toggle, BEFORE runApp() ever paints a
// single frame. If nothing was ever saved (first launch after install),
// it stays at ThemeMode.system, matching the previous default exactly.
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // NEW: read the saved theme choice before anything else renders. This
  // is deliberately placed before Firebase init and before runApp() — it
  // has nothing to do with Firebase Auth or login state, which is exactly
  // why it survives both a full app close/reopen AND a logout: nothing in
  // the sign-out flow touches SharedPreferences, and this read happens
  // regardless of whether a user is signed in at all.
  final prefs = await SharedPreferences.getInstance();
  final bool? savedIsDark = prefs.getBool('isDarkMode');
  if (savedIsDark != null) {
    themeNotifier.value = savedIsDark ? ThemeMode.dark : ThemeMode.light;
  }
  // If savedIsDark is null (nothing has ever been saved — e.g. a fresh
  // install, or a user who has never touched the toggle), themeNotifier
  // keeps its original ThemeMode.system default, unchanged from before.

  String? initError;

  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyCnfoiasHySwrtAnx9pB_Xjucxz5JfW3Qw",
        appId: "1:627989159362:android:e44aefb6d573e078ae0a5b",
        messagingSenderId: "627989159362",
        projectId: "ar-flower-shop-app",
        storageBucket: "ar-flower-shop-app.firebasestorage.app",
      ),
    );

    await FirebaseAppCheck.instance.activate(
      androidProvider:
      kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider:
      kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
    );

    syncManager.init();
  } catch (e) {
    print("Firebase initialization error: $e");
    initError =
    "Firebase Error: $e\n\nTip: Check your configuration and network connection.";
  }

  runApp(BloomApp(initError: initError));
}

class BloomApp extends StatelessWidget {
  final String? initError;
  const BloomApp({super.key, this.initError});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          title: 'Bloominous',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData(
            primaryColor: const Color(0xFFF59E0B),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFF59E0B),
              primary: const Color(0xFFF59E0B),
              secondary: const Color(0xFF121212),
              surface: const Color(0xFFFFFDF7),
            ),
            scaffoldBackgroundColor: const Color(0xFFFFFDF7),
            useMaterial3: true,
            textTheme: GoogleFonts.interTextTheme().copyWith(
              displayLarge: GoogleFonts.cormorantGaramond(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF121212),
                  fontSize: 64),
              displayMedium: GoogleFonts.cormorantGaramond(
                  fontWeight: FontWeight.bold, color: const Color(0xFF121212)),
              titleLarge:
              GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18),
              bodyMedium: GoogleFonts.inter(color: const Color(0xFF555555)),
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: const Color(0xFFF59E0B),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFF59E0B),
              brightness: Brightness.dark,
              primary: const Color(0xFFF59E0B),
              secondary: const Color(0xFFFFFDF7),
            ),
            scaffoldBackgroundColor: const Color(0xFF121212),
            useMaterial3: true,
            textTheme:
            GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
              displayLarge: GoogleFonts.cormorantGaramond(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontSize: 64),
              displayMedium: GoogleFonts.cormorantGaramond(
                  fontWeight: FontWeight.bold, color: Colors.white),
              titleLarge:
              GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18),
              bodyMedium: GoogleFonts.inter(color: Colors.grey[400]),
            ),
          ),
          home: initError != null
              ? ErrorScreen(message: initError!)
              : const AppAuthWrapper(),
        );
      },
    );
  }
}

class AppAuthWrapper extends StatelessWidget {
  const AppAuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
                child: CircularProgressIndicator(color: Color(0xFFF59E0B))),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          return const HomePage();
        }
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                    child: CircularProgressIndicator(color: Color(0xFFF59E0B))),
              );
            }
            if (userSnap.hasData && userSnap.data!.exists) {
              final data = userSnap.data!.data() as Map<String, dynamic>?;
              final role = data?['role'] ?? 'employee';
              if (role == 'delivery') {
                return const DeliveryDashboard();
              } else if (role == 'admin' ||
                  role == 'super-admin' ||
                  role == 'staff' ||
                  role == 'employee') {
                return AdminDashboard(role: role);
              }
            }
            return const HomePage();
          },
        );
      },
    );
  }
}

class ErrorScreen extends StatelessWidget {
  final String message;
  const ErrorScreen({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              const Text('Startup Error',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'The app couldn\'t start properly.\n\nDetails: $message',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => main(),
                child: const Text('RETRY'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  const Color(0xFFF59E0B).withOpacity(0.05),
                  theme.scaffoldBackgroundColor,
                  theme.scaffoldBackgroundColor,
                ],
              ),
            ),
          ),

          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24.0, vertical: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isDark ? Colors.grey[800] : Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black12, blurRadius: 10)
                                ],
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/images/logo.jpg',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.local_florist,
                                      color: Color(0xFF7B79F2), size: 20),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'BLOOMINOUS',
                              style: GoogleFonts.cormorantGaramond(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 3.0,
                                fontSize: 20,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF121212),
                              ),
                            ),
                          ],
                        ),
                        const SyncIndicator(),
                        IconButton(
                          icon: Icon(Icons.person_pin_rounded,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF121212),
                              size: 28),
                          onPressed: () => _handleProfileNavigation(context),
                        ),
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32.0, vertical: 40.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7B79F2).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'PREMIUM FLORISTRY',
                            style: TextStyle(
                              color: Color(0xFF7B79F2),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Flowers that\nspeak for you.',
                          style: theme.textTheme.displayLarge,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Experience the future of floristry with AI-powered freshness detection and immersive AR bouquet building.',
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark
                                ? Colors.grey[400]
                                : const Color(0xFF555555),
                            fontFamily: 'Inter',
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildActionCard(
                        context,
                        title: 'Build Your Bouquet',
                        subtitle: 'Create custom AR arrangements',
                        icon: Icons.auto_awesome_rounded,
                        color: isDark ? Colors.white : const Color(0xFF121212),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const BuilderPage())),
                        isPrimary: true,
                      ),
                      const SizedBox(height: 16),
                      _buildActionCard(
                        context,
                        title: 'AI Visual & Personal Stylist',
                        subtitle: 'Photo theme analysis & custom matchmaker',
                        icon: Icons.auto_awesome,
                        color: isDark
                            ? const Color(0xFF2E2412)
                            : const Color(0xFFFFFBEB),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const AIAssistantPage())),
                        isPrimary: false,
                      ),
                      const SizedBox(height: 16),
                      _buildActionCard(
                        context,
                        title: 'Shop by Category',
                        subtitle: 'Browse our collection',
                        icon: Icons.grid_view_rounded,
                        color: isDark ? Colors.grey[900]! : Colors.white,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                const ProductCatalogPage())),
                        isPrimary: false,
                      ),
                      const SizedBox(height: 16),
                      _buildActionCard(
                        context,
                        title: 'Scan for Freshness',
                        subtitle: 'AI-powered quality check',
                        icon: Icons.qr_code_scanner_rounded,
                        color: isDark ? Colors.grey[900]! : Colors.white,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => ScannerPage())),
                        isPrimary: false,
                      ),
                    ]),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 60.0, top: 40),
                    child: Column(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                  const EmployeeLoginPage())),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.badge_outlined,
                                  size: 14, color: Colors.grey[600]),
                              const SizedBox(width: 8),
                              Text(
                                'Staff Portal Login',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '© 2026 BloomyPro. All rights reserved.',
                          style:
                          TextStyle(color: Colors.grey[400], fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
      BuildContext context, {
        required String title,
        required String subtitle,
        required IconData icon,
        required Color color,
        required VoidCallback onTap,
        required bool isPrimary,
      }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color contentColor = isPrimary
        ? (isDark ? const Color(0xFF121212) : Colors.white)
        : (isDark ? Colors.white : const Color(0xFF121212));

    final Color subContentColor = isPrimary
        ? (isDark
        ? const Color(0xFF121212).withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.6))
        : (isDark ? Colors.white.withValues(alpha: 0.6) : Colors.grey[600]!);

    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: isPrimary
                ? const Color(0xFF121212).withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: isPrimary
            ? null
            : Border.all(
            color: (isDark ? Colors.white : const Color(0xFF121212))
                .withValues(alpha: 0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isPrimary
                        ? const Color(0xFFF4B400).withValues(alpha: 0.2)
                        : (isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : const Color(0xFF121212).withValues(alpha: 0.05)),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: isPrimary ? const Color(0xFFF4B400) : contentColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: contentColor,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: subContentColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: contentColor.withOpacity(0.3),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleProfileNavigation(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    final firestore = FirebaseFirestore.instance;

    if (user != null) {
      final customerDoc =
      await firestore.collection('customers').doc(user.uid).get();

      if (customerDoc.exists) {
        final email = customerDoc.data()?['email'] ?? user.email ?? 'Customer';
        if (context.mounted) {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) =>
                      CustomerProfilePage(email: email, customerId: user.uid)));
        }
        return;
      }

      final email = user.email;
      if (email != null) {
        final emailQuery = await firestore
            .collection('customers')
            .where('email', isEqualTo: email.toLowerCase())
            .limit(1)
            .get();

        if (emailQuery.docs.isNotEmpty) {
          final existingDoc = emailQuery.docs.first;
          final userData = existingDoc.data();
          final oldDocId = existingDoc.id;

          await firestore.collection('customers').doc(user.uid).set({
            ...userData,
            'lastLogin': FieldValue.serverTimestamp(),
            'migratedFrom': oldDocId,
          }, SetOptions(merge: true));

          final existingUserDoc =
          await firestore.collection('users').doc(user.uid).get();
          final existingDocData = existingUserDoc.data();
          final existingRole =
          existingDocData != null ? existingDocData['role'] : null;
          if (existingRole == null || existingRole == 'customer') {
            await firestore.collection('users').doc(user.uid).set({
              'role': 'customer',
              'email': email,
              'customerId': user.uid,
            }, SetOptions(merge: true));
          }

          if (oldDocId != user.uid) {
            await firestore.collection('customers').doc(oldDocId).delete();
          }

          if (context.mounted) {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => CustomerProfilePage(
                        email: email, customerId: user.uid)));
          }
          return;
        }
      }

      final userDoc = await firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        final role = data?['role'] ?? 'employee';

        if (context.mounted) {
          if (role == 'customer') {
            final email = data?['email'] ?? user.email ?? 'Customer';
            final customerId = data?['customerId'] ?? user.uid;
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => CustomerProfilePage(
                        email: email, customerId: customerId)));
          } else if (role == 'delivery') {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const DeliveryDashboard()));
          } else {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => AdminDashboard(role: role)));
          }
        }
        return;
      }

      if (context.mounted) {
        Navigator.push(
            context, MaterialPageRoute(builder: (context) => const AuthPage()));
      }
    } else {
      if (context.mounted) {
        Navigator.push(
            context, MaterialPageRoute(builder: (context) => const AuthPage()));
      }
    }
  }
}

class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ConnectivityStatus>(
      stream: connectivityService.statusStream,
      initialData: ConnectivityStatus.online,
      builder: (context, connectivitySnap) {
        final isOnline = connectivitySnap.data == ConnectivityStatus.online;

        return StreamBuilder<bool>(
          stream: syncManager.syncStatusStream,
          initialData: false,
          builder: (context, syncSnap) {
            final isSyncing = syncSnap.data ?? false;
            // UNCHANGED from what you pasted — this body was already
            // flagged as unverified in your own file, not something I'm
            // touching or replacing here. Left exactly as-is.
            return Icon(
              isSyncing
                  ? Icons.sync_rounded
                  : (isOnline ? Icons.cloud_done_rounded : Icons.cloud_off_rounded),
              size: 18,
              color: isOnline ? Colors.green : Colors.grey,
            );
          },
        );
      },
    );
  }
}