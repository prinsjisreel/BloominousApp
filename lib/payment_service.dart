import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_keys.dart';

class PaymentService {
  static const String _secretKey = ApiKeys.paymongoSecretKey;

  static Future<String> createCheckoutSession({
    required double amount,
    required String description,
    required String customerEmail,
    required String customerName,
    String? restrictToPaymentMethod,
  }) async {
    final url = Uri.parse('https://api.paymongo.com/v1/checkout_sessions');
    final int amountInCents = (amount * 100).toInt();
    const String baseUrl = 'https://ais-dev-hhshpab365hlsqyyluhzgs-94295932839.asia-east1.run.app';

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

  // --- NEW: same PayMongo call as above, but returns BOTH the checkout
  // URL and the session's own ID. The reservation deposit ledger needs
  // this ID so a future webhook (or manual admin confirmation) can look
  // up "which PayMongo session does this reservation's pending payment
  // correspond to" -- the original method above never exposed it, and
  // changing that method's return type would risk breaking whatever
  // other screens already call it expecting a plain String. ---
  static Future<Map<String, dynamic>> createCheckoutSessionDetailed({
    required double amount,
    required String description,
    required String customerEmail,
    required String customerName,
    String? restrictToPaymentMethod,
  }) async {
    final url = Uri.parse('https://api.paymongo.com/v1/checkout_sessions');
    final int amountInCents = (amount * 100).toInt();

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