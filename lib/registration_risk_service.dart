import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Result of a pre-signup risk check against check_email_risk_mobile.php.
/// Field names mirror the real PHP response exactly: {success, block,
/// reason, flag, scoreBump} — NOT an "allowed" boolean.
class RegistrationRiskResult {
  final bool blocked;
  final String? reason;
  final bool flagged;
  final int scoreBump;

  RegistrationRiskResult({
    required this.blocked,
    this.reason,
    this.flagged = false,
    this.scoreBump = 0,
  });
}

/// Calls the mobile-facing twin of check_email_risk.php as a pre-signup
/// UX check — same tier of protection as the web app's own pre-check
/// (Principle #3 in the fraud handoff doc: this is a convenience layer,
/// NOT the real enforcement boundary, exactly like check_email_risk.php
/// is on web — register.php's own account creation is client-side too).
///
/// Also handles the post-signup score recording (record_email_risk.php)
/// — that endpoint is platform-agnostic (it only verifies a Firebase ID
/// token), so it's reused as-is from both web and mobile with no
/// separate mobile version needed.
class RegistrationRiskService {
  static const String _riskCheckEndpoint =
      'https://honeydew-duck-132160.hostingersite.com/check_email_risk_mobile.php';

  static const String _recordScoreEndpoint =
      'https://honeydew-duck-132160.hostingersite.com/record_email_risk.php';

  Future<RegistrationRiskResult> checkEmail(String email) async {
    try {
      // App Check proves this request came from your real, unmodified app
      // — the mobile-native equivalent of what Turnstile proves for a
      // browser. If this ever returns null (activation failed, misconfig),
      // we still send the request; the server decides what to do with an
      // empty token.
      final appCheckToken = await FirebaseAppCheck.instance.getToken();

      final response = await http
          .post(
        Uri.parse(_riskCheckEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'appCheckToken': appCheckToken ?? '',
        }),
      )
          .timeout(const Duration(seconds: 8));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // The 400 "Invalid email format" and 405 "Method not allowed"
      // responses use {success: false, message: ...} — no 'block' field
      // at all. Fail open on that shape, same policy as every other
      // infra hiccup.
      if (data['success'] != true) {
        return RegistrationRiskResult(blocked: false);
      }

      return RegistrationRiskResult(
        blocked: data['block'] == true,
        reason: data['reason'] as String?,
        flagged: data['flag'] == true,
        scoreBump: (data['scoreBump'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      // Network error, timeout, malformed JSON, DNS failure, etc.
      // Fail OPEN — Principle #2.
      return RegistrationRiskResult(blocked: false);
    }
  }

  /// Mirrors register.php's post-signup call: persists the score bump
  /// computed during checkEmail() onto the just-created account, since
  /// firestore.rules blocks the client from writing fraudScore itself.
  /// Best-effort — a failure here should never undo a successful
  /// registration, same as web's console.warn-and-continue behavior.
  Future<void> recordScore(int scoreBump) async {
    if (scoreBump <= 0) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();

      await http.post(
        Uri.parse(_recordScoreEndpoint),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Bearer $idToken',
        },
        body: {'scoreBump': scoreBump.toString()},
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      // Best-effort — swallow and move on, same as web.
    }
  }
}