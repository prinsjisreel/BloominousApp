import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_sidebar.dart';
import 'inventory_data.dart';

/// BLOOMINOUS - Delivery Status Monitoring (mobile twin of web delivery_status.php)
///
/// READ-ONLY. This page never writes to `orders`. It only displays each online
/// order's delivery status and lets staff view the rider's Proof of Delivery
/// photo. Status changes happen in Orders (Order Management), which is the
/// single owner of order status on both web and app.
class DeliveryStatusPage extends StatefulWidget {
  final String role;

  const DeliveryStatusPage({super.key, required this.role});

  @override
  State<DeliveryStatusPage> createState() => _DeliveryStatusPageState();
}

class _DeliveryStatusPageState extends State<DeliveryStatusPage> {
  // Created ONCE in initState so screen rebuilds don't open new Firestore listeners.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _ordersStream;
  late final String _branchId;

  // Brand colors for the status badges (same meaning as web's badge classes).
  static const Color _pendingColor = Color(0xFFFFBB55);   // .badge-pending
  static const Color _transitColor = Color(0xFF7B79F2);   // .badge-transit
  static const Color _confirmedColor = Color(0xFF2ECC71); // .badge-confirmed
  static const Color _accent = Color(0xFFF59E0B);

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    // Same fallback the checkout uses when no branch has been picked yet.
    _branchId = InventoryData.selectedBranchId ?? 'main_branch';

    // Same query as web: filter by branch only, then filter/sort on the device.
    // (Adding orderBy here would require a Firestore composite index.)
    _ordersStream = FirebaseFirestore.instance
        .collection('orders')
        .where('branchId', isEqualTo: _branchId)
        .snapshots();
  }

  // ─────────────────────────── Helpers ───────────────────────────

  /// Maps any stored status to the 4 statuses Order Management can set.
  /// Older records ("delivered", "completed") fall back to "Confirmed", exactly like web.
  static String _displayStatus(dynamic raw) {
    final status = (raw ?? 'pending').toString().toLowerCase();
    if (status == 'confirmed' || status == 'delivered' || status == 'completed') {
      return 'Confirmed';
    }
    if (status == 'in transit') return 'In Transit';
    if (status == 'processing') return 'Processing';
    return 'Pending';
  }

  static Color _statusColor(String displayStatus) {
    switch (displayStatus) {
      case 'Confirmed':
        return _confirmedColor;
      case 'In Transit':
      case 'Processing':
        return _transitColor;
      default:
        return _pendingColor;
    }
  }

  /// Turns a Firestore Timestamp into "Sep 30, 2026". Missing dates show "Recently".
  static String _formatDate(dynamic ts) {
    if (ts is! Timestamp) return 'Recently';
    final d = ts.toDate();
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  /// Timestamp → number for sorting. Orders without a timestamp sink to the bottom.
  static int _millis(dynamic ts) => ts is Timestamp ? ts.millisecondsSinceEpoch : 0;

  /// "#A1B2C3D4" style short ID, safe even if an ID is shorter than 8 characters.
  static String _shortId(String id) =>
      '#${(id.length > 8 ? id.substring(0, 8) : id).toUpperCase()}';

  // ─────────────────────────── Build ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);

    return Scaffold(
      drawer: Drawer(
        width: 260,
        child: AppSidebar(role: widget.role, currentPage: 'delivery'),
      ),
      appBar: AppBar(
        title: Text(
          'DELIVERY STATUS',
          style: GoogleFonts.cormorantGaramond(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textColor,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _ordersStream,
        builder: (context, snapshot) {
          // 1) Firestore failed (rules, network, etc.)
          if (snapshot.hasError) {
            return _messageState(
              icon: Icons.error_outline,
              text: 'Could not load deliveries.\n${snapshot.error}',
              isDark: isDark,
            );
          }

          // 2) First data hasn't arrived yet
          if (!snapshot.hasData) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: _transitColor),
                  SizedBox(height: 12),
                  Text('Syncing with logistics database...'),
                ],
              ),
            );
          }

          // 3) Keep online orders only. Walk-in (POS) orders have no delivery leg.
          final onlineDocs = snapshot.data!.docs
              .where((doc) => (doc.data()['type'] ?? 'WEB') != 'POS')
              .toList();

          // 4) Newest first
          onlineDocs.sort(
                (a, b) => _millis(b.data()['timestamp']).compareTo(_millis(a.data()['timestamp'])),
          );

          if (onlineDocs.isEmpty) {
            return _messageState(
              icon: Icons.local_shipping_outlined,
              text: 'No online deliveries found.',
              isDark: isDark,
            );
          }

          // 5) Header + one card per order
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: onlineDocs.length + 1, // +1 for the header row
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) return _buildHeader(isDark, textColor);
              return _buildDeliveryCard(onlineDocs[index - 1], isDark, textColor);
            },
          );
        },
      ),
    );
  }

  // ─────────────────────────── UI pieces ───────────────────────────

  Widget _buildHeader(bool isDark, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Icon(Icons.local_shipping, color: Colors.pinkAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Monitoring only — statuses are changed from Orders.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryCard(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      bool isDark,
      Color textColor,
      ) {
    final data = doc.data();
    final displayStatus = _displayStatus(data['status']);
    final statusColor = _statusColor(displayStatus);

    final customerName =
    (data['customer_name'] ?? data['customerName'] ?? 'Guest Customer').toString();
    final date = _formatDate(data['timestamp']);

    final podUrl = data['podPhotoUrl']?.toString() ?? '';
    final courier = data['courierName']?.toString() ?? '';
    final recipient = data['podRecipient']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.grey.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: order info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _shortId(doc.id),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.5,
                    color: _accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  customerName,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: textColor),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  date,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7D8DA1)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Right: status badge + proof of delivery
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  displayStatus.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              podUrl.isNotEmpty
                  ? GestureDetector(
                onTap: () => _showPodPhoto(podUrl, courier, recipient),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    podUrl,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Icons.broken_image_outlined, color: Colors.grey),
                    ),
                  ),
                ),
              )
                  : Text(
                'No POD yet',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[400],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Read-only viewer for the rider's proof-of-delivery photo (web's #podViewOverlay).
  void _showPodPhoto(String photoUrl, String courier, String recipient) {
    final metaParts = <String>[
      if (courier.isNotEmpty) 'Courier: $courier',
      if (recipient.isNotEmpty) 'Received by: $recipient',
    ];

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  photoUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  errorBuilder: (_, __, ___) => const SizedBox(
                    height: 200,
                    child: Center(child: Text('Photo could not be loaded.')),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                metaParts.isEmpty ? 'No additional details on file.' : metaParts.join(' · '),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('CLOSE', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messageState({required IconData icon, required String text, required bool isDark}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: isDark ? Colors.grey[600] : Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}