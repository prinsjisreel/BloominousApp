import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_sidebar.dart';
import 'fraud_review_service.dart';

/*
 * BLOOMINOUS - Fraud Activity Log (mobile)
 *
 * Mobile twin of the web's fraud_analytics.php. Every recorded fraud
 * signal is grouped under the fraud activity categories from the study
 * this module is based on (account theft, payment fraud, fake
 * transactions, malicious returns).
 *
 * TRIAGE (written by includes/fraud_activity.php on the server):
 *   - Risk level (critical/high/medium/low): rule-based, from categories.
 *   - Triage score (0-100), shown as a bar.
 * Both only decide REVIEW ORDER.
 *
 * REVIEW + DECISION (inside each account's log sheet):
 *   1. Transaction History from fraud_review.php (server-computed).
 *   2. Admin Decision at the END of the sheet, after the evidence:
 *        Confirm Fraud     -> account blacklisted + its devices banned
 *        Mark False Alarm  -> restriction lifted (if any); account leaves
 *                             High Priority until new activity appears
 *      Both need a written reason, an up-to-date history, and a
 *      confirmation. The server re-checks everything.
 *
 * The class name stays FraudAnalyticsPage on purpose so existing routes
 * and AppSidebar(currentPage: 'fraud') keep working.
 */

// =====================================================================
// 1. CATEGORY, LEVEL AND SCORE DEFINITIONS
// Shared contract with fraud_analytics.php (JavaScript) and
// includes/fraud_activity.php (PHP). Never rename a key; only labels,
// icons, and colors may change.
// =====================================================================

class FraudCategory {
  final String label;
  final IconData icon;
  final Color color;
  const FraudCategory(this.label, this.icon, this.color);
}

const Map<String, FraudCategory> kFraudCategories = {
  'account_takeover': FraudCategory('Account Theft', Icons.person_off, Color(0xFF7C3AED)),
  'payment_fraud': FraudCategory('Payment Fraud', Icons.credit_card, Color(0xFF2563EB)),
  'fake_transaction': FraudCategory('Fake Transaction', Icons.receipt_long, Color(0xFFD97706)),
  'malicious_return': FraudCategory('Malicious Return', Icons.assignment_return, Color(0xFF0D9488)),
  'account_action': FraudCategory('Account Action', Icons.manage_accounts, Color(0xFF6B7280)),
  'other': FraudCategory('Other Signal', Icons.help_outline, Color(0xFF9CA3AF)),
};

// Only these four count toward the risk LEVEL
// (same list as BLOOM_FRAUD_CATEGORIES in PHP).
const Set<String> kStudyCategories = {
  'account_takeover',
  'payment_fraud',
  'fake_transaction',
  'malicious_return',
};

// Same as BLOOM_HARD_EVIDENCE_CODES in PHP.
const Set<String> kHardEvidenceCodes = {'banned_device'};

// Same as BLOOM_RISK_SCORE_CAP in PHP. The bar is drawn as a share of it.
const int kScoreMax = 100;

const Map<String, String> kDecisionLabels = {
  'confirmed_fraud': 'Confirmed Fraud',
  'false_alarm': 'False Alarm',
};

// Option B risk levels. Declaration ORDER is also the review order:
// critical first, low last. `name` (critical/high/medium/low) matches the
// string stored in Firestore.
enum RiskLevel {
  critical('CRITICAL RISK', Color(0xFF7F1D1D), Color(0xFFDC2626), Icons.dangerous),
  high('HIGH RISK', Color(0xFFDC2626), Color(0xFFF87171), Icons.warning_amber_rounded),
  medium('MEDIUM RISK', Color(0xFFD97706), Color(0xFFFBBF24), Icons.error_outline),
  low('LOW RISK', Color(0xFF16A34A), Color(0xFF34D399), Icons.check_circle_outline);

  const RiskLevel(this.label, this.lightColor, this.darkColor, this.icon);
  final String label;
  final Color lightColor;
  final Color darkColor;
  final IconData icon;

  // Dark backgrounds need a brighter shade to stay readable.
  Color colorFor(bool isDark) => isDark ? darkColor : lightColor;
}

// Turns the stored string ('high') into a RiskLevel. Anything unknown,
// missing, or misspelled returns null so the caller can fall back.
RiskLevel? parseRiskLevel(dynamic value) {
  if (value is! String) return null;
  for (final level in RiskLevel.values) {
    if (level.name == value) return level;
  }
  return null;
}

// Translates free-text flags into a category. Checked top to bottom; the
// first rule with a matching keyword wins. Same order and keywords as the
// web dashboard. 'blacklisted' and 'reviewed by admin' cover the notes
// written by fraud_review.php.
class _CategoryRule {
  final String category;
  final List<String> keywords;
  const _CategoryRule(this.category, this.keywords);
}

const List<_CategoryRule> _kCategoryRules = [
  _CategoryRule('account_action', [
    'restriction', 'restricted', 'trust restored', 'verified via', 'blacklisted', 'reviewed by admin',
  ]),
  _CategoryRule('malicious_return', ['refund', 'void', 'return', 'not delivered', 'wilted']),
  _CategoryRule('payment_fraud', ['payment', 'declined', 'dispute', 'chargeback']),
  _CategoryRule('account_takeover', ['tor/abuse', 'vpn', 'proxy', 'device-to-destination', 'new device', 'unrecognized device']),
  _CategoryRule('fake_transaction', [
    'banned device', 'disposable', 'voip', 'phone number already', 'address already',
    'repeat checkout', 'rapid checkouts', 'first order', 'email risk',
  ]),
];

// One flag, after classification: which category it belongs to, and the
// readable text to show.
class ClassifiedFlag {
  final String category;
  final String text;
  const ClassifiedFlag(this.category, this.text);

  // Account actions (restrictions, reviews, trust restored) are history.
  bool get isActivity => category != 'account_action';
}

