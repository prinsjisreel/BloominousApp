import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'inventory_data.dart';
import 'my_orders_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CustomerProfilePage extends StatefulWidget {
  final String email;
  final String customerId;

  const CustomerProfilePage({
    super.key,
    required this.email,
    required this.customerId,
  });

  @override
  State<CustomerProfilePage> createState() => _CustomerProfilePageState();
}

class _CustomerProfilePageState extends State<CustomerProfilePage> {
  bool _isRecovering = false;

  @override
  void initState() {
    super.initState();
    _checkAndRecoverPoints();
  }

  Future<void> _checkAndRecoverPoints() async {
    final firestore = FirebaseFirestore.instance;
    if (mounted) setState(() => _isRecovering = true);

    try {
      // 1. Check if the current doc exists in customers
      final doc =
          await firestore.collection('customers').doc(widget.customerId).get();
      bool foundSomething = false;
      int recoveredPoints = 0;

      // 2. Search for old records by email (both exact and lowercase variants)
      final emailLower = widget.email.toLowerCase();
      final emailOriginal = widget.email.trim();
      final List<String> searchEmails = {emailLower, emailOriginal}.toList();

      for (final email in searchEmails) {
        // Check customers collection
        final customerQuery = await firestore
            .collection('customers')
            .where('email', isEqualTo: email)
            .get();

        for (var oldDoc in customerQuery.docs) {
          if (oldDoc.id != widget.customerId) {
            final data = oldDoc.data();
            recoveredPoints += (data['points'] as num? ?? 0).toInt();
            foundSomething = true;
            await firestore.collection('customers').doc(oldDoc.id).delete();
          }
        }

        // Check legacy loyalty_points collection
        final loyaltyQuery = await firestore
            .collection('loyalty_points')
            .where('email', isEqualTo: email)
            .get();

        for (var oldDoc in loyaltyQuery.docs) {
          if (oldDoc.id != widget.customerId) {
            final data = oldDoc.data();
            recoveredPoints += (data['points'] as num? ?? 0).toInt();
            foundSomething = true;
            await firestore
                .collection('loyalty_points')
                .doc(oldDoc.id)
                .delete();
          }
        }
      }

      // 3. Update or Create current document
      if (doc.exists) {
        if (foundSomething && recoveredPoints > 0) {
          await firestore
              .collection('customers')
              .doc(widget.customerId)
              .update({
            'points': FieldValue.increment(recoveredPoints),
            'lastRecovery': FieldValue.serverTimestamp(),
          });
        }
      } else {
        // Create new doc if it didn't exist
        await firestore.collection('customers').doc(widget.customerId).set({
          'name': 'Floral Enthusiast',
          'email': widget.email,
          'points': recoveredPoints,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
          'lastRecovery': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        foundSomething =
            true; // Mark as found because we created a new doc to fix the error UI
      }

      if (mounted) {
        String msg = foundSomething
            ? (recoveredPoints > 0
                ? 'Success! $recoveredPoints points synchronized.'
                : 'Account synchronized successfully.')
            : 'Your account is already up to date.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: foundSomething ? Colors.green : Colors.black87,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Recovery error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recovery failed: $e'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRecovering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: InventoryData.getCustomerLoyaltyDocStream(widget.customerId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting ||
              _isRecovering) {
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFFF4B400)));
          }

          final data = snapshot.data;
          final bool isRegistered = data != null;
          final firstName = data?['firstName'] ?? '';
          final lastName = data?['lastName'] ?? '';
          final middleName = data?['middleName'] ?? '';
          final name = (firstName.isNotEmpty || lastName.isNotEmpty)
              ? "$firstName $middleName $lastName".trim()
              : (data?['name'] ?? 'Floral Enthusiast');
          final points = data?['points'] ?? 0;
          final phone = data?['phone'] ?? 'Update phone number';
          final membership = _getMembershipTier(points);

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Modern Header with "Hello"
              SliverAppBar(
                expandedHeight: 140.0,
                floating: false,
                pinned: true,
                elevation: 0,
                backgroundColor: isDark ? Colors.black : Colors.white,
                leading: IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded,
                      color: isDark ? Colors.white : Colors.black, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(
                    icon: Icon(Icons.settings_outlined,
                        color: isDark ? Colors.white : Colors.black, size: 24),
                    onPressed: () {
                      // Settings action
                    },
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  expandedTitleScale: 1.2,
                  centerTitle: false,
                  titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
                  title: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hello,',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        name,
                        style: GoogleFonts.cormorantGaramond(
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                          color: isDark ? Colors.white : Colors.black,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      if (!isRegistered) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.redAccent.withOpacity(0.3)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.error_outline,
                                      color: Colors.redAccent),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Account sync error. Your points may not display correctly.',
                                      style: const TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _checkAndRecoverPoints,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                ),
                                child: const Text('RECOVER MY POINTS'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // Premium Membership Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: membership['colors'],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: (membership['colors'][0] as Color)
                                  .withOpacity(0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Icon(Icons.local_florist,
                                    color: Colors.white, size: 32),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    membership['name'].toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),
                            const Text(
                              'BLOOM POINTS',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  isRegistered ? '$points' : '---',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 52,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -1,
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.qr_code_2_rounded,
                                          color: Colors.white, size: 32),
                                      onPressed: () =>
                                          _showMyQR(context, widget.customerId),
                                      tooltip: 'Show Membership QR',
                                    ),
                                    const Text('MY QR',
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900)),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Text(
                              name.toUpperCase(),
                              style: GoogleFonts.cormorantGaramond(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              widget.email.toLowerCase(),
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontFamily: 'Inter'),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Details Section
                      _buildOptionTile(
                        context,
                        icon: Icons.phone_outlined,
                        label: 'Phone Number',
                        value: phone,
                        onTap: () => _showUpdatePhoneDialog(context, phone),
                      ),
                      const SizedBox(height: 16),
                      _buildOptionTile(context,
                          icon: Icons.shopping_bag_outlined,
                          label: 'Order History',
                          value: 'View your previous bouquets', onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MyOrdersPage(
                                userId: widget.customerId, email: widget.email),
                          ),
                        );
                      }),
                      const SizedBox(height: 16),
                      _buildOptionTile(
                        context,
                        icon: Icons.card_giftcard_rounded,
                        label: 'Rewards Catalog',
                        value: 'Redeem your points here',
                        onTap: () => _showRewardsCatalog(context, points),
                      ),

