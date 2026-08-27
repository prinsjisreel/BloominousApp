import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

/// Calls send_verification_email.php — identical contract to what
/// register.php and index.php's "Resend verification email" button
/// already use on web: POST with a Bearer ID token, no body. Same
/// platform-agnostic shape as record_email_risk.php, so this is reused
/// as-is rather than needing a separate mobile endpoint.
class EmailVerificationService {
  static const String _endpoint =
      'https://honeydew-duck-132160.hostingersite.com/send_verification_email.php';

  Future<bool> sendVerificationEmail() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      final idToken = await user.getIdToken();

      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {'Authorization': 'Bearer $idToken'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['success'] == true;
    } catch (e) {
      return false;
    }
  }
}