import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'api_keys.dart';

/// Thrown when create_payment_session.php refuses or fails. `code` mirrors
/// the server's reason when present (ALREADY_PAID, ORDER_CLOSED,
/// RATE_LIMITED) or a client-side one (TIMEOUT, NETWORK, BAD_RESPONSE).
class PaymentSessionException implements Exception {
  final String message;
  final String? code;
  PaymentSessionException(this.message, {this.code});

  @override
  String toString() => message;
}

class PaymentService {
  // Still used ONLY by createCheckoutSessionDetailed (reservation deposits)
  // and the deprecated createCheckoutSession below. Order payments no longer
  // touch it. Remove it from the app once reservations also move server-side.
  static const String _secretKey = ApiKeys.paymongoSecretKey;

  static const String _createSessionEndpoint =
      'https://honeydew-duck-132160.hostingersite.com/create_payment_session.php';

  /// Starts GCash/Maya payment for an order that submit_order.php already
  /// created. Same server endpoint the web checkout uses, so the app gets:
  ///   - the amount from the order in Firestore (never from the phone),
  ///   - the same rate limits,
  ///   - session reuse (tapping "Pay" twice returns the same page),
  ///   - no PayMongo secret key involved.
  /// Returns the PayMongo checkout URL to open.
  static Future<String> startOrderPayment({
    required String orderId,
    required String paymentMethod, // 'gcash' | 'maya'
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw PaymentSessionException('You must be signed in to pay.');
    }
    final idToken = await user.getIdToken();

    http.Response response;
    try {
      response = await http
          .post(
        Uri.parse(_createSessionEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'orderId': orderId,
          'paymentMethod': paymentMethod,
        }),
      )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw PaymentSessionException(
        'The payment service is taking too long. Please try again in a moment.',
        code: 'TIMEOUT',
      );
    } catch (e) {
      debugPrint('PaymentService.startOrderPayment request failed: $e');
      throw PaymentSessionException(
        'Could not reach the payment service. Please check your internet connection.',
        code: 'NETWORK',
      );
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw PaymentSessionException(
        'The payment service returned an unexpected response. Please try again.',
        code: 'BAD_RESPONSE',
      );
    }

    if (data['success'] != true) {
      throw PaymentSessionException(
        data['message']?.toString() ?? 'Could not start your payment.',
        code: data['code']?.toString(),
      );
    }

    final checkoutUrl = data['checkoutUrl'];
    if (checkoutUrl is! String || checkoutUrl.isEmpty) {
      throw PaymentSessionException(
        'The payment page link was missing. Please try again.',
        code: 'BAD_RESPONSE',
      );
    }
    return checkoutUrl;
  }

  /// OLD direct-to-PayMongo call. Uses the secret key from inside the app
  /// and trusts the amount the phone sends, so it skips every server-side
  /// check. Kept only so any screen still calling it keeps compiling —
  /// use startOrderPayment() for orders.
  @Deprecated('Use PaymentService.startOrderPayment() for orders.')
  static Future<String> createCheckoutSession({
    required double amount,
    required String description,
    required String customerEmail,
    required String customerName,
    String? restrictToPaymentMethod,
  }) async {
    final url = Uri.parse('https://api.paymongo.com/v1/checkout_sessions');
    // round(), not toInt(): 19.99 * 100 = 1998.999... must become 1999.
    final int amountInCents = (amount * 100).round();

    final List<String> paymentMethodTypes = restrictToPaymentMethod != null
        ? [restrictToPaymentMethod]
        : ['gcash', 'paymaya', 'card', 'dob', 'grab_pay'];

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Basic ${base64Encode(utf8.encode('$_secretKey:'))}',
      },
      body: jsonEncode({
        'data': {
          'attributes': {
            'send_email_receipt': true,
            'show_description': true,
            'show_line_items': true,
            'description': description,
            'line_items': [
              {
                'currency': 'PHP',
                'amount': amountInCents,
                'description': description,
                'name': 'Bloom Bouquet Order',
                'quantity': 1,
              }
            ],
            'payment_method_types': paymentMethodTypes,
            'success_url': 'flowerar://success',
            'cancel_url': 'flowerar://cancel',
          }
        }
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['data']['attributes']['checkout_url'];
    } else {
      final error = jsonDecode(response.body);
      throw Exception('Payment Error: ${error['errors'][0]['detail']}');
    }
  }

  // Same PayMongo call as above, but returns BOTH the checkout URL and the
  // session's own ID. The reservation deposit ledger needs this ID so a
  // future webhook (or manual admin confirmation) can look up which PayMongo
  // session a reservation's pending payment corresponds to.
  // NOTE: still calls PayMongo directly with the secret key. Next step is a
  // server endpoint for reservations, like create_payment_session.php.
  static Future<Map<String, dynamic>> createCheckoutSessionDetailed({
    required double amount,
    required String description,
    required String customerEmail,
    required String customerName,
    String? restrictToPaymentMethod,
  }) async {
    final url = Uri.parse('https://api.paymongo.com/v1/checkout_sessions');
    // round(), not toInt(): 19.99 * 100 = 1998.999... must become 1999.
    final int amountInCents = (amount * 100).round();

    final List<String> paymentMethodTypes = restrictToPaymentMethod != null
        ? [restrictToPaymentMethod]
        : ['gcash', 'paymaya', 'card', 'dob', 'grab_pay'];

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Basic ${base64Encode(utf8.encode('$_secretKey:'))}',
      },
      body: jsonEncode({
        'data': {
          'attributes': {
            'send_email_receipt': true,
            'show_description': true,
            'show_line_items': true,
            'description': description,
            'line_items': [
              {
                'currency': 'PHP',
                'amount': amountInCents,
                'description': description,
                'name': 'Bloom Reservation Booking Fee',
                'quantity': 1,
              }
            ],
            'payment_method_types': paymentMethodTypes,
            'success_url': 'flowerar://success',
            'cancel_url': 'flowerar://cancel',
          }
        }
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      final attrs = data['data']['attributes'];
      return {
        'checkoutUrl': attrs['checkout_url'],
        'sessionId': data['data']['id'],
      };
    } else {
      final error = jsonDecode(response.body);
      throw Exception('Payment Error: ${error['errors'][0]['detail']}');
    }
  }
}