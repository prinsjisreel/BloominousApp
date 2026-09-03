import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'inventory_data.dart';
import 'app_sidebar.dart';

class DeliveryStatusPage extends StatelessWidget {
  final String role;
  const DeliveryStatusPage({super.key, this.role = 'employee'});

  // --- Mirrors delivery_status.php's exact rule: (o.type || 'WEB') !== 'POS'.
  // Walk-in orders never have a delivery leg (handed over in person), so this
  // monitor only ever shows online orders — same contract as orders_page.dart's
  // _isOnlineOrder(), kept identical on purpose so both screens can never
  // disagree about which orders count as "online." ---
  bool _isOnlineOrder(Map<String, dynamic> o) {
    final type = (o['type'] ?? 'WEB').toString().toUpperCase();
    return type != 'POS';
  }

  // --- Mirrors delivery_status.php's displayStatus mapping exactly:
  // confirmed/delivered/completed -> Confirmed
  // in transit                    -> In Transit
  // processing                    -> Processing
  // anything else                 -> Pending
  // This is a deliberate narrowing from whatever raw value Firestore holds
  // down to only 4 possible labels — matching the web page's chart of
  // states instead of just echoing back the database's raw text. ---
  String _displayStatus(Map<String, dynamic> o) {
    final status = (o['status'] ?? 'pending').toString().toLowerCase();
    if (status == 'confirmed' || status == 'delivered' || status == 'completed') {
      return 'Confirmed';
    }
    if (status == 'in transit') return 'In Transit';
    if (status == 'processing') return 'Processing';
    return 'Pending';
  }

  // --- Mirrors web's badgeClass assignment exactly: Processing and In
  // Transit deliberately SHARE one color (badge-transit) — they are not
  // meant to look different from each other at a glance, only Pending and
  // Confirmed get their own distinct colors. ---
  Color _badgeColor(String displayStatus) {
    switch (displayStatus) {
      case 'In Transit':
      case 'Processing':
        return const Color(0xFF7B79F2); // matches web's var(--secondary)
      case 'Confirmed':
        return const Color(0xFF2ECC71);
      default: // Pending
        return const Color(0xFFFFBB55);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width >= 850;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFFFFDF9),
      appBar: AppBar(
        title: Text(
          'Delivery Status',
          style: GoogleFonts.cormorantGaramond(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        backgroundColor: isDark ? Colors.black : const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      drawer: isDesktop ? null : Drawer(child: AppSidebar(role: role, currentPage: 'delivery')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) AppSidebar(role: role, currentPage: 'delivery'),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: InventoryData.ordersStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error loading deliveries: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)));
                }

