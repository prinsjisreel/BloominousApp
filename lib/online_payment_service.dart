import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// BLOOMINOUS - Online Payment (GCash / Maya) client for BloominousApp.
///
/// Dart twin of BloominousWeb's assets/script/online_payment.js — same
/// endpoint, same rules, same data contract:
///
///   POST {host}/create_payment_session.php
///   Authorization: Bearer <Firebase ID token>
///   Body: { "orderId": "...", "paymentMethod": "gcash" | "maya" }
///   ->  { success: true, checkoutUrl }  or  { success: false, code?, message }
///
/// The app NEVER holds a PayMongo key and NEVER sends an amount: the server
/// charges whatever total_price is stored on the order in Firestore.
class OnlinePaymentException implements Exception {
  final String message;
  final String? code;

  const OnlinePaymentException(this.message, {this.code});

  @override
  String toString() => message;
}

/// The server's reply, unpacked once so callers don't repeat the parsing.
class _SessionReply {
  final int statusCode;
  final Map<String, dynamic> data;

  const _SessionReply(this.statusCode, this.data);

  bool get alreadyPaid => data['code'] == 'ALREADY_PAID';

  String? get checkoutUrl {
    final url = data['checkoutUrl'];
    return (url is String && url.isNotEmpty) ? url : null;
  }

  bool get ok => statusCode == 200 && data['success'] == true && checkoutUrl != null;

  String get message =>
      (data['message'] as String?) ?? 'Could not start your GCash/Maya payment. Please try again.';
}

class OnlinePaymentService {
  OnlinePaymentService._(); // static-only helper, never instantiated

  // Same Hostinger host the rest of this app already calls
  // (restore_trust.php, check_phone_risk.php).
  static const String _baseUrl = 'https://honeydew-duck-132160.hostingersite.com';
  static const String _createSessionEndpoint = '$_baseUrl/create_payment_session.php';

  static const List<String> onlineMethods = ['gcash', 'maya'];

  /// "GCash" -> "gcash", "PayMaya" -> "maya" (mirrors PaymentHelper::normalizeMethod).
  static String normalizeMethod(String? method) {
    final m = (method ?? '').trim().toLowerCase();
    return m == 'paymaya' ? 'maya' : m;
  }

  static bool isOnlineMethod(String? method) => onlineMethods.contains(normalizeMethod(method));

  /// Asks our server for a PayMongo GCash/Maya page for an EXISTING order.
  /// Returns the checkout URL, or null when the order turns out to be
  /// already paid (the server finalizes it in that case).
  static Future<String?> createCheckoutUrl({
    required String orderId,
    required String paymentMethod,
  }) async {
    final reply = await _requestSession(orderId, paymentMethod);
    if (reply.alreadyPaid) return null;
    if (!reply.ok) {
      throw OnlinePaymentException(reply.message, code: reply.data['code'] as String?);
    }
    return reply.checkoutUrl;
  }

  /// "I've paid — check status": asks the server to look the order up with
  /// PayMongo right now. The server's reuse logic finalizes a paid session
  /// and answers ALREADY_PAID, so this also works when the webhook is late
  /// or missing. Returns true when the order is paid.
  static Future<bool> isPaidNow({
    required String orderId,
    required String paymentMethod,
  }) async {
    final reply = await _requestSession(orderId, paymentMethod);
    if (reply.alreadyPaid) return true;
    if (reply.ok) return false; // session still open = not paid yet
    throw OnlinePaymentException(reply.message, code: reply.data['code'] as String?);
  }

  /// Live payment status of an order, straight from Firestore. The webhook
  /// (or the success-page fallback) flips paymentStatus to 'Paid', and this
  /// stream delivers that change to the app within a second or two.
  static Stream<String> watchPaymentStatus(String orderId) {
    return FirebaseFirestore.instance
        .collection('orders')
        .doc(orderId)
        .snapshots()
        .map((snap) => (snap.data()?['paymentStatus'] as String?) ?? 'Pending');
  }

  static Future<_SessionReply> _requestSession(String orderId, String paymentMethod) async {
    final method = normalizeMethod(paymentMethod);
    if (orderId.isEmpty) {
      throw const OnlinePaymentException('Missing order reference.');
    }
    if (!isOnlineMethod(method)) {
      throw const OnlinePaymentException('Please choose GCash or Maya for online payment.');
    }

    final user = FirebaseAuth.instance.currentUser;
    final String? idToken = user == null ? null : await user.getIdToken();
    if (idToken == null) {
      throw const OnlinePaymentException('Your session expired. Please sign in again to pay.');
    }

    final http.Response response;
    try {
      response = await http
          .post(
        Uri.parse(_createSessionEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'orderId': orderId, 'paymentMethod': method}),
      )
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw const OnlinePaymentException('The payment server took too long to answer. Please try again.');
    } catch (_) {
      throw const OnlinePaymentException('Could not reach the payment server. Check your connection and try again.');
    }

    // A PHP fatal returns HTML, not JSON — never let jsonDecode crash us.
    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {
      data = {};
    }

    return _SessionReply(response.statusCode, data);
  }
}