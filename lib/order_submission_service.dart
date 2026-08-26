import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'device_security_service.dart';

/// Thrown when submit_order.php rejects an order. `code` mirrors the
/// server's machine-readable reason (RESTRICTED, BLOCKED,
/// EMAIL_UNREACHABLE) when present, so the UI can react differently per
/// case instead of showing the same generic error for all of them.
class OrderSubmissionException implements Exception {
  final String message;
  final String? code;
  OrderSubmissionException(this.message, {this.code});

  @override
  String toString() => message;
}

class OrderSubmissionResult {
  final String orderId;
  final String invoiceId;
  OrderSubmissionResult({required this.orderId, required this.invoiceId});
}

/// Calls submit_order.php — the ONLY way an order can actually be
/// created. firestore.rules denies a direct client `orders` create
/// entirely for customers (`isStaff()` is required), so this endpoint
/// isn't an added security layer on top of something that already
/// worked — it's the fix for checkout being broken under the current
/// rules at all.
///
/// This endpoint only needs a Firebase ID token (same as
/// record_email_risk.php) — no Turnstile, no App Check — so it's reused
/// exactly as-is from both web and mobile. Same file, same fraud
/// scoring, no drift between platforms.
class OrderSubmissionService {
  static const String _endpoint =
      'https://honeydew-duck-132160.hostingersite.com/submit_order.php';

  final DeviceSecurityService _securityService = DeviceSecurityService();

  Future<OrderSubmissionResult> submitOrder({
    required String name,
    required String phone,
    required String address,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double shippingFee,
    required String paymentMethod,
    required String branchId,
    String? email,
    bool isGift = false,
    double? customerLat,
    double? customerLng,
    bool otpVerified = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw OrderSubmissionException(
          'You must be signed in to place an order.');
    }

    final idToken = await user.getIdToken();
    final deviceHash = await _securityService.getDeviceHash();

    final response = await http
        .post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'user_id': user.uid,
        'name': name,
        'phone': phone,
        'address': address,
        'email': email ?? user.email ?? '',
        'items': items,
        'subtotal': subtotal,
        'shippingFee': shippingFee,
        'paymentMethod': paymentMethod,
        'branchId': branchId,
        'isGift': isGift,
        if (customerLat != null) 'customerLat': customerLat,
        if (customerLng != null) 'customerLng': customerLng,
        'otpVerified': otpVerified,
        'deviceHash': deviceHash,
      }),
    )
        .timeout(const Duration(seconds: 15));

    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw OrderSubmissionException(
          'The server returned an unexpected response. Please try again.');
    }

    if (data['success'] != true) {
      throw OrderSubmissionException(
        data['message'] as String? ?? 'Order could not be placed.',
        code: data['code'] as String?,
      );
    }

    return OrderSubmissionResult(
      orderId: data['orderId'] as String,
      invoiceId: data['invoiceId'] as String,
    );
  }
}