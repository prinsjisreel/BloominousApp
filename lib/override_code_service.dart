import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class OverrideCodeResult {
  final bool success;
  final bool valid;
  final String? message;
  const OverrideCodeResult({required this.success, this.valid = false, this.message});
}

/// Calls verify_override_code.php — the ONLY place a walk-in
/// cancellation override code is ever checked. The Flutter app never
/// reads the override_codes collection directly; firestore.rules
/// restricts it to isAdmin() entirely, so an employee's app has no way
/// to see which codes exist or whether one is still valid except by
/// asking this endpoint.
class OverrideCodeService {
  static const String _endpoint =
      'https://honeydew-duck-132160.hostingersite.com/verify_override_code.php';

  Future<OverrideCodeResult> verifyAndBurn({
    required String branchId,
    required String code,
    required String orderId,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return const OverrideCodeResult(success: false, message: 'Not signed in.');
      }
      final idToken = await user.getIdToken();

      final response = await http
          .post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'branchId': branchId, 'code': code, 'orderId': orderId}),
      )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return OverrideCodeResult(
        success: data['success'] == true,
        valid: data['valid'] == true,
        message: data['message'] as String?,
      );
    } catch (e) {
      return OverrideCodeResult(success: false, message: e.toString());
    }
  }
}