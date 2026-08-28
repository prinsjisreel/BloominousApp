import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FraudAnalyticsPage extends StatefulWidget {
  const FraudAnalyticsPage({super.key});

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

  /// Matches web's manualAdminOverrideToggle() exactly: real 30-day
  /// restrictedUntil timestamp, arrayUnion/arrayRemove on fraudFlags
  /// instead of overwriting the whole array, and writes ONLY to
  /// `customers` — the collection your actual fraud engine
  /// (submit_order.php, record_email_risk.php, restore_trust.php, the
  /// mobile checkout flow) reads and writes everywhere else. The old
  /// dual-write to `users` was pointless — nothing in the real pipeline
  /// ever reads fraud fields from there — and risked the two collections
  /// silently disagreeing with each other over time.
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

  /// Matches web's manualBanDevices() exactly: bans every REAL hash in
  /// this account's deviceHashes array — the same field
  /// DeviceSecurityService writes to on registration, and the same
  /// field submit_order.php/register.php actually check against. The
  /// old version invented a fake 'DEV_xxxxxx' ID that would never match
  /// a real device, meaning it likely banned nothing that actually
  /// existed.
  ///
  /// Note this is intentionally a DIFFERENT action from unbanning — this
  /// project has no single "toggle" for device bans since a customer can
  /// have MULTIPLE device hashes on file, potentially banned at
  /// different times for different reasons. This button always bans;
  /// lifting a specific device ban is a separate, deliberate admin
  /// action (see the banned_devices collection directly, same as web
  /// doesn't offer a one-click "unban all" either).
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
      // Reads directly from `customers` — the real collection your fraud
      // engine writes to everywhere else in this project. The old
      // `users` stream was showing stale/default values for every real
      // customer, since nothing in submit_order.php, register.php,
      // record_email_risk.php, or restore_trust.php ever writes fraud
      // fields to `users`.
      body: StreamBuilder<QuerySnapshot>(
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
            final status = data['status'] as String?;
            return status == 'blocked' || score >= 75;
          }).length;

          double trustRatio = totalAudited == 0
              ? 100.0
              : ((totalAudited - highRiskCount) / totalAudited) * 100.0;

          // Filter by search query
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
                // Top Header & Search Bar
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
                        // Search Bar (Full width on mobile)
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

                // Stat Summary Cards Row (Responsive Grid / Wrap)
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

                // Customer Accounts Cards List
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

                      String statusLabel = 'ACCOUNT SAFE';
                      Color statusColor = Colors.green;
                      if (isBlocked || score >= 100) {
                        statusLabel = 'PERMANENTLY TERMINATED';
                        statusColor = Colors.grey[850]!;
                        score = 100;
                      } else if (score >= 75) {
                        statusLabel = 'CRITICAL SCRUTINY';
                        statusColor = Colors.red;
                      } else if (score >= 50 || isRestricted) {
                        statusLabel = 'SUSPICIOUS PROFILE';
                        statusColor = Colors.amber[800]!;
                      }

                      // Real fraudFlags array, matching web exactly —
                      // the honest fallback for a genuinely clean profile
                      // says so plainly, rather than showing fabricated
                      // history that never happened.
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
                            // Row 1: Censored Name & Status Badge
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

                            // Row 2: Vector Rating & Score Indicator
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

                            // Row 3: UID Line + device count context
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

                            // Row 4: Action Buttons (Responsive Wrap)
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

                            // Row 5: Audit Trail Logging Flags Box (real data)
                            Container(
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
                                ],
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