// Accepts either an old text flag ("VPN/Proxy detected") or a new
// structured activity ({category, code, reason}) and always returns the
// same shape.
ClassifiedFlag classifyFlag(dynamic flag) {
  if (flag is Map) {
    final rawCategory = flag['category']?.toString();
    final category = kFraudCategories.containsKey(rawCategory) ? rawCategory! : 'other';
    final text = (flag['reason'] ?? flag['text'] ?? 'Unlabeled activity').toString();
    return ClassifiedFlag(category, text);
  }

  final text = flag?.toString() ?? '';
  final lower = text.toLowerCase();
  for (final rule in _kCategoryRules) {
    if (rule.keywords.any((word) => lower.contains(word))) {
      return ClassifiedFlag(rule.category, text);
    }
  }
  return ClassifiedFlag('other', text);
}

// Account states. Declaration ORDER is also the sort order.
enum AccountState {
  blocked('BLACKLISTED', Color(0xFF374151)),
  restricted('RESTRICTED', Color(0xFFDC2626)),
  flagged('FLAGGED ACTIVITY', Color(0xFFD97706)),
  reviewed('REVIEWED · FALSE ALARM', Color(0xFF059669)),
  clear('NO FLAGGED ACTIVITY', Color(0xFF16A34A));

  const AccountState(this.label, this.color);
  final String label;
  final Color color;
}

class _FilterOption {
  final String key;
  final String label;
  const _FilterOption(this.key, this.label);
}

const List<_FilterOption> _kFilters = [
  _FilterOption('all', 'All Accounts'),
  _FilterOption('priority', 'High Priority'),
  _FilterOption('flagged', 'Flagged Only'),
  _FilterOption('account_takeover', 'Account Theft'),
  _FilterOption('payment_fraud', 'Payment Fraud'),
  _FilterOption('fake_transaction', 'Fake Transaction'),
  _FilterOption('malicious_return', 'Malicious Return'),
];

const Color _kAccent = Color(0xFFF59E0B);
const Color _kPink = Color(0xFFEC4899);
const Color _kRose = Color(0xFFE11D48);
const Color _kFraudRed = Color(0xFFB91C1C);
const Color _kClearGreen = Color(0xFF059669);

// =====================================================================
// 2. SMALL HELPERS
// =====================================================================

// Firestore gives back "dynamic". This safely turns anything into a list,
// so a missing or malformed field becomes an empty list instead of a crash.
List<dynamic> _asList(dynamic value) => value is List ? value : const [];

// A score is only trusted when the server actually wrote a number.
int? readScore(Map<String, dynamic> data) {
  final value = data['riskScore'];
  if (value is num && value.isFinite) return value.round();
  return null;
}

// Same 30-day rule as bloom_restriction_state() in PHP: a restriction
// whose end date has passed no longer counts.
bool isRestrictionActive(Map<String, dynamic> data) {
  if (data['isRestricted'] != true) return false;
  final until = data['restrictedUntil'];
  if (until is Timestamp) return until.toDate().isAfter(DateTime.now());
  return true; // old record without an end date: still active
}

// "False alarm" counts only while no NEW activity arrived after it.
bool isDismissed(Map<String, dynamic> data) {
  final review = data['fraudReview'];
  if (review is! Map || review['decision'] != 'false_alarm') return false;
  final reviewedAt = review['reviewedAt'];
  if (reviewedAt is! Timestamp) return false;
  final last = data['lastFraudActivityAt'];
  if (last is! Timestamp) return true;
  return reviewedAt.compareTo(last) >= 0;
}

/// Risk level for one account or order document.
/// 1) A valid stored riskLevel wins (the server is the source of truth).
/// 2) Otherwise (data recorded before triage existed) derive it with the
///    SAME Option B rule as bloom_fraud_risk_level() in PHP.
RiskLevel deriveRiskLevel(Map<String, dynamic> data, List<ClassifiedFlag> activity) {
  final stored = parseRiskLevel(data['riskLevel']);
  if (stored != null) return stored;

  final codes = _asList(data['fraudCodes']).map((e) => e.toString());
  final hasHardEvidence = codes.any(kHardEvidenceCodes.contains) ||
      activity.any((f) => f.text.toLowerCase().contains('banned device'));
  if (hasHardEvidence) return RiskLevel.critical;

  final distinct = activity.map((f) => f.category).where(kStudyCategories.contains).toSet();
  if (distinct.length >= 2) return RiskLevel.high;
  if (distinct.length == 1) return RiskLevel.medium;
  return RiskLevel.low;
}

String maskCustomerName(String name) {
  if (name.trim().isEmpty) return 'A********* U***';
  final words = name.trim().split(RegExp(r'\s+'));
  final masked = <String>[];
  for (final word in words) {
    if (word.isEmpty) continue;
    if (word.length <= 1) {
      masked.add('*');
    } else if (word.length == 2) {
      masked.add('${word[0]}*');
    } else {
      masked.add(word[0] + '*' * (word.length - 2) + word[word.length - 1]);
    }
  }
  return masked.join(' ');
}

String _formatPeso(dynamic amount) {
  final value = amount is num ? amount.toDouble() : (double.tryParse('$amount') ?? 0);
  final parts = value.toStringAsFixed(2).split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  return '₱$whole.${parts[1]}';
}

String _formatDate(DateTime d) => '${d.month}/${d.day}/${d.year}';

String _formatDateOrDash(DateTime? d) => d == null ? '—' : _formatDate(d);

String _formatDateTime(DateTime d) {
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final period = d.hour < 12 ? 'AM' : 'PM';
  return '${_formatDate(d)} $hour12:$minute $period';
}

// Orders from submit_order.php carry createdAt; some older or POS-created
// ones only carry timestamp. Try both.
int _orderMillis(Map<String, dynamic> order) {
  final ts = order['createdAt'] ?? order['timestamp'];
  return ts is Timestamp ? ts.millisecondsSinceEpoch : 0;
}

