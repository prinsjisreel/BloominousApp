import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

/// Thrown when an appeal call fails. `code` mirrors the server's
/// machine-readable reason when it sends one (ALREADY_PENDING, COOLDOWN,
/// NOT_RESTRICTED, MESSAGE_INVALID, BLOCKED, RATE_LIMITED, ...) or a
/// client-side one (NETWORK, TIMEOUT, AUTH, BAD_RESPONSE), so the screen can
/// react differently per case.
class RestrictionAppealException implements Exception {
  final String message;
  final String? code;
  RestrictionAppealException(this.message, {this.code});

  @override
  String toString() => message;
}

/// What the server says about this customer's restriction and appeal.
/// Built from the `status` action of fraud_appeal.php.
class RestrictionAppealStatus {
  /// Is the account restricted right now (an expired restriction is NOT).
  final bool restricted;

  /// Can the customer send an appeal right now?
  final bool canAppeal;

  /// Why they can't: 'pending' (one is waiting for an admin) or 'cooldown'
  /// (the last one was denied and the waiting time isn't over). Null if they can.
  final String? blockedBy;

  /// When a new appeal is allowed again (only for the cooldown).
  final DateTime? canAppealAt;

  /// Latest appeal: 'pending' | 'approved' | 'denied' | null (never appealed).
  final String? appealStatus;
  final String appealMessage;
  final DateTime? submittedAt;
  final DateTime? decidedAt;

  /// Length limits the server enforces on the appeal text.
  final int minChars;
  final int maxChars;

  const RestrictionAppealStatus({
    required this.restricted,
    required this.canAppeal,
    required this.blockedBy,
    required this.canAppealAt,
    required this.appealStatus,
    required this.appealMessage,
    required this.submittedAt,
    required this.decidedAt,
    required this.minChars,
    required this.maxChars,
  });

  bool get isPending => appealStatus == 'pending';
  bool get isDenied => appealStatus == 'denied';

  factory RestrictionAppealStatus.fromJson(Map<String, dynamic> json) {
    final appeal = json['appeal'];
    final appealMap = appeal is Map ? Map<String, dynamic>.from(appeal) : <String, dynamic>{};

    DateTime? date(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
    int number(dynamic v, int fallback) => v is num ? v.toInt() : fallback;

    final status = appealMap['status']?.toString();
    return RestrictionAppealStatus(
      restricted: json['restricted'] == true,
      canAppeal: json['canAppeal'] == true,
      blockedBy: json['blockedBy']?.toString(),
      canAppealAt: date(json['canAppealAt']),
      appealStatus: (status == null || status.isEmpty) ? null : status,
      appealMessage: (appealMap['message'] ?? '').toString(),
      submittedAt: date(appealMap['submittedAt']),
      decidedAt: date(appealMap['decidedAt']),
      minChars: number(json['messageMinChars'], 20),
      maxChars: number(json['messageMaxChars'], 1000),
    );
  }
}

/// Talks to fraud_appeal.php, the ONE server door for restriction appeals
/// (the website uses the same file). The customer actions are:
///   status -> is the account restricted, is there an appeal, can a new one be sent?
///   submit -> save the appeal (admins review it in the Fraud Activity Log)
/// The admin action ("decide") lives in the admin screens, not here.
///
/// Like submit_order.php it only needs a Firebase ID token.
class RestrictionAppealService {
  static const String _endpoint =
      'https://honeydew-duck-132160.hostingersite.com/fraud_appeal.php';

  static const Duration _timeout = Duration(seconds: 30);

  Future<RestrictionAppealStatus> fetchStatus() async {
    final data = await _post({'action': 'status'});
    return RestrictionAppealStatus.fromJson(data);
  }

  Future<void> submit(String message) async {
    await _post({'action': 'submit', 'message': message});
  }

  /// One request to fraud_appeal.php. Returns the decoded JSON when the
  /// server says success, otherwise throws a [RestrictionAppealException]
  /// carrying the server's own message and code.
  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw RestrictionAppealException('Please sign in again.', code: 'AUTH');
    }

    String? idToken;
    try {
      idToken = await user.getIdToken();
    } on FirebaseAuthException catch (e) {
      debugPrint('RestrictionAppealService: getIdToken failed: ${e.code}');
      throw RestrictionAppealException(
        e.code == 'network-request-failed'
            ? 'Could not reach the server. Please check your internet connection.'
            : 'Your session has expired. Please sign out and sign in again.',
        code: e.code == 'network-request-failed' ? 'NETWORK' : 'AUTH',
      );
    }

    http.Response response;
    try {
      response = await http
          .post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode(body),
      )
          .timeout(_timeout);
    } on TimeoutException {
      throw RestrictionAppealException(
        'The server is taking too long to respond. Please try again.',
        code: 'TIMEOUT',
      );
    } catch (e) {
      debugPrint('RestrictionAppealService: request failed: $e');
      throw RestrictionAppealException(
        'Could not reach the server. Please check your internet connection and try again.',
        code: 'NETWORK',
      );
    }

    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException('not an object');
      data = Map<String, dynamic>.from(decoded);
    } catch (_) {
      // The host sometimes answers with an HTML error page instead of JSON.
      throw RestrictionAppealException(
        'The server sent an unexpected reply (HTTP ${response.statusCode}). Please try again.',
        code: 'BAD_RESPONSE',
      );
    }

    if (data['success'] != true) {
      throw RestrictionAppealException(
        (data['message'] ?? 'Your request could not be completed. Please try again.').toString(),
        code: data['code']?.toString(),
      );
    }
    return data;
  }
}