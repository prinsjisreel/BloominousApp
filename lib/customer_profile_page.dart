import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'inventory_data.dart';
import 'order_tracking_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// One redeemable reward, built from a document in the `promos` collection.
/// Note: it deliberately has NO promo_code field, so the code cannot be
/// shown to customers by accident.
class _CatalogReward {
  final String id; // the promo document id
  final String name;
  final String desc;
  final int cost;
  final int discount;

  const _CatalogReward({
    required this.id,
    required this.name,
    required this.desc,
    required this.cost,
    required this.discount,
  });
}

/// "20% Off Voucher": the one place this title is built, so the catalog
/// card and the saved redemption always use identical wording.
String _rewardTitle(int discount) => '$discount% Off Voucher';

/// True when a promo's expiry_date ("yyyy-MM-dd" from the web form) is in the
/// past. The promo stays valid through the END of its expiry day.
/// A missing or unreadable date is treated as "not expired".
bool _isPromoExpired(dynamic rawExpiry) {
  if (rawExpiry is! String) return false;
  final parsed = DateTime.tryParse(rawExpiry);
  if (parsed == null) return false;
  final endOfDay = DateTime(parsed.year, parsed.month, parsed.day, 23, 59, 59);
  return DateTime.now().isAfter(endOfDay);
}

