import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  // The server runs rate limits, pricing, IP/phone lookups, fraud checks,
  // the invoice counter and notifications before it answers, so a slow
  // host can need well over 15 seconds. 45s is generous but still finite.
  static const Duration _requestTimeout = Duration(seconds: 45);

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

  /// After a timeout, asks Firestore: "did the server create my order
  /// anyway?" Looks at THIS customer's orders only (the same read the
  /// order-tracking screen already does) and accepts one that was created
  /// since this request started AND matches the payment method and
  /// subtotal we sent. Checks a few times, because the server may still be
  /// finishing when the app gives up. Returns null if nothing is found.
  Future<OrderSubmissionResult?> _findOrderCreatedSince({
    required String uid,
    required DateTime since,
    required String paymentMethod,
    required double subtotal,
  }) async {
    for (int attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) await Future.delayed(const Duration(seconds: 4));
      try {
        final snap = await FirebaseFirestore.instance
            .collection('orders')
            .where('user_id', isEqualTo: uid)
            .get();

        for (final doc in snap.docs) {
          final data = doc.data();
          final created = data['createdAt'];
          final invoiceId = data['invoiceId'];
          final savedSubtotal = data['subtotal'];

          final isRecent = created is Timestamp && !created.toDate().isBefore(since);
          final sameMethod = data['payment_method'] == paymentMethod;
          final sameAmount =
              savedSubtotal is num && (savedSubtotal - subtotal).abs() < 1.0;

          if (isRecent && sameMethod && sameAmount && invoiceId is String) {
            return OrderSubmissionResult(orderId: doc.id, invoiceId: invoiceId);
          }
        }
      } catch (e) {
        debugPrint('OrderSubmissionService: recovery lookup failed: $e');
      }
    }
    return null;
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

    // Remember when we started, minus a minute for clock differences
    // between this phone and the server. Used only by the recovery check.
    final requestStartedAt = DateTime.now().subtract(const Duration(minutes: 1));

    // --- Send the order ---
    http.Response? response;
    bool timedOut = false;
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
          .timeout(_requestTimeout);
    } on TimeoutException {
      timedOut = true;
    } catch (e) {
      debugPrint('OrderSubmissionService: request failed: $e');
      throw OrderSubmissionException(
        'Could not reach the server. Please check your internet connection and try again.',
        code: 'NETWORK',
      );
    }

    // --- Timed out: the order may still have been created ---
    if (timedOut) {
      final recovered = await _findOrderCreatedSince(
        uid: user.uid,
        since: requestStartedAt,
        paymentMethod: paymentMethod,
        subtotal: subtotal,
      );
      if (recovered != null) {
        debugPrint('OrderSubmissionService: recovered order ${recovered.invoiceId} after timeout.');
        return recovered;
      }
      throw OrderSubmissionException(
        'The server is taking too long to respond. Your order may still have gone through — please check your orders before trying again.',
        code: 'TIMEOUT',
      );
    }

    // --- Read the reply ---
    Map<String, dynamic> data;
    try {
      data = jsonDecode(response!.body) as Map<String, dynamic>;
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