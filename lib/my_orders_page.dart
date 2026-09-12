import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'inventory_data.dart';
import 'order_tracking_page.dart';

class MyOrdersPage extends StatefulWidget {
  final String? email;
  // NEW: accepts an explicit userId, matching how customer_profile_page.dart
  // already calls this widget (MyOrdersPage(userId: widget.customerId, ...)).
  // Optional and additive — every other call site that only passes `email`
  // is completely unaffected.
  final String? userId;
  const MyOrdersPage({super.key, this.email, this.userId});

  @override
  State<MyOrdersPage> createState() => _MyOrdersPageState();
}

class _MyOrdersPageState extends State<MyOrdersPage> {
  String _filterStatus = 'All';

  final List<String> _filterOptions = [
    'All',
    'Pending',
    'Processing',
    'Shipped',
    'Delivered',
    'Cancelled'
  ];

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'processing':
        return Colors.blue;
      case 'shipped':
      case 'in transit':
        return Colors.purple;
      case 'delivered':
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.hourglass_empty_rounded;
      case 'processing':
        return Icons.settings_rounded;
      case 'shipped':
      case 'in transit':
        return Icons.local_shipping_rounded;
      case 'delivered':
      case 'completed':
        return Icons.check_circle_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  int _initialTabFor(Map<String, dynamic> order) {
    final status = (order['status'] ?? '').toString().toLowerCase();
    final paymentStatus = (order['paymentStatus'] ?? '').toString().toLowerCase();
    final paymentMethod = (order['payment_method'] ?? order['paymentMethod'] ?? '')
        .toString()
        .toLowerCase();

    if (status == 'delivered' || status == 'completed') return 3;
    if (status == 'shipped' || status == 'out_for_delivery') return 2;

    final isOnlinePayment = paymentMethod == 'gcash' ||
        paymentMethod == 'maya' ||
        paymentMethod == 'paymaya' ||
        paymentMethod == 'paymongo';
    final paymentUnresolved =
        paymentStatus.contains('pending') || paymentStatus.contains('awaiting');

    if (isOnlinePayment && paymentUnresolved) return 0;
    return 1;
  }

  Future<void> _cancelOrder(String orderId) async {
    try {
      await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });

      final orderSnap = await FirebaseFirestore.instance.collection('orders').doc(orderId).get();
      final orderData = orderSnap.data();
      final branchIdForNotif = orderData?['branchId'];
      final shortId = '#${(orderId.length > 8 ? orderId.substring(0, 8) : orderId).toUpperCase()}';
      final customerName = (orderData?['customer_name'] ?? orderData?['customerName'] ?? 'A customer').toString();

      await InventoryData.createNotification(
        title: 'Order Cancellation Requested',
        message: '$customerName cancelled order $shortId.',
        type: 'warning',
        branchId: branchIdForNotif,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order cancelled successfully'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cancelling order: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showCancelConfirmation(String orderId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Order?'),
        content: const Text('Are you sure you want to cancel this order? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No, Keep Order'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelOrder(orderId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    // NEW: explicit widget.userId (if the caller provided one) wins;
    // otherwise falls back to the signed-in Firebase user, exactly as
    // before. This means customer_profile_page.dart's
    // MyOrdersPage(userId: widget.customerId) now actually filters by
    // that specific customer ID instead of erroring at compile time.
    final effectiveUserId = widget.userId ?? user?.uid;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        backgroundColor: isDark ? Colors.black : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: _filterOptions.map((status) {
                final isSelected = _filterStatus == status;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(status),
                    selected: isSelected,
                    onSelected: (val) => setState(() => _filterStatus = status),
                    selectedColor: const Color(0xFFF59E0B),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    backgroundColor: isDark ? Colors.grey[900] : Colors.grey[100],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: InventoryData.getUserOrdersStream(userId: effectiveUserId, email: widget.email),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          var orders = snapshot.data ?? [];

          if (_filterStatus != 'All') {
            orders = orders.where((o) {
              final status = (o['status'] ?? '').toString().toLowerCase();
              return status == _filterStatus.toLowerCase();
            }).toList();
          }

          if (orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('No orders found', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final orderId = order['id'];
              final status = (order['status'] ?? 'pending').toString();
              final items = (order['items'] as List?) ?? [];
              final total = (order['total_price'] ?? order['totalAmount'] ?? 0.0).toDouble();
              final rawDate = order['createdAt'] ?? order['created_at'];
              final date = rawDate is Timestamp ? rawDate.toDate() : DateTime.now();
              final canCancel = status.toLowerCase() == 'pending';

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900] : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Order #${orderId.toString().substring(0, 8).toUpperCase()}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              Text(DateFormat('MMM d, yyyy').format(date),
                                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _getStatusColor(status).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_getStatusIcon(status), size: 14, color: _getStatusColor(status)),
                                const SizedBox(width: 4),
                                Text(status.toUpperCase(),
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _getStatusColor(status))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: items.take(2).map((item) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text('${item['name'] ?? 'Item'} x${item['qty'] ?? 1}',
                                style: TextStyle(fontSize: 13, color: isDark ? Colors.grey[300] : Colors.grey[700])),
                          );
                        }).toList(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('₱${total.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFF59E0B))),
                          Row(
                            children: [
                              if (canCancel)
                                TextButton(
                                  onPressed: () => _showCancelConfirmation(orderId),
                                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                                  child: const Text('Cancel'),
                                ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => OrderTrackingPage(
                                        customerId: effectiveUserId ?? '',
                                        initialTabIndex: _initialTabFor(order),
                                      ),
                                    ),
                                  );
                                },
                                child: const Text('Track Order'),
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
        },
      ),
    );
  }
}