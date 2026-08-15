import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'inventory_data.dart';

class DeliveryStatusPage extends StatelessWidget {
  const DeliveryStatusPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFFFFDF9),
      appBar: AppBar(
        title: Text(
          'Delivery Status',
          style: GoogleFonts.cormorantGaramond(
              fontWeight: FontWeight.bold, fontSize: 24),
        ),
        backgroundColor: isDark ? Colors.black : const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: InventoryData.ordersStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
                child: Text('Error loading deliveries: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFFF59E0B)));
          }

          final allOrders = snapshot.data ?? [];
          // Filter out in-store walk-in orders if desired, or include all delivery orders
          final deliveryOrders = allOrders.where((o) {
            final orderType =
                (o['orderType'] ?? o['type'] ?? '').toString().toUpperCase();
            return !orderType.contains('WALK_IN');
          }).toList();

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
                              color:
                                  isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.pink.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.pink.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.local_shipping_rounded,
                              size: 16, color: Colors.pink),
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
                      'No active deliveries in queue.',
                      style: TextStyle(color: Colors.grey[400], fontSize: 14),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[900] : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.withOpacity(0.15)),
                    ),
                    child: Column(
                      children: [
                        // Table Header
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.black26
                                : const Color(0xFFF8FAFC),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(20)),
                          ),
                          child: const Row(
                            children: [
                              Expanded(
                                  flex: 2,
                                  child: Text('ORDER ID',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey))),
                              Expanded(
                                  flex: 3,
                                  child: Text('CUSTOMER NAME',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey))),
                              Expanded(
                                  flex: 2,
                                  child: Text('ORDER DATE',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey))),
                              Expanded(
                                  flex: 2,
                                  child: Text('DELIVERY STATUS',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey))),
                              Expanded(
                                  flex: 3,
                                  child: Text('PROOF OF DELIVERY',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey))),
                            ],
                          ),
                        ),
                        const Divider(height: 1),

                        // Table Rows
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: deliveryOrders.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final order = deliveryOrders[index];
                            final orderId = (order['id'] ??
                                    order['orderId'] ??
                                    'ORD-#${index + 1000}')
                                .toString();
                            final shortId = orderId.length > 8
                                ? '#${orderId.substring(0, 8).toUpperCase()}'
                                : '#${orderId.toUpperCase()}';

                            final customerName = (order['customerName'] ??
                                    order['recipientName'] ??
                                    'Valued Customer')
                                .toString();
                            final rawDate = order['createdAt'];
                            DateTime date = DateTime.now();
                            if (rawDate is Timestamp) {
                              date = rawDate.toDate();
                            } else if (rawDate is String) {
                              date =
                                  DateTime.tryParse(rawDate) ?? DateTime.now();
                            }
                            final formattedDate =
                                DateFormat('MMM d, yyyy').format(date);

                            final rawStatus = (order['status'] ?? 'PENDING')
                                .toString()
                                .toUpperCase();

                            // Proof of delivery info
                            final podUrl = (order['proofOfDeliveryPhoto'] ??
                                order['podPhotoUrl']) as String?;
                            final podRecipient = (order['podRecipient'] ??
                                order['recipientName']) as String?;

                            Color statusColor = Colors.orange;
                            if (rawStatus.contains('DELIVERED') ||
                                rawStatus.contains('COMPLETED')) {
                              statusColor = Colors.green;
                            } else if (rawStatus.contains('TRANSIT') ||
                                rawStatus.contains('PROCESSING')) {
                              statusColor = Colors.blue;
                            } else if (rawStatus.contains('CANCEL')) {
                              statusColor = Colors.red;
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 16),
                              child: Row(
                                children: [
                                  // ORDER ID
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      shortId,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: const Color(0xFFF59E0B),
                                      ),
                                    ),
                                  ),
                                  // CUSTOMER NAME
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      customerName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13),
                                    ),
                                  ),
                                  // ORDER DATE
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      formattedDate,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600]),
                                    ),
                                  ),
                                  // DELIVERY STATUS
                                  Expanded(
                                    flex: 2,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: statusColor.withOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          rawStatus,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // PROOF OF DELIVERY
                                  Expanded(
                                    flex: 3,
                                    child: podUrl != null && podUrl.isNotEmpty
                                        ? Row(
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                child: Image.network(
                                                  podUrl,
                                                  width: 32,
                                                  height: 32,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error,
                                                          stackTrace) =>
                                                      const Icon(Icons.verified,
                                                          color: Colors.green,
                                                          size: 20),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  podRecipient != null
                                                      ? 'Received by $podRecipient'
                                                      : 'Verified POD Uploaded',
                                                  style: const TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.green,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          )
                                        : Text(
                                            'Not yet uploaded',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[400],
                                                fontStyle: FontStyle.italic),
                                          ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
