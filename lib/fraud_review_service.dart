import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

/// Thrown when a review request fails. `code` mirrors fraud_review.php's
/// machine-readable reason (FORBIDDEN, REASON_REQUIRED, HISTORY_CHANGED,
/// NO_EVIDENCE, ALREADY_BLOCKED, ...) or a client-side reason (TIMEOUT,
/// NETWORK, BAD_RESPONSE, NO_SESSION), so the UI can react per case.
class FraudReviewException implements Exception {
  final String message;
  final String? code;
  FraudReviewException(this.message, {this.code});

  @override
  String toString() => message;
}

int _readInt(dynamic value, {int fallback = 0}) => value is num ? value.round() : fallback;
int? _readIntOrNull(dynamic value) => value is num ? value.round() : null;
double? _readDoubleOrNull(dynamic value) => value is num ? value.toDouble() : null;
DateTime? _readDate(dynamic value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// The customer's transaction history, computed by the server
/// (bloom_build_account_history() in includes/fraud_activity.php).
class AccountHistory {
  final String profile; // no_orders | cold_start | returning
  final DateTime? accountCreatedAt;
  final int? accountAgeDays;
  final int totalOrders;
  final int completedOrders;
  final int cancelledOrders;
  final int openOrders;
  final int flaggedOrders;
  final int? flaggedOrderPercent;
  final DateTime? firstOrderAt;
  final DateTime? lastOrderAt;
  final double completedSpend;
  final double? averageCompletedOrder;
  final double? latestOrderTotal;

  const AccountHistory({
    required this.profile,
    required this.accountCreatedAt,
    required this.accountAgeDays,
    required this.totalOrders,
    required this.completedOrders,
    required this.cancelledOrders,
    required this.openOrders,
    required this.flaggedOrders,
    required this.flaggedOrderPercent,
    required this.firstOrderAt,
    required this.lastOrderAt,
    required this.completedSpend,
    required this.averageCompletedOrder,
    required this.latestOrderTotal,
  });

  factory AccountHistory.fromJson(Map<String, dynamic> json) {
    return AccountHistory(
      profile: (json['historyProfile'] ?? 'no_orders').toString(),
      accountCreatedAt: _readDate(json['accountCreatedAt']),
      accountAgeDays: _readIntOrNull(json['accountAgeDays']),
      totalOrders: _readInt(json['totalOrders']),
      completedOrders: _readInt(json['completedOrders']),
      cancelledOrders: _readInt(json['cancelledOrders']),
      openOrders: _readInt(json['openOrders']),
      flaggedOrders: _readInt(json['flaggedOrders']),
      flaggedOrderPercent: _readIntOrNull(json['flaggedOrderPercent']),
      firstOrderAt: _readDate(json['firstOrderAt']),
      lastOrderAt: _readDate(json['lastOrderAt']),
      completedSpend: _readDoubleOrNull(json['completedSpend']) ?? 0,
      averageCompletedOrder: _readDoubleOrNull(json['averageCompletedOrder']),
      latestOrderTotal: _readDoubleOrNull(json['latestOrderTotal']),
    );
  }
}

/// The last admin decision stored on the customer (fraudReview).
class FraudReviewRecord {
  final String decision; // confirmed_fraud | false_alarm
  final String reason;
  final String reviewedByRole;
  final DateTime? reviewedAt;

  const FraudReviewRecord({
    required this.decision,
    required this.reason,
    required this.reviewedByRole,
    required this.reviewedAt,
  });

  static FraudReviewRecord? fromJson(dynamic json) {
    if (json is! Map) return null;
    final decision = json['decision']?.toString();
    if (decision != 'confirmed_fraud' && decision != 'false_alarm') return null;
    return FraudReviewRecord(
      decision: decision!,
      reason: (json['reason'] ?? '').toString(),
      reviewedByRole: (json['reviewedByRole'] ?? 'admin').toString(),
      reviewedAt: _readDate(json['reviewedAt']),
    );
  }
}

class AccountReviewData {
  final AccountHistory history;
  final FraudReviewRecord? review;
  const AccountReviewData({required this.history, required this.review});
}

class FraudDecisionResult {
  final String decision;
  final int bannedDeviceCount;
  final bool restrictionLifted;
  final int allowListedDevices;
  const FraudDecisionResult({
    required this.decision,
    required this.bannedDeviceCount,
    required this.restrictionLifted,
    required this.allowListedDevices,
  });
}

/// Calls fraud_review.php — the same endpoint the web dashboard uses, so
/// both platforms see the same history and save decisions the same way.
class FraudReviewService {
  // Same domain as OrderSubmissionService.
  static const String _endpoint =
      'https://honeydew-duck-132160.hostingersite.com/fraud_review.php';

  // Same limits as fraud_review.php (BLOOM_REVIEW_REASON_MIN/MAX_CHARS).
  static const int reasonMinChars = 15;
  static const int reasonMaxChars = 500;

  Future<AccountReviewData> fetchHistory(String uid) async {
    final data = await _post({'action': 'history', 'uid': uid});
    final history = data['history'];
    if (history is! Map) {
      throw FraudReviewException('The server returned an incomplete history.', code: 'BAD_RESPONSE');
    }
    return AccountReviewData(
      history: AccountHistory.fromJson(Map<String, dynamic>.from(history)),
      review: FraudReviewRecord.fromJson(data['review']),
    );
  }

  /// `seenHistory` is the history the admin was shown. Its counts are sent
  /// so the server can refuse (HISTORY_CHANGED) if new orders arrived.
  Future<FraudDecisionResult> decide({
    required String uid,
    required String decision,
    required String reason,
    required AccountHistory seenHistory,
  }) async {
    final data = await _post({
      'action': 'decide',
      'uid': uid,
      'decision': decision,
      'reason': reason.trim(),
      'seenTotalOrders': seenHistory.totalOrders,
      'seenFlaggedOrders': seenHistory.flaggedOrders,
    });
    return FraudDecisionResult(
      decision: (data['decision'] ?? decision).toString(),
      bannedDeviceCount: _readInt(data['bannedDeviceCount']),
      restrictionLifted: data['restrictionLifted'] == true,
      allowListedDevices: _readInt(data['allowListedDevices']),
    );
  }

  /// Readable preview of a non-JSON reply: HTML tags removed, whitespace
  /// squeezed, at most 200 characters.
  static String _previewOf(String body) {
    final text = body.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > 200 ? '${text.substring(0, 200)}...' : text;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> payload) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FraudReviewException('Your session has expired. Please log in again.', code: 'NO_SESSION');
    }
    final idToken = await user.getIdToken();

    http.Response response;
    try {
      response = await http
          .post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode(payload),
      )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw FraudReviewException(
        'The server is taking too long to respond. If you were saving a decision, reopen the log to check whether it was saved.',
        code: 'TIMEOUT',
      );
    } catch (e) {
      debugPrint('FraudReviewService: request failed: $e');
      throw FraudReviewException(
        'Could not reach the server. Please check your internet connection and try again.',
        code: 'NETWORK',
      );
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      // Full reply to the debug console; short preview to the admin.
      debugPrint(
        'FraudReviewService: non-JSON reply from $_endpoint '
            '(HTTP ${response.statusCode}):\n${response.body}',
      );
      final preview = _previewOf(response.body);
      throw FraudReviewException(
        'The server returned an unexpected response (HTTP ${response.statusCode}). '
            '${preview.isEmpty ? 'The reply was empty.' : 'Server said: "$preview"'}',
        code: 'BAD_RESPONSE',
      );
    }

    if (data['success'] != true) {
      throw FraudReviewException(
        data['message']?.toString() ?? 'The request could not be completed (HTTP ${response.statusCode}).',
        code: data['code']?.toString(),
      );
    }
    return data;
  }
}