                final allOrders = snapshot.data ?? [];
                // FIXED: now uses the real web contract instead of a
                // guessed 'WALK_IN' string that never matched anything.
                final deliveryOrders = allOrders.where(_isOnlineOrder).toList()
                  ..sort((a, b) {
                    final ta = a['timestamp'] ?? a['createdAt'];
                    final tb = b['timestamp'] ?? b['createdAt'];
                    if (ta is! Timestamp || tb is! Timestamp) return 0;
                    return tb.compareTo(ta);
                  });

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Delivery Status',
                                  style: GoogleFonts.cormorantGaramond(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Monitoring only — statuses are changed from Order Management.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.pink.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.pink.withOpacity(0.2)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.local_shipping_rounded, size: 16, color: Colors.pink),
                                const SizedBox(width: 6),
                                Text(
                                  'REAL-TIME FLEET STATUS',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.pink[700],
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (deliveryOrders.isEmpty)
                        Container(
                          height: 200,
                          width: double.infinity,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[900] : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.withOpacity(0.15)),
                          ),
                          child: Text(
                            'No online deliveries found.',
                            style: TextStyle(color: Colors.grey[400], fontSize: 14),
                          ),
                        )
                      else if (MediaQuery.of(context).size.width >= 700)
                        _buildTable(context, deliveryOrders, isDark)
                      else
                        Column(children: deliveryOrders.map((o) => _buildCard(context, o, isDark)).toList()),
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

  Widget _buildTable(BuildContext context, List<Map<String, dynamic>> deliveryOrders, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('ORDER ID', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey))),
                Expanded(flex: 3, child: Text('CUSTOMER NAME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey))),
                Expanded(flex: 2, child: Text('ORDER DATE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey))),
                Expanded(flex: 2, child: Text('DELIVERY STATUS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey))),
                Expanded(flex: 2, child: Text('PROOF OF DELIVERY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey))),
              ],
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: deliveryOrders.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final order = deliveryOrders[index];
              final rowData = _extractRowData(order);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(rowData.shortId,
                          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFFF59E0B))),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(rowData.customerName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(rowData.formattedDate, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ),
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: rowData.badgeColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(rowData.displayStatus.toUpperCase(),
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: rowData.badgeColor)),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: _buildPodCell(context, rowData),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, Map<String, dynamic> order, bool isDark) {
    final rowData = _extractRowData(order);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(rowData.shortId,
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFFF59E0B))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: rowData.badgeColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(rowData.displayStatus.toUpperCase(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: rowData.badgeColor)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(rowData.customerName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 4),
          Text(rowData.formattedDate, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 10),
          _buildPodCell(context, rowData),
        ],
      ),
    );
  }

  Widget _buildPodCell(BuildContext context, _DeliveryRowData rowData) {
    if (rowData.podUrl == null || rowData.podUrl!.isEmpty) {
      return Text('Not yet uploaded', style: TextStyle(fontSize: 12, color: Colors.grey[400], fontStyle: FontStyle.italic));
    }
    // NEW: matches web's viewPodPhoto() — tapping the thumbnail opens a
    // detail dialog instead of just sitting there as a static image.
    return GestureDetector(
      onTap: () => _showPodDialog(context, rowData),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              rowData.podUrl!,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.verified, color: Colors.green, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.zoom_in, size: 14, color: Colors.grey),
        ],
      ),
    );
  }

  void _showPodDialog(BuildContext context, _DeliveryRowData rowData) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  rowData.podUrl!,
                  errorBuilder: (_, __, ___) => Container(
                    height: 200,
                    color: Colors.grey[200],
                    child: const Icon(Icons.broken_image, size: 48),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                [
                  if (rowData.courierName != null && rowData.courierName!.isNotEmpty) 'Courier: ${rowData.courierName}',
                  if (rowData.podRecipient != null && rowData.podRecipient!.isNotEmpty) 'Received by: ${rowData.podRecipient}',
                ].join(' · ').isEmpty
                    ? 'No additional details on file.'
                    : [
                  if (rowData.courierName != null && rowData.courierName!.isNotEmpty) 'Courier: ${rowData.courierName}',
                  if (rowData.podRecipient != null && rowData.podRecipient!.isNotEmpty) 'Received by: ${rowData.podRecipient}',
                ].join(' · '),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _DeliveryRowData _extractRowData(Map<String, dynamic> order) {
    final id = (order['id'] ?? order['orderId'] ?? '').toString();
    final shortId = '#${(id.length > 8 ? id.substring(0, 8) : id).toUpperCase()}';

    // FIXED: customer_name checked first, matching the real field name
    // confirmed from invoice_management.php's o.customer_name || o.customerName.
    final customerName = (order['customer_name'] ?? order['customerName'] ?? 'Guest Customer').toString();

    final rawDate = order['timestamp'] ?? order['createdAt'];
    DateTime date = DateTime.now();
    if (rawDate is Timestamp) {
      date = rawDate.toDate();
    } else if (rawDate is String) {
      date = DateTime.tryParse(rawDate) ?? DateTime.now();
    }
    final formattedDate = DateFormat('MMM d, yyyy').format(date);

    final displayStatus = _displayStatus(order);
    final badgeColor = _badgeColor(displayStatus);

    final podUrl = (order['podPhotoUrl'] ?? order['proofOfDeliveryPhoto']) as String?;
    final courierName = order['courierName'] as String?;
    final podRecipient = order['podRecipient'] as String?;

    return _DeliveryRowData(
      shortId: shortId,
      customerName: customerName,
      formattedDate: formattedDate,
      displayStatus: displayStatus,
      badgeColor: badgeColor,
      podUrl: podUrl,
      courierName: courierName,
      podRecipient: podRecipient,
    );
  }
}

class _DeliveryRowData {
  final String shortId;
  final String customerName;
  final String formattedDate;
  final String displayStatus;
  final Color badgeColor;
  final String? podUrl;
  final String? courierName;
  final String? podRecipient;

  _DeliveryRowData({
    required this.shortId,
    required this.customerName,
    required this.formattedDate,
    required this.displayStatus,
    required this.badgeColor,
    this.podUrl,
    this.courierName,
    this.podRecipient,
  });
}