import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class EmailVerificationResult {
  final bool success;
  final String? message;
  const EmailVerificationResult({required this.success, this.message});
}

/// Calls send_verification_email.php — identical contract to what
/// register.php and index.php's "Resend verification email" button
/// already use on web.
class EmailVerificationService {
  static const String _endpoint =
      'https://honeydew-duck-132160.hostingersite.com/send_verification_email.php';

  /// Returns a result object (success + real server message) rather
  /// than a plain bool — this is what lets EmailVerificationPendingPage
  /// show the ACTUAL reason a send failed (e.g. "Could not generate
  /// verification link" vs. "Could not send verification email") instead
  /// of a generic message that hides the real cause.
  Future<EmailVerificationResult> sendVerificationEmail() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return const EmailVerificationResult(
            success: false, message: 'No signed-in user found.');
      }
      final idToken = await user.getIdToken();

      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {'Authorization': 'Bearer $idToken'},
      ).timeout(const Duration(seconds: 10));

      Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        // The server responded, but not with the JSON shape we expect —
        // include the raw status/body so it's diagnosable instead of a
        // generic "something went wrong".
        return EmailVerificationResult(
          success: false,
          message:
          'Unexpected server response (HTTP ${response.statusCode}). Raw: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}',
        );
      }

      return EmailVerificationResult(
        success: data['success'] == true,
        message: data['message'] as String?,
      );
    } catch (e) {
      // Network error, timeout, DNS failure, etc. — surface the actual
      // exception instead of a flat false, so we can tell "couldn't
      // reach the server" apart from "server said no".
      return EmailVerificationResult(success: false, message: e.toString());
    }
  }
}