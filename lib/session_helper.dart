import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'main.dart' show AppAuthWrapper;

/// Logs the current user out and returns the app to its starting screen.
///
/// WHY THIS ORDER MATTERS:
///   1. First we throw away every open screen (orders page, inventory page...)
///      and put a fresh AppAuthWrapper in their place. Those screens each run
///      a live Firestore stream. Closing them first means no stream is still
///      listening when the user signs out.
///   2. THEN we sign out. AppAuthWrapper notices "nobody is signed in" and
///      shows the main page by itself.
///
/// If we signed out first (the old way), the open orders page was still
/// listening, Firestore said "permission-denied" because nobody was signed in
/// any more, and the red error text stayed on screen.
Future<void> logoutToHome(BuildContext context) async {
  // rootNavigator: true = the app's main navigator, even if we were called
  // from inside a Drawer or a dialog.
  final navigator = Navigator.of(context, rootNavigator: true);

  // (route) => false means "remove every route that is open right now".
  navigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const AppAuthWrapper()),
        (route) => false,
  );

  await FirebaseAuth.instance.signOut();
}