// Plain-language note for each history profile (same wording as web).
String _historyNote(AccountHistory h) {
  switch (h.profile) {
    case 'cold_start':
      return "Limited history to compare against: none of this account's orders has been completed yet. Weigh the recorded evidence carefully.";
    case 'returning':
      return '${h.completedOrders} completed order(s) on record. A single flagged order may be a false positive, but long-standing accounts can still be misused, so check the order log too.';
    default:
      return 'This account has never placed an order.';
  }
}

String _historyProfileLabel(String profile) {
  switch (profile) {
    case 'cold_start':
      return 'NEW ACCOUNT · NO COMPLETED ORDERS';
    case 'returning':
      return 'RETURNING CUSTOMER';
    default:
      return 'NO ORDERS YET';
  }
}

// One-line text version, reused in the confirmation dialog.
String _historySummaryText(AccountHistory h) {
  final age = h.accountAgeDays != null ? '${h.accountAgeDays} day(s) old' : 'account age unknown';
  final pct = h.flaggedOrderPercent != null ? ' (${h.flaggedOrderPercent}%)' : '';
  return '${_historyProfileLabel(h.profile)}, $age. Orders: ${h.totalOrders} total, '
      '${h.completedOrders} completed, ${h.cancelledOrders} cancelled, ${h.flaggedOrders} flagged$pct.';
}

// =====================================================================
// 3. ACCOUNT SUMMARY — one customer document, ready to display
// =====================================================================

class AccountSummary {
  final String id;
  final Map<String, dynamic> data;
  final String name;
  final String maskedName;
  final String email;
  final List<ClassifiedFlag> classified;
  final List<ClassifiedFlag> activity;
  final Map<String, int> counts;
  final AccountState state;
  final RiskLevel level;
  final int? score; // null = "Not scored" (legacy flagged account)
  final bool dismissed;
  final int deviceCount;

  const AccountSummary({
    required this.id,
    required this.data,
    required this.name,
    required this.maskedName,
    required this.email,
    required this.classified,
    required this.activity,
    required this.counts,
    required this.state,
    required this.level,
    required this.score,
    required this.dismissed,
    required this.deviceCount,
  });

  factory AccountSummary.fromDoc(String id, Map<String, dynamic> data) {
    final email = (data['email'] ?? '').toString();
    final rawName = (data['name'] ?? data['fullName'] ?? data['username'] ?? '').toString().trim();
    final name = rawName.isNotEmpty
        ? rawName
        : (email.contains('@') ? email.split('@')[0] : 'Registered User');

    final classified = _asList(data['fraudFlags']).map(classifyFlag).toList();
    final activity = classified.where((f) => f.isActivity).toList();

    final counts = <String, int>{};
    for (final f in activity) {
      counts[f.category] = (counts[f.category] ?? 0) + 1;
    }

    final dismissed = isDismissed(data);

    AccountState state;
    if (data['status'] == 'blocked') {
      state = AccountState.blocked;
    } else if (isRestrictionActive(data)) {
      state = AccountState.restricted;
    } else if (activity.isNotEmpty) {
      state = dismissed ? AccountState.reviewed : AccountState.flagged;
    } else {
      state = AccountState.clear;
    }

    // Score rules (same as web):
    //   server wrote a number          -> use it
    //   no number AND no activity       -> truly 0 points
    //   no number BUT activity exists   -> null ("Not scored", legacy)
    final storedScore = readScore(data);
    final score = storedScore ?? (activity.isEmpty ? 0 : null);

    return AccountSummary(
      id: id,
      data: data,
      name: name,
      maskedName: maskCustomerName(name),
      email: email,
      classified: classified,
      activity: activity,
      counts: counts,
      state: state,
      level: deriveRiskLevel(data, activity),
      score: score,
      dismissed: dismissed,
      deviceCount: _asList(data['deviceHashes']).length,
    );
  }

  bool get isActioned => state == AccountState.blocked || state == AccountState.restricted;

  // Only show triage when there is something to triage.
  bool get hasTriage => level != RiskLevel.low || activity.isNotEmpty;

  // High priority = still NEEDS a decision: critical/high level, not
  // already blacklisted, and not cleared as a false alarm.
  bool get isHighPriority =>
      (level == RiskLevel.critical || level == RiskLevel.high) &&
          state != AccountState.blocked &&
          !dismissed;

  // The decision stored on the account (if any), for the card line.
  String? get lastReviewLine {
    final review = data['fraudReview'];
    if (review is! Map) return null;
    final label = kDecisionLabels[review['decision']];
    if (label == null) return null;
    final reviewedAt = review['reviewedAt'];
    final when = reviewedAt is Timestamp ? ' • ${_formatDate(reviewedAt.toDate())}' : '';
    return 'Last review: $label$when';
  }
}

// =====================================================================
// 4. SHARED SMALL WIDGETS
// =====================================================================

class _CategoryChip extends StatelessWidget {
  final String category;
  final String suffix;
  const _CategoryChip({required this.category, this.suffix = ''});

  @override
  Widget build(BuildContext context) {
    final meta = kFraudCategories[category] ?? kFraudCategories['other']!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: meta.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: meta.color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: 11, color: meta.color),
          const SizedBox(width: 4),
          Text(
            '${meta.label}$suffix',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: meta.color),
          ),
        ],
      ),
    );
  }
}

class _FlagRow extends StatelessWidget {
  final ClassifiedFlag flag;
  final Color textColor;
  const _FlagRow({required this.flag, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CategoryChip(category: flag.category),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(flag.text, style: TextStyle(fontSize: 11, color: textColor, height: 1.4)),
            ),
          ),
        ],
      ),
    );
  }
}

