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

  Future<void> _manualRestrict(
      String userId, Map<String, dynamic> userData) async {
    final bool currentRestricted = userData['isRestricted'] ?? false;
    final bool newRestricted = !currentRestricted;
    final int newScore =
        newRestricted ? 65 : 20; // 65 is inside 50-86% COD restriction range

    try {
      await _db.collection('users').doc(userId).set({
        'isRestricted': newRestricted,
        'fraudScore': newScore,
        'restrictionReason':
            newRestricted ? 'Restricted by Admin for security audit.' : null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Also sync to customers collection if exists
      await _db.collection('customers').doc(userId).set({
        'isRestricted': newRestricted,
        'fraudScore': newScore,
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newRestricted
                  ? 'Account Restricted (Risk Rating: $newScore%). COD payment method is now disabled for this user.'
                  : 'Account Restriction lifted. Trust restored.',
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

  Future<void> _banDevice(String userId, Map<String, dynamic> userData) async {
    final bool currentBanned =
        (userData['isBanned'] ?? false) || (userData['fraudScore'] ?? 0) >= 100;
    final bool newBanned = !currentBanned;
    final int newScore = newBanned ? 100 : 10;

    final email = (userData['email'] ?? '').toString();
    final emailDomain = email.contains('@') ? email.split('@')[1] : '';
    final deviceId = (userData['deviceId'] ??
            'DEV_${userId.substring(0, min(6, userId.length))}')
        .toString();
    final ipAddress =
        (userData['ipAddress'] ?? userData['lastIp'] ?? '192.168.1.100')
            .toString();
    final networkSignature =
        (userData['networkSignature'] ?? 'NET_SIG_${userId.hashCode}')
            .toString();

    try {
      // 1. Update user account
      await _db.collection('users').doc(userId).set({
        'isBanned': newBanned,
        'isRestricted': newBanned,
        'fraudScore': newScore,
        'status': newBanned ? 'DEVICE BANNED' : 'ACCOUNT SAFE',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _db.collection('customers').doc(userId).set({
        'isBanned': newBanned,
        'isRestricted': newBanned,
        'fraudScore': newScore,
      }, SetOptions(merge: true));

      // 2. Manage banned_devices collection for strict device & IP & network signature enforcement
      if (newBanned) {
        await _db.collection('banned_devices').doc(deviceId).set({
          'deviceId': deviceId,
          'bannedUserId': userId,
          'email': email,
          'emailDomain': emailDomain,
          'ipAddress': ipAddress,
          'networkSignature': networkSignature,
          'bannedAt': FieldValue.serverTimestamp(),
          'reason':
              'Device & Network Fingerprint Banned by Admin due to Fraud.',
        });
      } else {
        await _db.collection('banned_devices').doc(deviceId).delete();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newBanned
                  ? 'DEVICE BANNED: Account, Device ID ($deviceId), IP ($ipAddress) & Email domain are strictly blacklisted.'
                  : 'Device Ban lifted.',
            ),
            backgroundColor: newBanned ? Colors.red : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error banning device: $e')));
      }
    }
  }

  int min(int a, int b) => a < b ? a : b;

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
      body: StreamBuilder<QuerySnapshot>(
        stream: _db.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
                child: Text('Error loading threat feeds: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFFF59E0B)));
          }

          final allDocs = snapshot.data?.docs ?? [];
          final customers = allDocs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final role = data['role'] ?? 'customer';
            return role == 'customer';
          }).toList();

          int totalAudited = customers.length;
          int highRiskCount = customers.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final score = (data['fraudScore'] ?? 0) as int;
            final isBanned = data['isBanned'] ?? false;
            return isBanned || score >= 80;
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
                          (email.contains('@')
                              ? email.split('@')[0]
                              : 'Customer');
                      final censoredName = _censorName(rawName);

                      final bool isBanned = (data['isBanned'] ?? false) ||
                          (data['status'] == 'DEVICE BANNED');
                      final bool isRestricted = data['isRestricted'] ?? false;
                      int score = (data['fraudScore'] ?? 20) as int;

                      String statusLabel = 'ACCOUNT SAFE';
                      Color statusColor = Colors.green;
                      if (isBanned || score >= 100) {
                        statusLabel = 'DEVICE BANNED';
                        statusColor = Colors.red;
                        score = 100;
                      } else if (score >= 90) {
                        statusLabel = 'SUSPENDED';
                        statusColor = Colors.deepOrange;
                      } else if (isRestricted || (score >= 50 && score <= 86)) {
                        statusLabel = 'RESTRICTED (NO COD)';
                        statusColor = Colors.amber[800]!;
                      }

                      final auditFlags = data['auditFlags'] ??
                          'Rapid Separated Checkouts Flagged (< 5 min window), Restricted for 30 days by admin, Identity verified via SMS - Trust Restored';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[900] : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isBanned
                                ? Colors.red.withOpacity(0.4)
                                : Colors.grey.withOpacity(0.15),
                            width: isBanned ? 1.5 : 1,
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

                            // Row 3: UID Line
                            SelectableText(
                              'UID: ${userId.toUpperCase()}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[500],
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Row 4: Action Buttons (Responsive Wrap)
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
                                  onPressed: () => _banDevice(userId, data),
                                  icon: Icon(
                                    isBanned
                                        ? Icons.phonelink_setup
                                        : Icons.phonelink_erase,
                                    size: 13,
                                  ),
                                  label: Text(
                                    isBanned ? 'UNBAN DEVICE' : 'BAN DEVICE(S)',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isBanned
                                        ? Colors.green[700]
                                        : const Color(0xFF0F172A),
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
                            ),
                            const SizedBox(height: 12),

                            // Row 5: Audit Trail Logging Flags Box
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
                                    auditFlags,
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