                      const SizedBox(height: 48),

                      // Sign Out
                      TextButton.icon(
                        onPressed: () async {
                          await FirebaseAuth.instance.signOut();
                          if (context.mounted) {
                            Navigator.of(context)
                                .popUntil((route) => route.isFirst);
                          }
                        },
                        icon: const Icon(Icons.logout_rounded,
                            color: Colors.redAccent, size: 18),
                        label: const Text(
                          'SIGN OUT OF PROFILE',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOptionTile(BuildContext context,
      {required IconData icon,
      required String label,
      required String value,
      required VoidCallback onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.black.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF4B400).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFFF4B400), size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 9,
                        color: Colors.grey,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }

  void _showMyQR(BuildContext context, String uid) {
    final String qrData = "BLOOM-CUST-$uid";
    final String qrUrl =
        "https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=$qrData";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        title: const Text('MY MEMBERSHIP QR',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Present this to the florist to earn Bloom Points',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey, fontFamily: 'Inter')),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.withOpacity(0.1)),
              ),
              child: Image.network(
                qrUrl,
                width: 200,
                height: 200,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const CircularProgressIndicator(color: Color(0xFFF4B400)),
              ),
            ),
            const SizedBox(height: 16),
            Text(uid,
                style: const TextStyle(
                    fontSize: 8, color: Colors.grey, fontFamily: 'monospace')),
          ],
        ),
        actions: [
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CLOSE',
                  style: TextStyle(
                      color: Color(0xFF121212), fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getMembershipTier(int points) {
    if (points >= 5000) {
      return {
        'name': 'Platinum Member',
        'colors': [const Color(0xFFE5E4E2), const Color(0xFFB4B4B4)],
      };
    } else if (points >= 2000) {
      return {
        'name': 'Diamond Member',
        'colors': [const Color(0xFFB9F2FF), const Color(0xFF00B4D8)],
      };
    } else if (points >= 1000) {
      return {
        'name': 'Gold Member',
        'colors': [const Color(0xFFD4AF37), const Color(0xFF996515)],
      };
    } else if (points >= 500) {
      return {
        'name': 'Silver Member',
        'colors': [const Color(0xFFC0C0C0), const Color(0xFF808080)],
      };
    } else {
      return {
        'name': 'Bronze Member',
        'colors': [const Color(0xFFCD7F32), const Color(0xFF8B4513)],
      };
    }
  }

  void _showUpdatePhoneDialog(BuildContext context, String currentPhone) {
    final controller = TextEditingController(
        text: currentPhone == 'Update phone number' ? '' : currentPhone);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Update Phone Number'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              hintText: 'e.g., +639123456789',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newPhone = controller.text.trim();
                if (newPhone.isNotEmpty) {
                  await FirebaseFirestore.instance
                      .collection('customers')
                      .doc(widget.customerId)
                      .set({'phone': newPhone}, SetOptions(merge: true));
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Phone number updated successfully!')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B)),
              child: const Text('SAVE', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showRewardsCatalog(BuildContext context, int currentPoints) {
    final rewards = [
      {
        'name': '₱100 Store Discount Voucher',
        'points': 100,
        'desc': 'Get ₱100 off any florist bouquet purchase',
        'icon': Icons.confirmation_number_outlined
      },
      {
        'name': '₱250 Mega Discount Voucher',
        'points': 220,
        'desc': 'Get ₱250 off any florist bouquet purchase',
        'icon': Icons.local_activity_outlined
      },
      {
        'name': 'Premium Custom Wrapper Upgrade',
        'points': 150,
        'desc': 'Free premium Korean styled flower wrapping',
        'icon': Icons.layers_outlined
      },
      {
        'name': 'Free Red Rose Stem Add-on',
        'points': 200,
        'desc': 'Add one extra fresh red rose stem to your next bouquet',
        'icon': Icons.local_florist_outlined
      },
      {
        'name': 'Free Fluffy Teddy Bear Plushie',
        'points': 300,
        'desc': 'An adorable 6-inch plushie companion for your arrangement',
        'icon': Icons.toys_outlined
      },
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'REWARDS CATALOG',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                          color: const Color(0xFFF59E0B),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$currentPoints Points',
                          style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Redeem your accumulated Bloom Points for premium vouchers and flower bouquet add-ons.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: rewards.length,
                      itemBuilder: (context, index) {
                        final reward = rewards[index];
                        final cost = reward['points'] as int;
                        final name = reward['name'] as String;
                        final desc = reward['desc'] as String;
                        final icon = reward['icon'] as IconData;
                        final canRedeem = currentPoints >= cost;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: isDark
                                  ? Colors.grey[800]!
                                  : Colors.grey[200]!,
                              width: 1,
                            ),
                          ),
                          color: isDark
                              ? const Color(0xFF2A2A2A)
                              : Colors.grey[50]!,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: canRedeem
                                        ? const Color(0xFFF59E0B)
                                            .withOpacity(0.1)
                                        : Colors.grey.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(icon,
                                      color: canRedeem
                                          ? const Color(0xFFF59E0B)
                                          : Colors.grey,
                                      size: 24),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        desc,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600]),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '$cost Points Required',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: canRedeem
                                              ? const Color(0xFF7B79F2)
                                              : Colors.grey,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton(
                                  onPressed: !canRedeem
                                      ? null
                                      : () async {
                                          // Perform Points Deduction in Firestore
                                          await FirebaseFirestore.instance
                                              .collection('customers')
                                              .doc(widget.customerId)
                                              .update({
                                            'points':
                                                FieldValue.increment(-cost)
                                          });

                                          // Create redemption record
                                          final code =
                                              'BLOOM-${name.split(" ").last.toUpperCase()}-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
                                          await FirebaseFirestore.instance
                                              .collection('redemptions')
                                              .add({
                                            'customerId': widget.customerId,
                                            'rewardName': name,
                                            'costPoints': cost,
                                            'redeemedAt':
                                                FieldValue.serverTimestamp(),
                                            'code': code,
                                            'status': 'active',
                                          });

                                          if (context.mounted) {
                                            Navigator.pop(context);
                                            // Show success dialog
                                            _showRedemptionSuccessDialog(
                                                context, name, code);
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF59E0B),
                                    disabledBackgroundColor: Colors.grey[300],
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    elevation: 0,
                                  ),
                                  child: Text(
                                    'REDEEM',
                                    style: TextStyle(
                                      color: canRedeem
                                          ? Colors.white
                                          : Colors.grey[600],
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showRedemptionSuccessDialog(
      BuildContext context, String rewardName, String couponCode) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green, size: 28),
              SizedBox(width: 10),
              Text('Redemption Successful!'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'You have successfully redeemed:',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                rewardName,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  children: [
                    const Text(
                      'YOUR REWARD COUPON CODE',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      couponCode,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF7B79F2),
                          letterSpacing: 1.2,
                          fontFamily: 'JetBrains Mono'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Present this code at the florist counter to claim your reward.',
                style: TextStyle(color: Colors.grey, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('DONE', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}
