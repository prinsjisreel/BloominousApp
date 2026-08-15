import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_keys.dart';

class PaymentService {
  // --- PAYMONGO CONFIGURATION ---
  // Real key now lives in lib/api_keys.dart (gitignored) --
  // see lib/api_keys.example.dart for the setup template.
  static const String _secretKey = ApiKeys.paymongoSecretKey;

  static Future<String> createCheckoutSession({
    required double amount,
    required String description,
    required String customerEmail,
    required String customerName,
  }) async {
    final url = Uri.parse('https://api.paymongo.com/v1/checkout_sessions');

    // PayMongo amounts are in cents (e.g., 100.00 PHP = 10000)
    final int amountInCents = (amount * 100).toInt();

    // Ang base URL ng iyong app para sa redirects pagkatapos magbayad
    const String baseUrl = 'https://ais-dev-hhshpab365hlsqyyluhzgs-94295932839.asia-east1.run.app';

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
            // Listahan ng mga payment methods na suportado
            'payment_method_types': ['gcash', 'paymaya', 'card', 'dob', 'grab_pay'],
            // Sa loob ng createCheckoutSession function:
            'success_url': 'flowerar://success',
            'cancel_url': 'flowerar://cancel',
          }
        }
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      // Ibinabalik ang URL ng checkout page na bubuksan sa browser
      return data['data']['attributes']['checkout_url'];
    } else {
      final error = jsonDecode(response.body);
      throw Exception('Payment Error: ${error['errors'][0]['detail']}');
    }
  }
}