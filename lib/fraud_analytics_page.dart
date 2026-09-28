import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_sidebar.dart';

class FraudAnalyticsPage extends StatefulWidget {
  final String role;
  const FraudAnalyticsPage({super.key, this.role = 'employee'});

  @override
  State<FraudAnalyticsPage> createState() => _FraudAnalyticsPageState();
}

class _FraudAnalyticsPageState extends State<FraudAnalyticsPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  String _censorName(String name) {
    if (name.trim().isEmpty) return 'P****e J*****l T*****n G****g';
    List<String> words = name.trim().split(RegExp(r'\s+'));
    List<String> censoredWords = [];
    for (String word in words) {
      if (word.isEmpty) continue;
      if (word.length <= 1) {
        censoredWords.add('*');
      } else if (word.length == 2) {
        censoredWords.add('${word[0]}*');
      } else {
        censoredWords
            .add(word[0] + '*' * (word.length - 2) + word[word.length - 1]);
      }
    }
    return censoredWords.join(' ');
  }

  // NEW: prefers the riskTier submit_order.php now writes (low/medium/
  // high/critical — the same tier model discussed for web). Falls back to
  // the original score-band guess ONLY for accounts that predate this
  // change and have no riskTier field yet, so old data still renders
  // sensibly instead of showing a blank badge.
  Map<String, dynamic> _classify(Map<String, dynamic> data, int score) {
    final status = data['status'] as String?;
    final riskTier = data['riskTier'] as String?;
    final bool isRestricted = data['isRestricted'] ?? false;

    if (status == 'blocked' || score >= 100) {
      return {'label': 'PERMANENTLY TERMINATED', 'color': Colors.grey[850]!, 'highRisk': true};
    }
    if (riskTier != null) {
      switch (riskTier) {
        case 'critical':
        case 'high':
          return {'label': 'CRITICAL SCRUTINY', 'color': Colors.red, 'highRisk': true};
        case 'medium':
          return {'label': 'SUSPICIOUS PROFILE', 'color': Colors.amber[800]!, 'highRisk': false};
        default:
          return {'label': 'ACCOUNT SAFE', 'color': Colors.green, 'highRisk': false};
      }
    }
    if (score >= 75) {
      return {'label': 'CRITICAL SCRUTINY', 'color': Colors.red, 'highRisk': true};
    }
    if (score >= 50 || isRestricted) {
      return {'label': 'SUSPICIOUS PROFILE', 'color': Colors.amber[800]!, 'highRisk': false};
    }
    return {'label': 'ACCOUNT SAFE', 'color': Colors.green, 'highRisk': false};
  }

  Future<void> _manualRestrict(
      String userId, Map<String, dynamic> userData) async {
    final bool currentRestricted = userData['isRestricted'] ?? false;
    final bool newRestricted = !currentRestricted;

    final confirmed = await _showConfirmDialog(
      title: newRestricted
          ? 'Apply Manual Override Restriction?'
          : 'Lift Manual Override Penalty?',
      message: newRestricted
          ? 'This will restrict the account for 30 days and disable Cash on Delivery.'
          : 'This will lift the restriction and restore full account trust.',
      confirmColor: newRestricted ? Colors.red : Colors.green,
    );
    if (!confirmed) return;

    try {
      final expiryDate = DateTime.now().add(const Duration(days: 30));
      const flagText = 'Restricted by admin manual override parameters';

      await _db.collection('customers').doc(userId).update({
        'isRestricted': newRestricted,
        'restrictedUntil':
        newRestricted ? Timestamp.fromDate(expiryDate) : null,
        'fraudFlags': newRestricted
            ? FieldValue.arrayUnion([flagText])
            : FieldValue.arrayRemove([flagText]),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newRestricted
                  ? 'Account restricted for 30 days. COD payment method is now disabled for this user.'
                  : 'Account restriction lifted. Trust restored.',
            ),
            backgroundColor: newRestricted ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating restriction: $e')));
      }
    }
  }

  Future<void> _banDevices(
      String userId, Map<String, dynamic> userData) async {
    final rawHashes = userData['deviceHashes'];
    final List<String> deviceHashes = rawHashes is List
        ? rawHashes.map((e) => e.toString()).toList()
        : <String>[];

    if (deviceHashes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No device history on file for this account yet.')),
        );
      }
      return;
    }

    final confirmed = await _showConfirmDialog(
      title: 'Ban ${deviceHashes.length} Device(s)?',
      message:
      'This blocks every device linked to this account from registering new accounts or placing orders. This action cannot be undone from this screen.',
      confirmColor: Colors.red,
    );
    if (!confirmed) return;

    try {
      final batch = _db.batch();
      for (final hash in deviceHashes) {
        final ref = _db.collection('banned_devices').doc(hash);
        batch.set(ref, {
          'bannedUid': userId,
          'reason': 'Manually banned by admin from Fraud Risk Analytics',
          'bannedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
            Text('${deviceHashes.length} device(s) banned successfully.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error banning device(s): $e')));
      }
    }
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    required Color confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor),
            child: const Text('CONFIRM', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // NEW: opens the per-customer fraud history as a bottom sheet — the
  // mobile-idiomatic equivalent of the web dashboard's centered modal.
  // maskedName is passed in (never the real name) so this detail view
  // can never leak an identity the list view chose not to show.
  void _openFraudHistory(String uid, String maskedName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FraudHistorySheet(uid: uid, maskedName: maskedName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width >= 850;

    return Scaffold(
      backgroundColor:
      isDark ? const Color(0xFF121212) : const Color(0xFFFFFDF9),
      appBar: AppBar(
        title: Text(
          'Fraud Risk Analytics',
          style: GoogleFonts.cormorantGaramond(
              fontWeight: FontWeight.bold, fontSize: 24),
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
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db.collection('customers').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                      child: Text('Error loading threat feeds: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: Color(0xFFF59E0B)));
                }

                final customers = snapshot.data?.docs ?? [];

                int totalAudited = customers.length;
                int highRiskCount = customers.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final score = (data['fraudScore'] ?? 0) as int;
                  return (_classify(data, score)['highRisk'] as bool);
                }).length;

                double trustRatio = totalAudited == 0
                    ? 100.0
                    : ((totalAudited - highRiskCount) / totalAudited) * 100.0;

                final filteredCustomers = customers.where((d) {
                  if (_searchQuery.trim().isEmpty) return true;
                  final data = d.data() as Map<String, dynamic>;
                  final uid = d.id.toLowerCase();
                  final email = (data['email'] ?? '').toString().toLowerCase();
                  final name = (data['name'] ?? data['fullName'] ?? '')
                      .toString()
                      .toLowerCase();
                  final q = _searchQuery.toLowerCase();
                  return uid.contains(q) || email.contains(q) || name.contains(q);
                }).toList();

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isMobile = constraints.maxWidth < 600;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Fraud Risk Analytics',
                                style: GoogleFonts.cormorantGaramond(
                                  fontSize: isMobile ? 24 : 28,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Real-time user account security matrix, customer action logging checks, and profile telemetry.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: isMobile ? double.infinity : 320,
                                height: 42,
                                child: TextField(
                                  controller: _searchController,
                                  onChanged: (val) =>
                                      setState(() => _searchQuery = val),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Search Account Name or UID...',
                                    hintStyle: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[400],
                                    ),
                                    prefixIcon: const Icon(Icons.search,
                                        size: 18, color: Colors.grey),
                                    suffixIcon: _searchQuery.isNotEmpty
                                        ? IconButton(
                                      icon: const Icon(Icons.clear, size: 16),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                    )
                                        : null,
                                    contentPadding: const EdgeInsets.symmetric(
                                        vertical: 0, horizontal: 14),
                                    filled: true,
                                    fillColor:
                                    isDark ? Colors.grey[900] : Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      borderSide: BorderSide(
                                          color: Colors.grey.withOpacity(0.2)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      borderSide: BorderSide(
                                          color: Colors.grey.withOpacity(0.2)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFF59E0B), width: 1.5),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      LayoutBuilder(
                        builder: (context, constraints) {
                          final cardWidth = constraints.maxWidth < 600
                              ? (constraints.maxWidth - 12) / 2
                              : (constraints.maxWidth - 32) / 3;

                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _buildStatBox(
                                  'TOTAL ACCOUNTS', '$totalAudited', null, isDark,
                                  width: cardWidth),
                              _buildStatBox('HIGH RISK FLAGGED', '$highRiskCount',
                                  Icons.warning_amber_rounded, isDark,
                                  width: cardWidth),
                              _buildStatBox('GLOBAL TRUST',
                                  '${trustRatio.toStringAsFixed(0)}%', null, isDark,
                                  width: cardWidth, valueColor: Colors.green[600]),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 24),

                      if (filteredCustomers.isEmpty)
                        Container(
                          height: 160,
                          width: double.infinity,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[900] : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.withOpacity(0.15)),
                          ),
                          child: Text(
                            'No audited customer accounts found.',
                            style: TextStyle(color: Colors.grey[400], fontSize: 13),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filteredCustomers.length,
                          itemBuilder: (context, index) {
                            final doc = filteredCustomers[index];
                            final data = doc.data() as Map<String, dynamic>;
                            final userId = doc.id;

                            final email = data['email'] ?? '';
                            final rawName = data['name'] ??
                                data['fullName'] ??
                                (email.toString().contains('@')
                                    ? email.toString().split('@')[0]
                                    : 'Customer');
                            final censoredName = _censorName(rawName);

                            final String? statusField = data['status'] as String?;
                            final bool isBlocked = statusField == 'blocked';
                            final bool isRestricted = data['isRestricted'] ?? false;
                            int score = (data['fraudScore'] ?? 10) as int;

                            final classification = _classify(data, score);
                            final String statusLabel = classification['label'] as String;
                            final Color statusColor = classification['color'] as Color;
                            if (isBlocked || score >= 100) score = 100;

                            final rawFlags = data['fraudFlags'];
                            final List<String> fraudFlags = rawFlags is List
                                ? rawFlags.map((e) => e.toString()).toList()
                                : <String>[];
                            final flagsDisplay = fraudFlags.isNotEmpty
                                ? fraudFlags.join(', ')
                                : 'Profile registers secure telemetry baselines.';

                            final rawHashes = data['deviceHashes'];
                            final deviceCount =
                            rawHashes is List ? rawHashes.length : 0;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.grey[900] : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isBlocked
                                      ? Colors.red.withOpacity(0.4)
                                      : Colors.grey.withOpacity(0.15),
                                  width: isBlocked ? 1.5 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.02),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          censoredName,
                                          style: GoogleFonts.cormorantGaramond(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: statusColor.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                              color: statusColor.withOpacity(0.3)),
                                        ),
                                        child: Text(
                                          statusLabel,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                            color: statusColor,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color:
                                      isDark ? Colors.grey[850] : Colors.grey[50],
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          'Vector Rating: ',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                        Expanded(
                                          child: SizedBox(
                                            height: 6,
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(3),
                                              child: LinearProgressIndicator(
                                                value: score / 100.0,
                                                backgroundColor: Colors.grey[300],
                                                valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    statusColor),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '$score%',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: statusColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  Row(
                                    children: [
                                      Expanded(
                                        child: SelectableText(
                                          'UID: ${userId.toUpperCase()}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey[500],
                                            fontFamily: 'monospace',
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '$deviceCount device${deviceCount == 1 ? '' : 's'} on file',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey[500],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  if (!isBlocked)
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        ElevatedButton.icon(
                                          onPressed: () =>
                                              _manualRestrict(userId, data),
                                          icon: Icon(
                                            isRestricted
                                                ? Icons.lock_open
                                                : Icons.block,
                                            size: 13,
                                          ),
                                          label: Text(
                                            isRestricted
                                                ? 'LIFT RESTRICTION'
                                                : 'MANUAL RESTRICT',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: isRestricted
                                                ? Colors.orange[800]
                                                : const Color(0xFFDC2626),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                BorderRadius.circular(12)),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                            elevation: 0,
                                            minimumSize: const Size(0, 34),
                                          ),
                                        ),
                                        ElevatedButton.icon(
                                          onPressed: () =>
                                              _banDevices(userId, data),
                                          icon: const Icon(Icons.phonelink_erase,
                                              size: 13),
                                          label: const Text(
                                            'BAN DEVICE(S)',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF0F172A),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                BorderRadius.circular(12)),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                            elevation: 0,
                                            minimumSize: const Size(0, 34),
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'BLACKLISTED',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 12),

                                  // NEW: this block is now an InkWell —
                                  // tapping it opens the same customer's
                                  // full order-by-order fraud history,
                                  // mirroring the web dashboard's
                                  // click-through Audit Trail block.
                                  InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _openFraudHistory(userId, censoredName),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.black26
                                            : const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: Colors.grey.withOpacity(0.1)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'AUDIT TRAIL LOGGING FLAGS',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.grey[500],
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            flagsDisplay,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark
                                                  ? Colors.grey[300]
                                                  : Colors.grey[700],
                                              fontWeight: FontWeight.w500,
                                              height: 1.4,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Icon(Icons.history, size: 12, color: const Color(0xFFF59E0B)),
                                              const SizedBox(width: 4),
                                              Text(
                                                'View full fraud history',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                  color: const Color(0xFFF59E0B),
                                                  letterSpacing: 0.2,
                                                ),
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
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox(String label, String value, IconData? icon, bool isDark,
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
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.grey[400],
              letterSpacing: 0.3,
            ),
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
                    color:
                    valueColor ?? (isDark ? Colors.white : Colors.black87),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (icon != null)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.redAccent, size: 16),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// NEW: the mobile equivalent of fraud_analytics.php's fraud-history
// modal. A separate widget (rather than an inline method) since it owns
// its own async fetch/sort and its own scroll behavior via
// DraggableScrollableSheet.
class _FraudHistorySheet extends StatelessWidget {
  final String uid;
  final String maskedName;
  const _FraudHistorySheet({required this.uid, required this.maskedName});

  Color _tierColor(String? tier) {
    switch (tier) {
      case 'critical':
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.amber[800]!;
      default:
        return Colors.green[700]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sheetColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final borderColor = isDark ? const Color(0xFF2A2A2A) : Colors.grey.withOpacity(0.15);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Fraud History — $maskedName',
                        style: GoogleFonts.cormorantGaramond(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(icon: Icon(Icons.close, color: subTextColor), onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('UID: $uid', style: TextStyle(fontSize: 10, color: subTextColor, fontFamily: 'monospace')),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<QuerySnapshot>(
                  // NOTE: no .orderBy() here on purpose. An equality
                  // filter on user_id plus a sort on a DIFFERENT field
                  // (createdAt) needs a manually-created Firestore
                  // composite index — the exact same wall the web
                  // dashboard hit. Fetching the (small, per-customer)
                  // result set and sorting it client-side avoids needing
                  // that index at all, on either platform.
                  future: FirebaseFirestore.instance
                      .collection('orders')
                      .where('user_id', isEqualTo: uid)
                      .limit(50)
                      .get(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Could not load history: ${snapshot.error}',
                              style: TextStyle(color: subTextColor, fontStyle: FontStyle.italic)),
                        ),
                      );
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)));
                    }
                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Text('No web orders on file for this account yet.',
                            style: TextStyle(color: subTextColor, fontStyle: FontStyle.italic)),
                      );
                    }

                    final orders = docs.map((d) => d.data() as Map<String, dynamic>).toList();
                    orders.sort((a, b) {
                      final aTs = a['createdAt'];
                      final bTs = b['createdAt'];
                      final aMs = aTs is Timestamp ? aTs.millisecondsSinceEpoch : 0;
                      final bMs = bTs is Timestamp ? bTs.millisecondsSinceEpoch : 0;
                      return bMs - aMs;
                    });

                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      itemCount: orders.length,
                      itemBuilder: (context, i) {
                        final o = orders[i];
                        final ts = o['createdAt'];
                        String when = '...';
                        if (ts is Timestamp) {
                          final d = ts.toDate();
                          when = '${d.month}/${d.day}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
                        }
                        final tier = o['riskTier'] as String?;
                        final score = o['fraudScore'];
                        final rawFlags = o['fraudFlags'];
                        final flags = rawFlags is List ? rawFlags.map((e) => e.toString()).toList() : <String>[];
                        final invoiceId = o['invoiceId']?.toString() ?? '(no invoice)';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(invoiceId,
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _tierColor(tier).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${tier ?? 'n/a'} • score ${score ?? 'n/a'}',
                                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: _tierColor(tier)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(when, style: TextStyle(fontSize: 10, color: subTextColor)),
                              const SizedBox(height: 8),
                              if (flags.isEmpty)
                                Text('No flags raised on this order.',
                                    style: TextStyle(fontSize: 11, color: subTextColor, fontStyle: FontStyle.italic))
                              else
                                ...flags.map((f) => Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Text('•  $f', style: TextStyle(fontSize: 11, color: textColor)),
                                )),
                            ],
                          ),
                        );
                      },
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
}