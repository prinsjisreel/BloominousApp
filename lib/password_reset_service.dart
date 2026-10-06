import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Thrown when a reset email can't be requested. `code` mirrors the
/// server's reason when present (RATE_LIMITED) or a client-side one
/// (INVALID_EMAIL, TIMEOUT, NETWORK, BAD_RESPONSE).
class PasswordResetException implements Exception {
  final String message;
  final String? code;
  PasswordResetException(this.message, {this.code});

  @override
  String toString() => message;
}

/// Asks request_password_reset.php to email a password-reset link.
///
/// SAME endpoint the web's forgot_password.php uses, so both platforms get:
///   - the same BLOOM-styled email, sent from the shop's own Gmail,
///   - a secure, single-use Firebase reset link (the new password is set
///     on Firebase's own page — nothing in the app changes a password),
///   - the same server-side rate limits,
///   - the same answer whether or not the email has an account.
///
/// No sign-in or ID token needed: the customer is, by definition, locked out.
class PasswordResetService {
  static const String _endpoint =
      'https://honeydew-duck-132160.hostingersite.com/request_password_reset.php';

  // Same simple check the web page uses; the server validates properly.
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static bool isValidEmail(String email) => _emailPattern.hasMatch(email.trim());

  /// Returns the server's (neutral) success message.
  Future<String> requestReset(String rawEmail) async {
    final email = rawEmail.trim().toLowerCase();
    if (!isValidEmail(email)) {
      throw PasswordResetException('Please enter a valid email address.', code: 'INVALID_EMAIL');
    }

    // --- Send the request ---
    http.Response response;
    try {
      response = await http
          .post(
        Uri.parse(_endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      // The server may have sent the email even though the reply was slow.
      throw PasswordResetException(
        'The server is taking too long to respond. Please check your inbox before trying again.',
        code: 'TIMEOUT',
      );
    } catch (e) {
      debugPrint('PasswordResetService: request failed: $e');
      throw PasswordResetException(
        'Could not reach the server. Please check your internet connection and try again.',
        code: 'NETWORK',
      );
    }

    // --- Read the reply ---
    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw PasswordResetException(
        'The server returned an unexpected response. Please try again shortly.',
        code: 'BAD_RESPONSE',
      );
    }

    if (data['success'] != true) {
      throw PasswordResetException(
        data['message']?.toString() ?? 'We could not send the reset link right now. Please try again shortly.',
        code: data['code']?.toString(),
      );
    }

    return data['message']?.toString() ??
        "If an account exists for that email, we've sent a password reset link.";
  }
}