// Generic small badge (state, profile).
class _TextBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const _TextBadge({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.3, color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// Level badge. Critical is a solid fill (like web's lvl-critical).
class _LevelBadge extends StatelessWidget {
  final RiskLevel level;
  const _LevelBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = level.colorFor(isDark);
    final isSolid = level == RiskLevel.critical;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isSolid ? color : color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isSolid ? color : color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(level.icon, size: 11, color: isSolid ? Colors.white : color),
          const SizedBox(width: 4),
          Text(
            level.label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
              color: isSolid ? Colors.white : color,
            ),
          ),
        ],
      ),
    );
  }
}

// Compact pill, used on single orders inside the log.
class _ScorePill extends StatelessWidget {
  final int? score;
  const _ScorePill({required this.score});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unscored = score == null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withOpacity(0.25)),
      ),
      child: Text(
        unscored ? 'Not scored' : '$score pts',
        style: TextStyle(
          fontSize: 9,
          fontWeight: unscored ? FontWeight.w700 : FontWeight.w900,
          fontStyle: unscored ? FontStyle.italic : FontStyle.normal,
          color: unscored ? Colors.grey[500] : (isDark ? Colors.white : const Color(0xFF374151)),
        ),
      ),
    );
  }
}

// Triage score with a bar line.
class _ScoreBar extends StatelessWidget {
  final int? score;
  final RiskLevel level;
  const _ScoreBar({required this.score, required this.level});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = isDark ? Colors.white10 : const Color(0xFFF3F4F6);
    final labelStyle = TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.grey[500]);

    final unscored = score == null;
    final safeScore = unscored ? 0 : score!.clamp(0, kScoreMax).toInt();
    // Must be a real number between 0.0 and 1.0. Passing null would turn
    // the bar into an endless "loading" animation.
    final fraction = safeScore / kScoreMax;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('TRIAGE SCORE', style: labelStyle),
            const Spacer(),
            if (unscored)
              Text(
                'Not scored',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic, color: Colors.grey[500]),
              )
            else
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$safeScore',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF1F2937),
                      ),
                    ),
                    TextSpan(
                      text: ' / $kScoreMax',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Semantics(
          label: 'Triage score',
          value: unscored ? 'Not scored' : '$safeScore out of $kScoreMax',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: trackColor,
              valueColor: AlwaysStoppedAnimation<Color>(
                unscored ? Colors.grey.withOpacity(0.4) : level.colorFor(isDark),
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          unscored ? 'Recorded before triage scoring existed.' : 'Sets review order only.',
          style: TextStyle(fontSize: 9.5, color: Colors.grey[500]),
        ),
      ],
    );
  }
}

// One cell in the transaction-history grid.
class _HistoryStat extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final double width;
  const _HistoryStat({required this.label, required this.value, this.sub, required this.width});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 0.6, color: Colors.grey[500])),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: isDark ? Colors.white : const Color(0xFF1F2937))),
          if (sub != null && sub!.isNotEmpty)
            Text(sub!, style: TextStyle(fontSize: 9.5, color: Colors.grey[500])),
        ],
      ),
    );
  }
}

// =====================================================================
// 5. THE PAGE
// =====================================================================

class FraudAnalyticsPage extends StatefulWidget {
  final String role;
  const FraudAnalyticsPage({super.key, this.role = 'employee'});

  @override
  State<FraudAnalyticsPage> createState() => _FraudAnalyticsPageState();
}

class _FraudAnalyticsPageState extends State<FraudAnalyticsPage> {
  // Same rule as the web page: admin and super-admin only.
  static const Set<String> _adminRoles = {'admin', 'super-admin'};

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _activeFilter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------------- Filtering ----------------

  bool _matchesFilter(AccountSummary a) {
    if (_activeFilter == 'all') return true;
    if (_activeFilter == 'priority') return a.isHighPriority;
    if (_activeFilter == 'flagged') return a.state != AccountState.clear;
    return (a.counts[_activeFilter] ?? 0) > 0;
  }

