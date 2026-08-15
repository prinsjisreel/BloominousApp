import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'inventory_data.dart';

class MyOrdersPage extends StatefulWidget {
  final String userId;
  final String? email;
  const MyOrdersPage({super.key, required this.userId, this.email});

  @override
  State<MyOrdersPage> createState() => _MyOrdersPageState();
}

class _MyOrdersPageState extends State<MyOrdersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFFFFDF7),
      appBar: AppBar(
        title: Text(
          'MY ORDERS',
          style: GoogleFonts.cormorantGaramond(
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFF4B400),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFFF4B400),
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Completed'),
            Tab(text: 'Cancelled'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOrdersList('active'),
          _buildOrdersList('completed'),
          _buildOrdersList('cancelled'),
        ],
      ),
    );
  }

  Widget _buildOrdersList(String type) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: InventoryData.getUserOrdersStream(
          userId: widget.userId, email: widget.email),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_bag_outlined,
                    size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text('No $type orders found.',
                    style: TextStyle(color: Colors.grey[400])),
              ],
            ),
          );
        }

        final allOrders = snapshot.data!;
        final filteredOrders = allOrders.where((order) {
          final status =
              (order['status'] ?? 'pending').toString().toLowerCase();
          if (status == 'delivered') {
            // Move delivered to completed
            if (type == 'completed') return true;
            return false;
          }

          if (type == 'active') {
            return status != 'completed' &&
                status != 'cancelled' &&
                status != 'delivered';
          } else if (type == 'completed') {
            return status == 'completed' || status == 'delivered';
          } else {
            return status == 'cancelled';
          }
        }).toList();

        if (filteredOrders.isEmpty) {
          return Center(
              child: Text('No $type orders.',
                  style: const TextStyle(color: Colors.grey)));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filteredOrders.length,
          itemBuilder: (context, index) {
            return _buildOrderCard(filteredOrders[index]);
          },
        );
      },
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = order['status'] ?? 'pending';
    final date = order['createdAt'] != null
        ? (order['createdAt'] as dynamic).toDate()
        : DateTime.now();
    final formattedDate = DateFormat('MMM dd, yyyy').format(date);
    final total =
        (order['totalAmount'] ?? order['totalPrice'] ?? 0.0).toDouble();
    final orderId = order['id']
        .toString()
        .toUpperCase()
        .substring(0, min(8, order['id'].toString().length));
    final items = (order['items'] as List<dynamic>?) ?? [];

    // Determine the main display name
    String mainItemName = "Generic Bouquet";
    if (items.isNotEmpty) {
      mainItemName = items.first['name'] ?? "Bouquet Arrangement";
      if (items.length > 1) {
        mainItemName += " (+${items.length - 1} more)";
      }
    } else if (order['orderType'] == 'CUSTOM_AR') {
      mainItemName = "AR Custom Arrangement";
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ORD-$orderId',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      mainItemName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    Text(
                      'Placed on $formattedDate • ${order['paymentStatus'] == 'paid' ? "Paid" : "Unpaid"}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                _buildStatusBadge(status),
              ],
            ),
            const SizedBox(height: 24),

            // Tracking Timeline
            _buildTrackingTimeline(status),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '₱${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      color: Color(0xFFF4B400)),
                ),
                TextButton(
                  onPressed: () => _showOrderDetails(order),
                  child: const Text('View Details →',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;
    final s = status.toLowerCase();

    switch (s) {
      case 'pending':
        color = Colors.orange;
        label = 'PLANNED';
        break;
      case 'confirmed':
        color = Colors.blue;
        label = 'CONFIRMED';
        break;
      case 'processing':
      case 'in_progress':
        color = Colors.purple;
        label = 'PRODUCTION';
        break;
      case 'out_for_delivery':
        color = Colors.indigo;
        label = 'SHIPPING';
        break;
      case 'completed':
      case 'delivered':
        color = Colors.green;
        label = 'DONE';
        break;
      case 'cancelled':
        color = Colors.red;
        label = 'CANCELLED';
        break;
      default:
        color = Colors.grey;
        label = status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildTrackingTimeline(String status) {
    int currentStep = 0;
    final s = status.toLowerCase();
    if (s == 'pending') currentStep = 1;
    if (s == 'confirmed') currentStep = 2;
    if (s == 'processing' || s == 'in_progress') currentStep = 3;
    if (s == 'out_for_delivery') currentStep = 4;
    if (s == 'delivered' || s == 'completed') currentStep = 5;
    if (s == 'cancelled') currentStep = 0;

    return Column(
      children: [
        Row(
          children: [
            _buildTimelineNode('Placed', currentStep >= 1, true, false),
            _buildTimelineNode('Confirmed', currentStep >= 2, false, false),
            _buildTimelineNode('Production', currentStep >= 3, false, false),
            _buildTimelineNode('Shipping', currentStep >= 4, false, false),
            _buildTimelineNode('Done', currentStep >= 5, false, true),
          ],
        ),
      ],
    );
  }

  Widget _buildTimelineNode(
      String label, bool isCompleted, bool isFirst, bool isLast) {
    return Expanded(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                  child: Container(
                      height: 2,
                      color: isFirst
                          ? Colors.transparent
                          : (isCompleted
                              ? const Color(0xFFF4B400)
                              : Colors.grey[200]))),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color:
                      isCompleted ? const Color(0xFFF4B400) : Colors.grey[200],
                  shape: BoxShape.circle,
                  border: isCompleted
                      ? Border.all(
                          color: const Color(0xFFF4B400).withOpacity(0.3),
                          width: 4)
                      : null,
                ),
              ),
              Expanded(
                  child: Container(
                      height: 2,
                      color: isLast
                          ? Colors.transparent
                          : (isCompleted
                              ? const Color(0xFFF4B400)
                              : Colors.grey[200]))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal,
              color: isCompleted ? const Color(0xFF121212) : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.all(Radius.circular(2))))),
            const SizedBox(height: 32),
            const Text('ORDER DETAILS',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    fontSize: 16)),
            const SizedBox(height: 24),
            Expanded(
              child: ListView(
                children: [
                  _buildDetailRow(
                      'Recipient', order['recipientName'] ?? 'Customer'),
                  _buildDetailRow('Phone', order['recipientPhone'] ?? 'N/A'),
                  _buildDetailRow(
                      'Address', order['deliveryAddress'] ?? 'No address'),
                  _buildDetailRow('Payment',
                      (order['paymentMethod'] ?? 'COD').toUpperCase()),
                  _buildDetailRow(
                      'Order Time',
                      DateFormat('MMM dd, yyyy - hh:mm a').format(
                          order['createdAt'] != null
                              ? (order['createdAt'] as dynamic).toDate()
                              : DateTime.now())),
                  const Divider(height: 48),
                  const Text('ITEMS',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.grey)),
                  const SizedBox(height: 16),
                  ...((order['items'] as List<dynamic>?) ?? [])
                      .map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${item['name']} x${item['qty'] ?? 1}'),
                                Text(
                                    '₱${((item['price'] ?? 0.0) * (item['qty'] ?? 1)).toStringAsFixed(2)}'),
                              ],
                            ),
                          ))
                      .toList(),
                  if (order['deliveryFee'] != null)
                    _buildDetailRow('Delivery Fee',
                        '₱${(order['deliveryFee'] as num).toStringAsFixed(2)}'),
                  if ((order['proofOfDeliveryPhoto'] ?? order['podPhotoUrl']) !=
                          null &&
                      ((order['proofOfDeliveryPhoto'] ?? order['podPhotoUrl'])
                              as String)
                          .isNotEmpty) ...[
                    const Divider(height: 36),
                    const Row(
                      children: [
                        Icon(Icons.verified, color: Colors.green, size: 18),
                        SizedBox(width: 6),
                        Text('PROOF OF DELIVERY (POD)',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.green)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 160,
                        width: double.infinity,
                        color: Colors.black12,
                        child: _buildImageFromBase64OrUrl(
                            (order['proofOfDeliveryPhoto'] ??
                                order['podPhotoUrl']) as String),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow(
                        'Received By',
                        order['podRecipient'] ??
                            order['recipientName'] ??
                            'Customer'),
                    if (order['courierName'] != null ||
                        order['driverName'] != null)
                      _buildDetailRow('Courier / Driver',
                          order['courierName'] ?? order['driverName']),
                  ],
                  const Divider(height: 48),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TOTAL',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                      Text(
                        '₱${(order['totalAmount'] ?? 0.0).toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 24,
                            color: Color(0xFFF4B400)),
                      ),
                    ],
                  ),
                  if (order['status'] == 'pending')
                    Padding(
                      padding: const EdgeInsets.only(top: 32.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => _confirmCancelOrder(order['id']),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('CANCEL ORDER',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmCancelOrder(String orderId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Order?'),
        content: const Text(
            'Are you sure you want to cancel this order? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('NO')),
          TextButton(
            onPressed: () {
              InventoryData.updateOrderStatus(orderId, 'cancelled');
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close bottom sheet
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Order cancelled successfully'),
                    backgroundColor: Colors.red),
              );
            },
            child:
                const Text('YES, CANCEL', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildImageFromBase64OrUrl(String strData) {
    try {
      if (strData.startsWith('data:image') || strData.contains(';base64,')) {
        final base64Str = strData.split(',').last;
        final bytes = base64Decode(base64Str);
        return Image.memory(bytes, fit: BoxFit.cover);
      } else if (strData.startsWith('http://') ||
          strData.startsWith('https://')) {
        return Image.network(strData,
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) =>
                const Icon(Icons.broken_image, size: 40));
      } else {
        final bytes = base64Decode(strData);
        return Image.memory(bytes, fit: BoxFit.cover);
      }
    } catch (e) {
      return Container(
        color: Colors.grey[800],
        child: const Center(
            child: Icon(Icons.broken_image, color: Colors.white54)),
      );
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold)),
          Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  int min(int a, int b) => a < b ? a : b;
}