/// Random coupon code like BLOOM-K7QM-X2PD. Skips look-alike characters
/// (0/O, 1/I) so staff can read it aloud without mistakes.
String _generateRedemptionCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  final part =
  List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
  return 'BLOOM-${part.substring(0, 4)}-${part.substring(4)}';
}

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
      final doc =
      await firestore.collection('customers').doc(widget.customerId).get();
      bool foundSomething = false;
      int recoveredPoints = 0;

      final emailLower = widget.email.toLowerCase();
      final emailOriginal = widget.email.trim();
      final List<String> searchEmails = {emailLower, emailOriginal}.toList();

      for (final email in searchEmails) {
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
        await firestore.collection('customers').doc(widget.customerId).set({
          'name': 'Floral Enthusiast',
          'email': widget.email,
          'points': recoveredPoints,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
          'lastRecovery': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        foundSomething = true;
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
          // Always a whole number, even if Firestore stored 100.0
          final int points = (data?['points'] as num? ?? 0).toInt();
          final phone = data?['phone'] ?? 'Update phone number';
          final membership = _getMembershipTier(points);

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
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
                    onPressed: () {},
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

                      _buildOrderTrackingRow(context, widget.customerId),

                      const SizedBox(height: 32),

                      _buildOptionTile(
                        context,
                        icon: Icons.phone_outlined,
                        label: 'Phone Number',
                        value: phone,
                        onTap: () => _showUpdatePhoneDialog(context, phone),
                      ),
                      const SizedBox(height: 16),
                      // "Order History" tile removed: the MY ORDERS card above
                      // (To Pay / To Ship / To Deliver / To Rate) already
                      // covers it.
                      _buildOptionTile(
                        context,
                        icon: Icons.card_giftcard_rounded,
                        label: 'Rewards Catalog',
                        value: 'Redeem your points here',
                        onTap: () => _showRewardsCatalog(context, points),
                      ),

                      const SizedBox(height: 48),

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

  Widget _buildOrderTrackingRow(BuildContext context, String customerId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('user_id', isEqualTo: customerId)
          .snapshots(),
      builder: (context, snapshot) {
        int toPay = 0, toShip = 0, toDeliver = 0, toRate = 0;

        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;

            // Same decision the tracking tabs use (orderBucketFor lives in
            // order_tracking_page.dart), so a badge always matches its tab.
            final bucket = orderBucketFor(data);
            if (bucket == null) continue; // cancelled orders are not counted

            final items = (data['items'] as List?) ?? [];
            final itemCount = items.fold<int>(0, (sum, item) {
              if (item is! Map) return sum + 1;
              final qty = item['qty'] ?? item['quantity'] ?? 1;
              final parsedQty = (qty is num) ? qty.toInt() : 1;
              return sum + parsedQty;
            });

            switch (bucket) {
              case OrderBucket.toPay:
                toPay += itemCount;
                break;
              case OrderBucket.toShip:
                toShip += itemCount;
                break;
              case OrderBucket.toDeliver:
                toDeliver += itemCount;
                break;
              case OrderBucket.toRate:
                toRate += itemCount;
                break;
            }
          }
        }

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.black.withOpacity(0.05),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'MY ORDERS',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                          color: Colors.grey),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              OrderTrackingPage(customerId: customerId),
                        ),
                      ),
                      child: const Text('View All',
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFFF4B400),
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // To Pay first, then To Ship. The last number is the tab
                  // OrderTrackingPage opens on (0 = To Pay, 1 = To Ship).
                  Expanded(
                      child: _trackingIcon(context, customerId,
                          Icons.payments_outlined, 'To Pay', toPay, 0)),
                  Expanded(
                      child: _trackingIcon(context, customerId,
                          Icons.inventory_2_outlined, 'To Ship', toShip, 1)),
                  Expanded(
                      child: _trackingIcon(
                          context,
                          customerId,
                          Icons.local_shipping_outlined,
                          'To Deliver',
                          toDeliver,
                          2)),
                  Expanded(
                      child: _trackingIcon(context, customerId,
                          Icons.star_border_rounded, 'To Rate', toRate, 3)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _trackingIcon(BuildContext context, String customerId, IconData icon,
      String label, int count, int tabIndex) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrderTrackingPage(
              customerId: customerId, initialTabIndex: tabIndex),
        ),
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              // Gold accent instead of a light/dark toggle — reads
              // clearly against both a white card and a near-black one,
              // rather than depending on guessing the exact background
              // shade correctly.
              Icon(icon, size: 26, color: const Color(0xFFF4B400)),
              if (count > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                    constraints:
                    const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text('$count',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
        ],
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

  /// Turns the live `promos` documents into catalog rewards.
  /// Keeps only promos that have a points cost and have not expired,
  /// cheapest first. promo_code is never copied into the result.
  List<_CatalogReward> _rewardsFromDocs(List<QueryDocumentSnapshot> docs) {
    final rewards = <_CatalogReward>[];

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final cost = (data['points_cost'] as num? ?? 0).toInt();
      final discount = (data['discount_percentage'] as num? ?? 0).toInt();

      if (cost <= 0 || discount <= 0) continue; // not meant for the catalog
      if (_isPromoExpired(data['expiry_date'])) continue; // already expired

      final expiry = data['expiry_date'];
      rewards.add(_CatalogReward(
        id: doc.id,
        name: _rewardTitle(discount),
        desc: expiry is String && expiry.isNotEmpty
            ? 'Get $discount% off your next bouquet purchase. Valid until $expiry.'
            : 'Get $discount% off your next bouquet purchase.',
        cost: cost,
        discount: discount,
      ));
    }

    rewards.sort((a, b) => a.cost.compareTo(b.cost));
    return rewards;
  }

  /// Spends points and creates the coupon in ONE all-or-nothing transaction.
  /// Returns the coupon code on success. Throws an Exception with a
  /// customer-friendly message on failure.
  Future<String> _redeemPromo(String promoId) async {
    final db = FirebaseFirestore.instance;
    final customerRef = db.collection('customers').doc(widget.customerId);
    final promoRef = db.collection('promos').doc(promoId);

    // The coupon code doubles as the redemption document id (see rules #32).
    final code = _generateRedemptionCode();
    final redemptionRef = db.collection('redemptions').doc(code);

    await db.runTransaction((tx) async {
      // 1. Read the current truth INSIDE the transaction.
      final customerSnap = await tx.get(customerRef);
      final promoSnap = await tx.get(promoRef);

      if (!customerSnap.exists) {
        throw Exception('Your account could not be found. Please try again.');
      }
      if (!promoSnap.exists) {
        throw Exception('This reward is no longer available.');
      }

      final promo = promoSnap.data() as Map<String, dynamic>;
      final cost = (promo['points_cost'] as num? ?? 0).toInt();
      final discount = (promo['discount_percentage'] as num? ?? 0).toInt();

      if (cost <= 0 || discount <= 0) {
        throw Exception('This reward is no longer available.');
      }
      if (_isPromoExpired(promo['expiry_date'])) {
        throw Exception('This reward has expired.');
      }

      final points = ((customerSnap.data() as Map<String, dynamic>)['points']
      as num? ??
          0)
          .toInt();
      if (points < cost) {
        throw Exception(
            'Not enough points. You need $cost but have $points.');
      }

      // 2. Take the points...
      tx.update(customerRef, {'points': points - cost});

      // 3. ...and save the coupon. Both writes succeed together or not at all.
      tx.set(redemptionRef, {
        'customerId': widget.customerId,
        'promoId': promoId,
        'rewardName': _rewardTitle(discount),
        'costPoints': cost,
        'discountPercentage': discount,
        'code': code,
        'status': 'active',
        'redeemedAt': FieldValue.serverTimestamp(),
        if (promo['expiry_date'] is String)
          'validUntil': promo['expiry_date'],
      });
    });

    return code;
  }

  void _showRewardsCatalog(BuildContext pageContext, int currentPoints) {
    // Which reward is being redeemed right now (null = nothing in progress).
    // Lives outside the builder so it survives rebuilds of the sheet.
    String? redeemingId;
    // Last redeem error, shown inside the sheet (a SnackBar would hide behind it).
    String? errorMessage;

    showModalBottomSheet(
      context: pageContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            final isDark = Theme.of(sheetContext).brightness == Brightness.dark;

            // Runs when the customer taps REDEEM on a card.
            Future<void> onRedeem(_CatalogReward reward) async {
              // Spending points can't be undone, so confirm first.
              final confirmed = await showDialog<bool>(
                context: sheetContext,
                builder: (dialogContext) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  title: const Text('Confirm Redemption'),
                  content: Text(
                      'Spend ${reward.cost} points on "${reward.name}"?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('CANCEL'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B)),
                      child: const Text('REDEEM',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              if (!sheetContext.mounted) return;

              setModalState(() {
                redeemingId = reward.id;
                errorMessage = null;
              });

              try {
                final code = await _redeemPromo(reward.id);

                // Success: close the sheet, then show the coupon from the
                // PAGE's context (the sheet's context is gone after the pop).
                if (sheetContext.mounted) Navigator.pop(sheetContext);
                if (mounted) {
                  _showRedemptionSuccessDialog(pageContext, reward.name, code);
                }
              } catch (e) {
                debugPrint('Redeem failed: $e');
                if (sheetContext.mounted) {
                  setModalState(() {
                    redeemingId = null;
                    errorMessage =
                        e.toString().replaceFirst('Exception: ', '');
                  });
                }
              }
            }

            return Container(
              height: MediaQuery.of(sheetContext).size.height * 0.75,
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
                    'Redeem your accumulated Bloom Points for discount vouchers on your next bouquet.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 16),

                  // Red message box when a redemption fails
                  if (errorMessage != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border:
                        Border.all(color: Colors.redAccent.withOpacity(0.3)),
                      ),
                      child: Text(
                        errorMessage!,
                        style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),

                  Expanded(
                    // Live list: when staff add, edit, or delete a promo on
                    // the web, this list updates by itself.
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('promos')
                          .where('points_cost', isGreaterThan: 0)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting &&
                            !snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFFF59E0B)));
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'Could not load rewards.\n${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                          );
                        }

                        final rewards =
                        _rewardsFromDocs(snapshot.data?.docs ?? []);

                        if (rewards.isEmpty) {
                          return const Center(
                            child: Text(
                              'No rewards available right now.\nCheck back soon!',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          );
                        }

                        return ListView.builder(
                          itemCount: rewards.length,
                          itemBuilder: (context, index) {
                            final reward = rewards[index];
                            final canRedeem = currentPoints >= reward.cost;
                            final isBusy = redeemingId == reward.id;

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
                                      child: Icon(Icons.local_activity_outlined,
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
                                            reward.name,
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
                                            reward.desc,
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[600]),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '${reward.cost} Points Required',
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
                                      // Disabled when too expensive OR while
                                      // any redemption is already running.
                                      onPressed:
                                      (!canRedeem || redeemingId != null)
                                          ? null
                                          : () => onRedeem(reward),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                        const Color(0xFFF59E0B),
                                        disabledBackgroundColor:
                                        Colors.grey[300],
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 8),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                            BorderRadius.circular(12)),
                                        elevation: 0,
                                      ),
                                      child: isBusy
                                          ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white))
                                          : Text(
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
                'Screenshot or copy this code, then present it at the florist counter to claim your reward.',
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