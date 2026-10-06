import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'device_security_service.dart';

/// Thrown when an order can't be placed. `code` mirrors the server's
/// machine-readable reason when present (RESTRICTED, BLOCKED,
/// EMAIL_UNREACHABLE), or a client-side reason (TIMEOUT, NETWORK,
/// BAD_RESPONSE), so the UI can react differently per case.
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

/// Calls submit_order.php — the ONLY way an order can be created.
/// firestore.rules denies direct client `orders` creates for customers
/// (`isStaff()` is required), so every web and app order goes through
/// this one server file: the same fraud activity checks, the same
/// restriction gate, no drift between platforms.
///
/// The endpoint only needs a Firebase ID token (no Turnstile/App Check),
/// so web and mobile share it exactly as-is.
class OrderSubmissionService {
  static const String _endpoint =
      'https://honeydew-duck-132160.hostingersite.com/submit_order.php';

  // Must match submit_order.php exactly: preg_match('/^[a-f0-9]{64}$/').
  // A hash in any other shape is silently ignored by the server, which
  // would switch off the banned-device check for this order.
  static final RegExp _deviceHashPattern = RegExp(r'^[a-f0-9]{64}$');

  final DeviceSecurityService _securityService = DeviceSecurityService();

  /// Reads this device's fingerprint in the exact format the server
  /// accepts. Returns null (and logs why) if it can't — the order still
  /// goes through, same "fail open" policy as the server's other checks,
  /// but the problem is visible in the debug console instead of silent.
  Future<String?> _readDeviceHash() async {
    try {
      // Stored as Object? on purpose: works whether getDeviceHash()
      // returns String or String?, without an analyzer warning either way.
      final Object? raw = await _securityService.getDeviceHash();
      final normalized = raw?.toString().trim().toLowerCase() ?? '';

      if (_deviceHashPattern.hasMatch(normalized)) {
        return normalized;
      }

      debugPrint(
          'OrderSubmissionService: device hash has an unexpected format '
              '(length ${normalized.length}); the banned-device check will be '
              'skipped for this order. Expected 64 lowercase hex characters.');
      return null;
    } catch (e) {
      debugPrint('OrderSubmissionService: could not read device hash: $e');
      return null;
    }
  }

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
    String? notes,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw OrderSubmissionException('You must be signed in to place an order.');
    }

    final idToken = await user.getIdToken();
    final deviceHash = await _readDeviceHash();
    final trimmedNotes = notes?.trim() ?? '';

    // --- Send the order ---
    http.Response response;
    try {
      response = await http
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
          if (trimmedNotes.isNotEmpty) 'notes': trimmedNotes,
          'otpVerified': otpVerified,
          if (deviceHash != null) 'deviceHash': deviceHash,
        }),
      )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      // The request may have REACHED the server and created the order;
      // only the reply was too slow. Warn the customer before they tap
      // Place Order again and create a duplicate.
      throw OrderSubmissionException(
        'The server is taking too long to respond. Your order may still have gone through — please check your orders before trying again.',
        code: 'TIMEOUT',
      );
    } catch (e) {
      debugPrint('OrderSubmissionService: request failed: $e');
      throw OrderSubmissionException(
        'Could not reach the server. Please check your internet connection and try again.',
        code: 'NETWORK',
      );
    }

    // --- Read the reply ---
    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw OrderSubmissionException(
        'The server returned an unexpected response. Please try again.',
        code: 'BAD_RESPONSE',
      );
    }

    if (data['success'] != true) {
      throw OrderSubmissionException(
        data['message']?.toString() ?? 'Order could not be placed.',
        code: data['code']?.toString(),
      );
    }

    final orderId = data['orderId'];
    final invoiceId = data['invoiceId'];
    if (orderId is! String || invoiceId is! String) {
      // success: true means the order WAS created; only the reply is
      // incomplete. Say so, instead of implying nothing happened.
      throw OrderSubmissionException(
        'Your order was received, but the confirmation was incomplete. Please check your orders before trying again.',
        code: 'BAD_RESPONSE',
      );
    }

    return OrderSubmissionResult(orderId: orderId, invoiceId: invoiceId);
  }
}