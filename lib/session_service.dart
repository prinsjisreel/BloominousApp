import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'inventory_data.dart';
import 'main.dart' show AppAuthWrapper;

/// One shared, reliable logout for every staff/admin/delivery screen.
///
/// Why this exists: pages like the sidebar use pushReplacement, which can
/// replace the app's very first screen (AppAuthWrapper). After that, the old
/// "signOut() then popUntil(first)" had no login-checker left to fall back to,
/// so the app stayed on the dashboard until it was restarted.
///
/// This version signs out and then REBUILDS the whole navigation stack
/// starting from a fresh AppAuthWrapper, no matter what was open before.
class SessionService {
  SessionService._(); // static-only helper, never instantiated

  // Stops a double-tap from running logout twice at the same time.
  static bool _isLoggingOut = false;

  static Future<void> logout(BuildContext context) async {
    if (_isLoggingOut) return;
    _isLoggingOut = true;

    // Grab these BEFORE the await. After signOut the screen that owns
    // `context` may already be gone, but these objects stay usable.
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.maybeOf(context);

    try {
      await FirebaseAuth.instance.signOut();

      // Forget the previous account's branch so the next login starts clean.
      // 'main_branch' is the same default InventoryData starts with.
      InventoryData.selectedBranchId = 'main_branch';

      // Throw away EVERY open screen (dashboard, drawer, dialogs) and start
      // over from the login-checker. It sees "no user" and shows the home page.
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AppAuthWrapper()),
            (route) => false,
      );
    } catch (e) {
      debugPrint('Logout failed: $e');
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Could not log out: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      _isLoggingOut = false;
    }
  }
}