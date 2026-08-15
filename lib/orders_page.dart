import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'inventory_data.dart';
import 'invoice_portal_page.dart';

class OrdersPage extends StatefulWidget {
  final String role;
  const OrdersPage({super.key, this.role = 'employee'});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  int _selectedTab = 0; // 0 = Online Orders, 1 = Walk-in Orders
  final TextEditingController _filterController = TextEditingController();
  String _searchFilter = '';

  Future<void> _updateOrderStatus(String orderId, String newStatus) async {
    try {
      await FirebaseFirestore.instance.collection('orders').doc(orderId).set({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order status updated to "$newStatus"'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e')),
        );
      }
    }
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
          'Orders',
          style: GoogleFonts.cormorantGaramond(
              fontWeight: FontWeight.bold, fontSize: 24),
        ),
        backgroundColor: isDark ? Colors.black : const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_rounded),
            tooltip: 'Invoice Portal',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => InvoicePortalPage(role: widget.role)),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: InventoryData.ordersStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
                child: Text('Error loading orders: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFFF59E0B)));
          }

          final allOrders = snapshot.data ?? [];

          // Separate online vs walk-in orders
          final onlineOrders = allOrders.where((o) {
            final orderType =
                (o['orderType'] ?? o['type'] ?? '').toString().toUpperCase();
            return !orderType.contains('WALK_IN');
          }).toList();

          final walkInOrders = allOrders.where((o) {
            final orderType =
                (o['orderType'] ?? o['type'] ?? '').toString().toUpperCase();
            return orderType.contains('WALK_IN');
          }).toList();

          final currentList = _selectedTab == 0 ? onlineOrders : walkInOrders;

          // Filter current list
          final filteredList = currentList.where((o) {
            if (_searchFilter.trim().isEmpty) return true;
            final q = _searchFilter.toLowerCase();
            final customer = (o['recipientName'] ?? o['customerName'] ?? '')
                .toString()
                .toLowerCase();
            final payload =
                (o['items'] ?? o['flowers'] ?? []).toString().toLowerCase();
            final id = (o['id'] ?? o['orderId'] ?? '').toString().toLowerCase();
            return customer.contains(q) ||
                payload.contains(q) ||
                id.contains(q);
          }).toList();

          // Metrics
          int commerceVolume = currentList.length;
          int pendingResolution = currentList.where((o) {
            final st = (o['status'] ?? 'pending').toString().toLowerCase();
            return st.contains('pending') || st.contains('processing');
          }).length;

          double liquidityPipeline = 0.0;
          for (var o in currentList) {
            liquidityPipeline +=
                (o['totalAmount'] ?? o['totalPrice'] ?? 0.0).toDouble();
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header & Filter Bar Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Orders',
                            style: GoogleFonts.cormorantGaramond(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Track and manage customer orders.',
                            style: TextStyle(
                              fontSize: 13,
                              color:
                                  isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Search Filter
                    SizedBox(
                      width: 240,
                      height: 40,
                      child: TextField(
                        controller: _filterController,
                        onChanged: (val) => setState(() => _searchFilter = val),
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Filter Manifests...',
                          hintStyle:
                              TextStyle(fontSize: 11, color: Colors.grey[400]),
                          prefixIcon: const Icon(Icons.search,
                              size: 16, color: Colors.grey),
                          contentPadding: EdgeInsets.zero,
                          filled: true,
                          fillColor: isDark ? Colors.grey[900] : Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide:
                                BorderSide(color: Colors.grey.withOpacity(0.2)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide:
                                BorderSide(color: Colors.grey.withOpacity(0.2)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Order Type Selector Tabs (Online Orders vs Walk-in Orders) - Matching Screenshot 4
                Row(
                  children: [
                    _buildTabBtn(
                      index: 0,
                      label: 'Online Orders',
                      count: onlineOrders.length,
                      icon: Icons.language,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 12),
                    _buildTabBtn(
                      index: 1,
                      label: 'Walk-in Orders',
                      count: walkInOrders.length,
                      icon: Icons.storefront,
                      isDark: isDark,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Metrics Row (Commerce Volume, Pending Resolution, Liquidity Pipeline)
                Row(
                  children: [
                    _buildMetricBox('COMMERCE VOLUME', '$commerceVolume',
                        Icons.shopping_bag_outlined, isDark),
                    const SizedBox(width: 16),
                    _buildMetricBox('PENDING RESOLUTION', '$pendingResolution',
                        Icons.history, isDark),
                    const SizedBox(width: 16),
                    _buildMetricBox(
                        'LIQUIDITY PIPELINE',
                        '₱${liquidityPipeline.toStringAsFixed(2)}',
                        Icons.show_chart,
                        isDark),
                  ],
                ),
                const SizedBox(height: 24),

                // Orders Table Container
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[900] : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.withOpacity(0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          _selectedTab == 0
                              ? 'Online Orders Log'
                              : 'Walk-in Orders Log',
                          style: GoogleFonts.cormorantGaramond(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Divider(height: 1),

                      // Table Header
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        color:
                            isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                        child: Row(
                          children: [
                            const Expanded(
                                flex: 3,
                                child: Text('CLIENTELE',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey))),
                            const Expanded(
                                flex: 4,
                                child: Text('PAYLOAD SUMMARY',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey))),
                            const Expanded(
                                flex: 2,
                                child: Text('VALUATION',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey))),
                            const Expanded(
                                flex: 2,
                                child: Text('TIMELINE',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey))),
                            Expanded(
                                flex: 3,
                                child: Text(
                                    _selectedTab == 0
                                        ? 'STATUS'
                                        : 'ACTIONS / STATUS',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey))),
                          ],
                        ),
                      ),
                      const Divider(height: 1),

                      if (filteredList.isEmpty)
                        Container(
                          height: 160,
                          alignment: Alignment.center,
                          child: Text(
                            'No manifests found in this section.',
                            style: TextStyle(
                                color: Colors.grey[400], fontSize: 13),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filteredList.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final order = filteredList[index];
                            final orderId =
                                (order['id'] ?? order['orderId'] ?? '')
                                    .toString();
                            final customerName = (order['recipientName'] ??
                                    order['customerName'] ??
                                    'Walk-in Customer')
                                .toString();

                            // Build Payload Summary
                            final rawItems =
                                order['items'] ?? order['flowers'] ?? [];
                            List<String> itemSummaries = [];
                            if (rawItems is List) {
                              for (var item in rawItems) {
                                if (item is Map) {
                                  final name = item['name'] ?? 'Item';
                                  final qty =
                                      item['qty'] ?? item['quantity'] ?? 1;
                                  itemSummaries.add('$name ($qty)');
                                }
                              }
                            }
                            final payloadSummary = itemSummaries.isNotEmpty
                                ? itemSummaries.join(', ')
                                : (order['occasion'] ?? 'Custom Order Bouquet');

                            final totalValuation = (order['totalAmount'] ??
                                    order['totalPrice'] ??
                                    0.0)
                                .toDouble();

                            final rawDate = order['createdAt'];
                            DateTime date = DateTime.now();
                            if (rawDate is Timestamp) {
                              date = rawDate.toDate();
                            } else if (rawDate is String) {
                              date =
                                  DateTime.tryParse(rawDate) ?? DateTime.now();
                            }
                            final timelineStr =
                                DateFormat('M/d/yyyy').format(date);

                            final currentStatus = (order['status'] ?? 'PENDING')
                                .toString()
                                .toUpperCase();

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 16),
                              child: Row(
                                children: [
                                  // CLIENTELE
                                  Expanded(
                                    flex: 3,
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor:
                                              Colors.pink.withOpacity(0.1),
                                          child: Text(
                                            customerName.isNotEmpty
                                                ? customerName[0].toUpperCase()
                                                : 'C',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.pink),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            customerName,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // PAYLOAD SUMMARY
                                  Expanded(
                                    flex: 4,
                                    child: Text(
                                      payloadSummary,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? Colors.grey[300]
                                              : Colors.grey[800]),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                  ),

                                  // VALUATION
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      '₱${totalValuation.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ),

                                  // TIMELINE
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      timelineStr,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600]),
                                    ),
                                  ),

                                  // STATUS / ACTIONS
                                  Expanded(
                                    flex: 3,
                                    child: _selectedTab == 0
                                        ? // ONLINE ORDERS: Dropdown with only PENDING, PROCESSING, IN TRANSIT
                                        // NO Cancel button (customer cancels), NO Delivered option (rider confirms POD)
                                        Container(
                                            height: 36,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF2563EB),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: DropdownButtonHideUnderline(
                                              child: DropdownButton<String>(
                                                value: [
                                                  'PENDING',
                                                  'PROCESSING',
                                                  'IN TRANSIT'
                                                ].contains(currentStatus)
                                                    ? currentStatus
                                                    : 'PENDING',
                                                dropdownColor:
                                                    const Color(0xFF1E293B),
                                                icon: const Icon(
                                                    Icons.arrow_drop_down,
                                                    color: Colors.white),
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.bold),
                                                items: const [
                                                  DropdownMenuItem(
                                                      value: 'PENDING',
                                                      child: Text('PENDING')),
                                                  DropdownMenuItem(
                                                      value: 'PROCESSING',
                                                      child:
                                                          Text('PROCESSING')),
                                                  DropdownMenuItem(
                                                      value: 'IN TRANSIT',
                                                      child:
                                                          Text('IN TRANSIT')),
                                                ],
                                                onChanged: (val) {
                                                  if (val != null)
                                                    _updateOrderStatus(
                                                        orderId, val);
                                                },
                                              ),
                                            ),
                                          )
                                        : // WALK-IN ORDERS: Can confirm / complete or cancel directly!
                                        Row(
                                            children: [
                                              if (currentStatus == 'CANCELLED')
                                                Container(
                                                  padding: const EdgeInsets
                                                          .symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red
                                                        .withOpacity(0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                  ),
                                                  child: const Text('CANCELLED',
                                                      style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.red)),
                                                )
                                              else if (currentStatus ==
                                                  'COMPLETED')
                                                Container(
                                                  padding: const EdgeInsets
                                                          .symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green
                                                        .withOpacity(0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                  ),
                                                  child: const Text('COMPLETED',
                                                      style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.green)),
                                                )
                                              else ...[
                                                ElevatedButton(
                                                  onPressed: () =>
                                                      _updateOrderStatus(
                                                          orderId, 'COMPLETED'),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.green[700],
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding: const EdgeInsets
                                                            .symmetric(
                                                        horizontal: 10,
                                                        vertical: 8),
                                                    minimumSize: Size.zero,
                                                  ),
                                                  child: const Text('CONFIRM',
                                                      style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold)),
                                                ),
                                                const SizedBox(width: 6),
                                                OutlinedButton(
                                                  onPressed: () =>
                                                      _updateOrderStatus(
                                                          orderId, 'CANCELLED'),
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                    foregroundColor: Colors.red,
                                                    padding: const EdgeInsets
                                                            .symmetric(
                                                        horizontal: 10,
                                                        vertical: 8),
                                                    minimumSize: Size.zero,
                                                    side: const BorderSide(
                                                        color: Colors.red),
                                                  ),
                                                  child: const Text('CANCEL',
                                                      style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold)),
                                                ),
                                              ],
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
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabBtn({
    required int index,
    required String label,
    required int count,
    required IconData icon,
    required bool isDark,
  }) {
    final bool isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFF7ED)
              : (isDark ? Colors.grey[900] : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF59E0B)
                : Colors.grey.withOpacity(0.2),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: isSelected ? const Color(0xFFF59E0B) : Colors.grey),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? const Color(0xFFF59E0B)
                    : (isDark ? Colors.grey[300] : Colors.grey[700]),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFF59E0B) : Colors.grey[200],
                shape: BoxShape.circle,
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricBox(
      String label, String value, IconData icon, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.white,
          borderRadius: BorderRadius.circular(16),
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
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: const Color(0xFFF59E0B), size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