  bool _matchesSearch(AccountSummary a) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    return a.name.toLowerCase().contains(q) ||
        a.id.toLowerCase().contains(q) ||
        a.email.toLowerCase().contains(q);
  }

  // Review order (triage), same as web.
  int _compareAccounts(AccountSummary a, AccountSummary b) {
    final byState = a.state.index.compareTo(b.state.index);
    if (byState != 0) return byState;
    final byLevel = a.level.index.compareTo(b.level.index);
    if (byLevel != 0) return byLevel;
    final byScore = (b.score ?? -1).compareTo(a.score ?? -1);
    if (byScore != 0) return byScore;
    final byActivity = b.activity.length.compareTo(a.activity.length);
    if (byActivity != 0) return byActivity;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  void _openFraudActivityLog(AccountSummary a) {
    // The masked name is passed (never the real one): the log is a
    // privacy-sensitive detail view, same as on web.
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FraudActivityLogSheet(uid: a.id, maskedName: a.maskedName),
    );
  }

  // ---------------- Build ----------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width >= 850;
    final isAdmin = _adminRoles.contains(widget.role);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFFFFDF9),
      appBar: AppBar(
        title: Text(
          'Fraud Activity Log',
          style: GoogleFonts.cormorantGaramond(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        backgroundColor: isDark ? Colors.black : const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      drawer: isDesktop ? null : Drawer(child: AppSidebar(role: widget.role, currentPage: 'fraud')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) AppSidebar(role: widget.role, currentPage: 'fraud'),
          Expanded(child: isAdmin ? _buildLiveLog(isDark) : _buildNoAccess(isDark)),
        ],
      ),
    );
  }

  Widget _buildNoAccess(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 40, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'Admins only',
              style: GoogleFonts.cormorantGaramond(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The Fraud Activity Log is available to admin and super-admin accounts.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveLog(bool isDark) {
    // Live listener: rebuilds whenever ANY customer document changes
    // (a new flag, a new score, a decision...), on web or mobile.
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('customers').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Could not load accounts: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: _kAccent));
        }

        final accounts = snapshot.data!.docs
            .map((doc) => AccountSummary.fromDoc(doc.id, doc.data()))
            .toList()
          ..sort(_compareAccounts);

        final totalCount = accounts.length;
        final priorityCount = accounts.where((a) => a.isHighPriority).length;
        final flaggedCount = accounts.where((a) => a.state != AccountState.clear).length;
        final actionedCount = accounts.where((a) => a.isActioned).length;

        final visible = accounts.where((a) => _matchesFilter(a) && _matchesSearch(a)).toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isDark),
              const SizedBox(height: 20),
              _buildCounters(isDark, totalCount, priorityCount, flaggedCount, actionedCount),
              const SizedBox(height: 20),
              _buildFilterBar(isDark),
              const SizedBox(height: 20),
              if (visible.isEmpty)
                Container(
                  height: 140,
                  width: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[900] : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.withOpacity(0.15)),
                  ),
                  child: Text(
                    'No accounts match this view.',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: visible.length,
                  itemBuilder: (context, index) => _buildAccountCard(visible[index], isDark),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fraud Activity Log',
              style: GoogleFonts.cormorantGaramond(
                fontSize: isMobile ? 24 : 28,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Accounts are ordered by risk level and triage score so the riskiest are reviewed first. '
                  "Decisions are made inside each account's log, after reviewing its history.",
              style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600]),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: isMobile ? double.infinity : 320,
              height: 42,
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Search Account Name or UID...',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
                  filled: true,
                  fillColor: isDark ? Colors.grey[900] : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: _kAccent, width: 1.5),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCounters(bool isDark, int total, int priority, int flagged, int actioned) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 2 boxes per row on phones, 4 on wide screens.
        final perRow = constraints.maxWidth < 600 ? 2 : 4;
        final cardWidth = (constraints.maxWidth - 12 * (perRow - 1)) / perRow;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildStatBox('ACCOUNTS MONITORED', '$total', Icons.people_outline, _kPink, isDark,
                width: cardWidth),
            _buildStatBox('HIGH PRIORITY', '$priority', Icons.warning_amber_rounded, _kRose, isDark,
                width: cardWidth, valueColor: _kRose),
            _buildStatBox('FLAGGED ACTIVITY', '$flagged', Icons.flag_outlined, _kAccent, isDark,
                width: cardWidth, valueColor: _kAccent),
            _buildStatBox('RESTRICTED / BLACKLISTED', '$actioned', Icons.lock_outline,
                const Color(0xFFDC2626), isDark,
                width: cardWidth, valueColor: const Color(0xFFDC2626)),
          ],
        );
      },
    );
  }

  Widget _buildFilterBar(bool isDark) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _kFilters.map((f) {
        final selected = f.key == _activeFilter;
        return ChoiceChip(
          label: Text(
            f.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : (isDark ? Colors.grey[300] : Colors.grey[700]),
            ),
          ),
          selected: selected,
          onSelected: (_) => setState(() => _activeFilter = f.key),
          selectedColor: _kPink,
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          shape: StadiumBorder(
            side: BorderSide(color: selected ? _kPink : Colors.grey.withOpacity(0.25)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAccountCard(AccountSummary a, bool isDark) {
    final stateColor = a.state.color;
    final restrictedUntil = a.data['restrictedUntil'];
    final showRestrictedUntil = a.state == AccountState.restricted && restrictedUntil is Timestamp;
    final reviewLine = a.lastReviewLine;

    final latest = a.activity.length <= 3 ? a.activity : a.activity.sublist(a.activity.length - 3);
    final latestText = latest.isEmpty
        ? 'No fraud activity on file for this account.'
        : latest.map((f) => f.text).join('  •  ');

    // Chips follow the fixed category order, not the order flags arrived.
    final categoryChips = kFraudCategories.keys
        .where((key) => a.counts.containsKey(key))
        .map((key) => _CategoryChip(category: key, suffix: ' ×${a.counts[key]}'))
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: a.isActioned ? stateColor.withOpacity(0.4) : Colors.grey.withOpacity(0.15),
          width: a.isActioned ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Name + state badge ---
          Row(
            children: [
              Expanded(
                child: a.isActioned
                    ? Row(
                  children: [
                    const Icon(Icons.visibility, size: 16, color: Color(0xFFDC2626)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        a.name,
                        style: GoogleFonts.cormorantGaramond(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFDC2626),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                )
                    : Text(
                  a.maskedName,
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: _TextBadge(label: a.state.label, color: stateColor)),
            ],
          ),

          // --- Risk level badge (only when there is something to triage) ---
          if (a.hasTriage) ...[
            const SizedBox(height: 8),
            _LevelBadge(level: a.level),
          ],
          const SizedBox(height: 8),

          // --- UID + device count ---
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  'UID: ${a.id}',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500], fontFamily: 'monospace', fontWeight: FontWeight.w500),
                ),
              ),
              Text(
                '${a.deviceCount} device${a.deviceCount == 1 ? '' : 's'} on file',
                style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w500),
              ),
            ],
          ),
          if (showRestrictedUntil) ...[
            const SizedBox(height: 4),
            Text(
              'Restricted until ${_formatDate((restrictedUntil as Timestamp).toDate())}',
              style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626), fontWeight: FontWeight.w600),
            ),
          ],
          if (reviewLine != null) ...[
            const SizedBox(height: 4),
            Text(reviewLine, style: TextStyle(fontSize: 10.5, color: Colors.grey[600], fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 12),

          // --- Recorded activity types ---
          Text(
            'RECORDED ACTIVITY TYPES',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.grey[500], letterSpacing: 0.5),
          ),
          const SizedBox(height: 6),
          if (categoryChips.isEmpty)
            Text(
              'No fraud activity recorded',
              style: TextStyle(fontSize: 11, color: Colors.grey[500], fontStyle: FontStyle.italic),
            )
          else
            Wrap(spacing: 6, runSpacing: 6, children: categoryChips),
          const SizedBox(height: 14),

          // --- Triage score bar ---
          _ScoreBar(score: a.score, level: a.level),
          const SizedBox(height: 12),

          // --- Latest activity -> opens the Fraud Activity Log ---
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openFraudActivityLog(a),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withOpacity(0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LATEST RECORDED ACTIVITY',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.grey[500], letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    latestText,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Row(
                    children: [
                      Icon(Icons.history, size: 12, color: _kAccent),
                      SizedBox(width: 4),
                      Text(
                        'Open Fraud Activity Log →',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _kAccent, letterSpacing: 0.2),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox(String label, String value, IconData icon, Color iconColor, bool isDark,
      {Color? valueColor, double? width}) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey[400], letterSpacing: 0.3),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: valueColor ?? (isDark ? Colors.white : Colors.black87),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(icon, color: iconColor, size: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// 6. FRAUD ACTIVITY LOG SHEET — mobile twin of the web modal
// =====================================================================

class _OrderEntry {
  final String id;
  final Map<String, dynamic> data;
  final List<ClassifiedFlag> flags;
  final int millis;
  const _OrderEntry(this.id, this.data, this.flags, this.millis);

  bool get hasActivity => flags.any((f) => f.isActivity);
}

class _FraudActivityLogSheet extends StatefulWidget {
  final String uid;
  final String maskedName;
  const _FraudActivityLogSheet({required this.uid, required this.maskedName});

  @override
  State<_FraudActivityLogSheet> createState() => _FraudActivityLogSheetState();
}

class _FraudActivityLogSheetState extends State<_FraudActivityLogSheet> {
  // Created ONCE in initState. If these were created inside build(),
  // every rebuild (like typing a reason) would start a new request.
  late final Future<QuerySnapshot<Map<String, dynamic>>> _ordersFuture;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _customerStream;

  final FraudReviewService _reviewService = FraudReviewService();
  final TextEditingController _reasonController = TextEditingController();

  bool _flaggedOnly = false;

  // Transaction history (from fraud_review.php).
  AccountReviewData? _reviewData;
  String? _historyError;
  bool _historyLoading = true;

  // Decision state.
  bool _decisionBusy = false;
  String? _decisionMessage;
  bool _decisionMessageIsError = false;

  @override
  void initState() {
    super.initState();
    final db = FirebaseFirestore.instance;
    // No .orderBy() on purpose: an equality filter on user_id plus a sort
    // on a DIFFERENT field needs a manually created composite index. The
    // per-customer result set is small, so it's sorted in Dart instead.
    _ordersFuture = db.collection('orders').where('user_id', isEqualTo: widget.uid).limit(50).get();
    _customerStream = db.collection('customers').doc(widget.uid).snapshots();
    _reasonController.addListener(_onReasonChanged);
    _loadHistory();
  }

  @override
  void dispose() {
    _reasonController.removeListener(_onReasonChanged);
    _reasonController.dispose();
    super.dispose();
  }

  // Rebuild so the decision buttons enable/disable as the admin types.
  void _onReasonChanged() {
    if (mounted) setState(() {});
  }

  // Loads (or reloads) the history. The decision buttons stay disabled
  // until this finishes, so nobody decides without seeing it.
  Future<void> _loadHistory() async {
    // setState can't run during initState; the first load starts with
    // _historyLoading already true.
    if (!_historyLoading && mounted) {
      setState(() {
        _historyLoading = true;
        _historyError = null;
        _reviewData = null;
      });
    }
    try {
      final data = await _reviewService.fetchHistory(widget.uid);
      if (!mounted) return;
      setState(() {
        _reviewData = data;
        _historyError = null;
        _historyLoading = false;
      });
    } on FraudReviewException catch (e) {
      if (!mounted) return;
      setState(() {
        _historyError = e.message;
        _historyLoading = false;
      });
    }
  }

  Future<bool> _confirmDecisionDialog(String decision, AccountHistory history) async {
    final isFraud = decision == 'confirmed_fraud';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isFraud ? 'Confirm fraud for this account?' : 'Mark as a false alarm?'),
        content: SingleChildScrollView(
          child: Text(
            '${isFraud
                ? 'This will BLACKLIST the account and BAN every device linked to it. It cannot be undone from this screen.'
                : 'Nothing is punished. If the account is restricted, the restriction is lifted. The account leaves High Priority until new activity appears.'}'
                '\n\nHistory you reviewed:\n${_historySummaryText(history)}',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: isFraud ? _kFraudRed : _kClearGreen),
            child: Text(isFraud ? 'CONFIRM FRAUD' : 'MARK FALSE ALARM', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _submitDecision(String decision) async {
    final data = _reviewData;
    if (data == null || _decisionBusy) return;

    final reason = _reasonController.text.trim();
    if (reason.length < FraudReviewService.reasonMinChars) {
      setState(() {
        _decisionMessage = 'Please write at least ${FraudReviewService.reasonMinChars} characters explaining your decision.';
        _decisionMessageIsError = true;
      });
      return;
    }

    final confirmed = await _confirmDecisionDialog(decision, data.history);
    if (!confirmed || !mounted) return;

    setState(() {
      _decisionBusy = true;
      _decisionMessage = 'Saving decision...';
      _decisionMessageIsError = false;
    });

    try {
      final result = await _reviewService.decide(
        uid: widget.uid,
        decision: decision,
        reason: reason,
        seenHistory: data.history,
      );
      if (!mounted) return;

      String message;
      if (result.decision == 'confirmed_fraud') {
        message = 'Decision saved. Account blacklisted; ${result.bannedDeviceCount} device(s) banned.';
      } else {
        final extras = <String>[
          if (result.restrictionLifted) 'restriction lifted',
          if (result.allowListedDevices > 0) 'allowed on ${result.allowListedDevices} banned device(s)',
        ];
        message = 'Decision saved as false alarm${extras.isEmpty ? '' : ' (${extras.join(', ')})'}.';
      }

      _reasonController.clear();
      setState(() {
        _decisionMessage = message;
        _decisionMessageIsError = false;
      });
      await _loadHistory(); // refreshes "Last review"
    } on FraudReviewException catch (e) {
      if (!mounted) return;
      setState(() {
        _decisionMessage = e.message;
        _decisionMessageIsError = true;
      });
      if (e.code == 'HISTORY_CHANGED') {
        await _loadHistory();
      }
    } finally {
      if (mounted) setState(() => _decisionBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final borderColor = isDark ? const Color(0xFF2A2A2A) : Colors.grey.withOpacity(0.15);
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: sheetColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Fraud Activity Log — ${widget.maskedName}',
                        style: GoogleFonts.cormorantGaramond(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: subTextColor),
                      onPressed: _decisionBusy ? null : () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('UID: ${widget.uid}', style: TextStyle(fontSize: 10, color: subTextColor, fontFamily: 'monospace')),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _customerStream,
                  builder: (context, snapshot) {
                    final customerData = snapshot.data?.data();
                    final summary = customerData == null ? null : AccountSummary.fromDoc(widget.uid, customerData);

                    return ListView(
                      controller: scrollController,
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + keyboardInset),
                      children: [
                        _buildAccountPart(snapshot, summary, textColor, subTextColor, borderColor),
                        const SizedBox(height: 22),
                        _sectionTitle('TRANSACTION HISTORY', subTextColor),
                        const SizedBox(height: 8),
                        _buildHistorySection(subTextColor, borderColor),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            _sectionTitle('ORDER LOG', subTextColor),
                            const Spacer(),
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => setState(() => _flaggedOnly = !_flaggedOnly),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Checkbox(
                                      value: _flaggedOnly,
                                      activeColor: _kPink,
                                      onChanged: (v) => setState(() => _flaggedOnly = v ?? false),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text('Flagged orders only',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: subTextColor)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildOrderLog(textColor, subTextColor, borderColor, isDark),
                        const SizedBox(height: 22),
                        _sectionTitle('ADMIN DECISION', subTextColor),
                        const SizedBox(height: 8),
                        _buildDecisionSection(summary, textColor, subTextColor, borderColor, isDark),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String text, Color color) {
    return Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color, letterSpacing: 1));
  }

  Widget _emptyText(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: color, fontStyle: FontStyle.italic, fontSize: 12)),
      ),
    );
  }

  // Risk summary + account-level activity, from the live customer doc.
  Widget _buildAccountPart(
      AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
      AccountSummary? summary,
      Color textColor,
      Color subTextColor,
      Color borderColor,
      ) {
    if (snapshot.hasError) {
      return Text('Could not load account: ${snapshot.error}', style: TextStyle(fontSize: 11, color: subTextColor));
    }
    if (summary == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent))),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _LevelBadge(level: summary.level),
                  _TextBadge(label: summary.state.label, color: summary.state.color),
                ],
              ),
              const SizedBox(height: 12),
              _ScoreBar(score: summary.score, level: summary.level),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _sectionTitle('ACCOUNT-LEVEL ACTIVITY', subTextColor),
        const SizedBox(height: 4),
        if (summary.classified.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Nothing recorded at the account level.',
                style: TextStyle(fontSize: 11, color: subTextColor, fontStyle: FontStyle.italic)),
          )
        else
          ...summary.classified.map((f) => _FlagRow(flag: f, textColor: textColor)),
      ],
    );
  }

  Widget _buildHistorySection(Color subTextColor, Color borderColor) {
    if (_historyLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(color: _kAccent)),
      );
    }
    if (_historyError != null || _reviewData == null) {
      return Column(
        children: [
          _emptyText('Could not load transaction history: ${_historyError ?? 'unknown error'}', subTextColor),
          TextButton(onPressed: _loadHistory, child: const Text('TRY AGAIN')),
        ],
      );
    }

    final h = _reviewData!.history;
    final profileColor = h.profile == 'cold_start' ? const Color(0xFFD97706) : const Color(0xFF16A34A);
    final age = h.accountAgeDays != null ? '${h.accountAgeDays} day(s)' : 'Unknown';
    final flagged = h.flaggedOrderPercent != null ? '${h.flaggedOrders} (${h.flaggedOrderPercent}%)' : '${h.flaggedOrders}';

    // Latest order compared with this customer's own usual spend.
    String? latestSub;
    final avg = h.averageCompletedOrder;
    if (h.latestOrderTotal != null && avg != null && avg > 0) {
      latestSub = '${(h.latestOrderTotal! / avg).toStringAsFixed(1)}x their average completed order';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final perRow = constraints.maxWidth < 420 ? 2 : 3;
          final cellWidth = (constraints.maxWidth - 8 * (perRow - 1)) / perRow;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TextBadge(label: _historyProfileLabel(h.profile), color: profileColor, icon: Icons.person_search),
              const SizedBox(height: 8),
              Text(_historyNote(h), style: TextStyle(fontSize: 11, color: subTextColor, height: 1.4)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _HistoryStat(label: 'Account Age', value: age,
                      sub: h.accountCreatedAt != null ? 'Created ${_formatDate(h.accountCreatedAt!)}' : null, width: cellWidth),
                  _HistoryStat(label: 'Total Orders', value: '${h.totalOrders}', sub: '${h.openOrders} still open', width: cellWidth),
                  _HistoryStat(label: 'Completed', value: '${h.completedOrders}', width: cellWidth),
                  _HistoryStat(label: 'Cancelled', value: '${h.cancelledOrders}', width: cellWidth),
                  _HistoryStat(label: 'Flagged Orders', value: flagged, width: cellWidth),
                  _HistoryStat(label: 'First Order', value: _formatDateOrDash(h.firstOrderAt), width: cellWidth),
                  _HistoryStat(label: 'Latest Order', value: _formatDateOrDash(h.lastOrderAt), width: cellWidth),
                  _HistoryStat(
                    label: 'Avg Completed Order',
                    value: avg != null ? _formatPeso(avg) : '—',
                    sub: 'Total spent ${_formatPeso(h.completedSpend)}',
                    width: cellWidth,
                  ),
                  _HistoryStat(
                    label: 'Latest Order Total',
                    value: h.latestOrderTotal != null ? _formatPeso(h.latestOrderTotal) : '—',
                    sub: latestSub,
                    width: cellWidth,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDecisionSection(AccountSummary? summary, Color textColor, Color subTextColor, Color borderColor, bool isDark) {
    final review = _reviewData?.review;
    final isBlocked = summary?.state == AccountState.blocked;

    final reasonOk = _reasonController.text.trim().length >= FraudReviewService.reasonMinChars;
    final ready = summary != null && _reviewData != null && !_decisionBusy;
    final hasEvidence = summary != null && (summary.activity.isNotEmpty || (_reviewData?.history.flaggedOrders ?? 0) > 0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (review != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Last review: ${kDecisionLabels[review.decision] ?? review.decision} by ${review.reviewedByRole}'
                    '${review.reviewedAt != null ? ' on ${_formatDate(review.reviewedAt!)}' : ''}\n"${review.reason}"',
                style: TextStyle(fontSize: 11, color: textColor, height: 1.4),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (isBlocked)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _kFraudRed.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: const Text(
                'This account is blacklisted. No further decisions can be made here.',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _kFraudRed),
              ),
            )
          else ...[
            Text(
              'Decide only after reading the transaction history and the order log above. Your reason is saved in the admin audit log.',
              style: TextStyle(fontSize: 11, color: subTextColor, height: 1.4),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reasonController,
              maxLines: 3,
              maxLength: FraudReviewService.reasonMaxChars,
              enabled: !_decisionBusy,
              style: TextStyle(fontSize: 13, color: textColor),
              decoration: InputDecoration(
                hintText: 'Explain your decision (at least ${FraudReviewService.reasonMinChars} characters)...',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey[500]),
                filled: true,
                fillColor: isDark ? const Color(0xFF222222) : const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kPink),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: (ready && reasonOk && hasEvidence) ? () => _submitDecision('confirmed_fraud') : null,
                  icon: const Icon(Icons.person_off, size: 14),
                  label: const Text('CONFIRM FRAUD', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.3)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kFraudRed,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: (ready && reasonOk) ? () => _submitDecision('false_alarm') : null,
                  icon: const Icon(Icons.check_circle_outline, size: 14),
                  label: const Text('MARK FALSE ALARM', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.3)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kClearGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ),
            if (summary != null && !hasEvidence) ...[
              const SizedBox(height: 6),
              Text('No recorded fraud activity to confirm.',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey[500], fontStyle: FontStyle.italic)),
            ],
          ],
          if (_decisionMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _decisionMessage!,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: _decisionMessageIsError ? _kFraudRed : _kClearGreen,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOrderLog(Color textColor, Color subTextColor, Color borderColor, bool isDark) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _ordersFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _emptyText('Could not load order log: ${snapshot.error}', subTextColor);
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: _kAccent)),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _emptyText('No web orders on file for this account yet.', subTextColor);
        }

        // Prefer the structured fraudActivities (new orders); fall back
        // to the plain fraudFlags text (older orders).
        final entries = docs.map((doc) {
          final data = doc.data();
          final source = data['fraudActivities'] is List ? data['fraudActivities'] as List : _asList(data['fraudFlags']);
          return _OrderEntry(doc.id, data, source.map(classifyFlag).toList(), _orderMillis(data));
        }).toList()
          ..sort((a, b) => b.millis.compareTo(a.millis));

        final visible = _flaggedOnly ? entries.where((e) => e.hasActivity).toList() : entries;

        if (visible.isEmpty) {
          return _emptyText("None of this account's orders have flagged activity.", subTextColor);
        }

        return Column(
          children: visible.map((e) => _buildOrderCard(e, textColor, subTextColor, borderColor, isDark)).toList(),
        );
      },
    );
  }

  Widget _buildOrderCard(_OrderEntry e, Color textColor, Color subTextColor, Color borderColor, bool isDark) {
    final o = e.data;
    final when = e.millis > 0 ? _formatDateTime(DateTime.fromMillisecondsSinceEpoch(e.millis)) : 'Date unavailable';
    final invoiceId = (o['invoiceId'] ?? e.id).toString();
    final payment = (o['payment_method'] ?? 'Unknown payment').toString().toUpperCase();
    final status = (o['status'] ?? 'unknown').toString().toUpperCase();

    // Per-order triage only exists on orders written after submit_order.php
    // started saving riskLevel/riskScore. Low-risk orders show no badge.
    final orderLevel = parseRiskLevel(o['riskLevel']);
    final showOrderTriage = orderLevel != null && orderLevel != RiskLevel.low;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: e.hasActivity ? _kAccent.withOpacity(isDark ? 0.08 : 0.05) : null,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: e.hasActivity ? _kAccent.withOpacity(0.6) : borderColor,
          width: e.hasActivity ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(invoiceId, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor)),
                    const SizedBox(height: 2),
                    Text(when, style: TextStyle(fontSize: 10, color: subTextColor)),
                    const SizedBox(height: 2),
                    Text('$payment  •  ${_formatPeso(o['total_price'])}',
                        style: TextStyle(fontSize: 11, color: subTextColor, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.grey.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: Text(status, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: textColor)),
              ),
            ],
          ),
          if (showOrderTriage) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _LevelBadge(level: orderLevel),
                _ScorePill(score: readScore(o)),
              ],
            ),
          ],
          const SizedBox(height: 6),
          if (e.flags.isEmpty)
            Text('No activity flagged on this order.', style: TextStyle(fontSize: 11, color: subTextColor, fontStyle: FontStyle.italic))
          else
            ...e.flags.map((f) => _FlagRow(flag: f, textColor: textColor)),
        ],
      ),
    );
  }
}