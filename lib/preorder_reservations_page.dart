import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class PreordersPage extends StatefulWidget {
  const PreordersPage({super.key});

  @override
  State<PreordersPage> createState() => _PreordersPageState();
}

class _PreordersPageState extends State<PreordersPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> _updateStatus(String orderId, String newStatus) async {
    try {
      await _db.collection('orders').doc(orderId).update({
        'status': newStatus,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reservation status updated to $newStatus'),
            backgroundColor: Colors.amber[700],
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
  }

  Future<void> _rescheduleDate(String orderId, DateTime newDate) async {
    try {
      await _db.collection('orders').doc(orderId).update({
        'reservationDate': Timestamp.fromDate(newDate),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reservation rescheduled successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reschedule: $e')),
      );
    }
  }

  Future<void> _selectNewDate(
      BuildContext context, String orderId, DateTime currentDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      await _rescheduleDate(orderId, picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            'PRE-ORDERS & RESERVATIONS',
            style: GoogleFonts.cormorantGaramond(
                fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          backgroundColor: isDark ? Colors.black : const Color(0xFFF59E0B),
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.schedule), text: 'Upcoming'),
              Tab(icon: Icon(Icons.check_circle_outline), text: 'Completed'),
              Tab(
                  icon: Icon(Icons.all_inbox_outlined),
                  text: 'All Reservations'),
            ],
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: _db.collection('orders').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                  child: Text('Error loading reservations: ${snapshot.error}'));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final orderDocs = snapshot.data?.docs ?? [];
            final List<Map<String, dynamic>> allOrders = orderDocs.map((doc) {
              return {
                ...doc.data() as Map<String, dynamic>,
                'id': doc.id,
              };
            }).toList();

            // We filter for pre-orders or scheduled reservations
            // For general compatibility, we include:
            // 1. Orders marked as 'pre_order' or has a 'reservationDate'
            // 2. Orders with deliveryAddress or special notes indicating future reservation bookings
            // 3. Or simply all orders processed as reservation to manage delivery dates!
            final reservations = allOrders.where((order) {
              final String type =
                  (order['type'] ?? '').toString().toLowerCase();
              final String orderType =
                  (order['orderType'] ?? '').toString().toLowerCase();
              final bool isGift =
                  order['is_gift'] == true || order['isGift'] == true;
              final hasResDate = order['reservationDate'] != null;

              // We match catalog checkouts, gifts, custom bookings or pre_orders
              return hasResDate ||
                  type.contains('pre') ||
                  orderType.contains('catalog') ||
                  isGift;
            }).toList();

            // Sort reservations by closest date
            reservations.sort((a, b) {
              final dateA =
                  a['reservationDate'] ?? a['createdAt'] ?? a['created_at'];
              final dateB =
                  b['reservationDate'] ?? b['createdAt'] ?? b['created_at'];
              if (dateA == null && dateB == null) return 0;
              if (dateA == null) return 1;
              if (dateB == null) return -1;
              try {
                return (dateB as dynamic).compareTo(dateA);
              } catch (_) {
                return 0;
              }
            });

            final upcoming = reservations
                .where((o) =>
                    o['status'] != 'delivered' && o['status'] != 'cancelled')
                .toList();
            final completed = reservations
                .where((o) =>
                    o['status'] == 'delivered' || o['status'] == 'cancelled')
                .toList();

            return TabBarView(
              children: [
                _buildOrderList(upcoming, context, isDark),
                _buildOrderList(completed, context, isDark),
                _buildOrderList(reservations, context, isDark),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildOrderList(
      List<Map<String, dynamic>> list, BuildContext context, bool isDark) {
    if (list.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('No active bookings found in this category.',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final order = list[index];
        final orderId = order['id'];
        final status = order['status'] ?? 'pending';
        final total =
            (order['totalAmount'] ?? order['totalPrice'] ?? 0.0).toDouble();
        final items = (order['items'] ?? []) as List<dynamic>;

        // Parse dates
        final createdAtRaw = order['createdAt'] ?? order['created_at'];
        final DateTime createdDate =
            createdAtRaw != null && createdAtRaw is Timestamp
                ? createdAtRaw.toDate()
                : DateTime.now();

        final resDateRaw = order['reservationDate'];
        final DateTime reservationDate =
            resDateRaw != null && resDateRaw is Timestamp
                ? resDateRaw.toDate()
                : createdDate.add(const Duration(
                    days: 2)); // default pre-order target is +2 days if not set

        final String formattedCreated =
            DateFormat('MMM dd, yyyy - hh:mm a').format(createdDate);
        final String formattedReserved =
            DateFormat('EEEE, MMMM dd, yyyy').format(reservationDate);

        final bool isGift = order['is_gift'] == true || order['isGift'] == true;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
                color:
                    isGift ? Colors.amber.withOpacity(0.5) : Colors.transparent,
                width: 1.5),
          ),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: isGift
                  ? Colors.amber.withOpacity(0.15)
                  : Colors.blue.withOpacity(0.1),
              child: Icon(
                isGift ? Icons.card_giftcard : Icons.alarm,
                color: isGift ? Colors.amber[800] : Colors.blue,
              ),
            ),
            title: Text(
              order['recipientName'] ??
                  order['customer_name'] ??
                  order['customerName'] ??
                  'Walk-In Customer',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.calendar_month,
                        size: 12, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(
                      'Booking Date: $formattedReserved',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber),
                    ),
                  ],
                ),
                Text('Placed: $formattedCreated',
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
            trailing: Text(
              '₱${total.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.green),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    const Text('ORDER ITEMS:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: Colors.grey)),
                    const SizedBox(height: 6),
                    ...items.map((it) {
                      final name = it['name'] ?? 'Custom Flower Bouquet';
                      final qty = it['qty'] ?? it['quantity'] ?? 1;
                      final price = (it['price'] ?? 0.0).toDouble();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('$name x$qty',
                                style: const TextStyle(fontSize: 12)),
                            Text('₱${(price * qty).toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      );
                    }).toList(),
                    const Divider(height: 24),
                    const Text('RESERVATION SPECS:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: Colors.grey)),
                    const SizedBox(height: 6),
                    Text(
                        'Delivery Address: ${order['deliveryAddress'] ?? order['address'] ?? "Self-PickUp"}',
                        style: const TextStyle(fontSize: 12)),
                    if (order['notes'] != null &&
                        order['notes'].toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Notes: ${order['notes']}',
                            style: const TextStyle(
                                fontSize: 12, fontStyle: FontStyle.italic)),
                      ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Status:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12)),
                        DropdownButton<String>(
                          value: status == 'Order Placed' || status == 'pending'
                              ? 'pending'
                              : (status == 'delivered' ? 'delivered' : status),
                          items: const [
                            DropdownMenuItem(
                                value: 'pending',
                                child: Text('Pending Approval')),
                            DropdownMenuItem(
                                value: 'confirmed',
                                child: Text('Reservation Confirmed')),
                            DropdownMenuItem(
                                value: 'processing',
                                child: Text('Production Stage')),
                            DropdownMenuItem(
                                value: 'out_for_delivery',
                                child: Text('On Its Way')),
                            DropdownMenuItem(
                                value: 'delivered',
                                child: Text('Delivered & Closed')),
                            DropdownMenuItem(
                                value: 'cancelled', child: Text('Cancelled')),
                          ],
                          onChanged: (newStatus) {
                            if (newStatus != null) {
                              _updateStatus(orderId, newStatus);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () =>
                              _selectNewDate(context, orderId, reservationDate),
                          icon: const Icon(Icons.edit_calendar, size: 16),
                          label: const Text('Reschedule Booking Date',
                              style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        if (status != 'delivered' && status != 'cancelled')
                          TextButton(
                            onPressed: () =>
                                _updateStatus(orderId, 'delivered'),
                            child: const Text('Mark Completed',
                                style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
