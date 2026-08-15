import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'inventory_data.dart';
import 'package:intl/intl.dart';

class SalesReportPage extends StatefulWidget {
  final String role;
  const SalesReportPage({super.key, this.role = 'admin'});

  @override
  State<SalesReportPage> createState() => _SalesReportPageState();
}

class _SalesReportPageState extends State<SalesReportPage> {
  String? _filterBranchId =
      InventoryData.selectedBranchId; // Local filter state

  @override
  Widget build(BuildContext context) {
    // Super Admin can see all or filter by branch
    final isSuperAdmin = widget.role == 'super-admin';

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8DC),
      appBar: AppBar(
        title: const Text('Sales Report',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (isSuperAdmin)
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: InventoryData.getBranchesStream(),
              builder: (context, snapshot) {
                final branches = snapshot.data ?? [];
                return PopupMenuButton<String?>(
                  icon: const Icon(Icons.filter_list_alt),
                  tooltip: 'Filter by Branch',
                  onSelected: (val) => setState(() => _filterBranchId = val),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                        value: null, child: Text('All Branches')),
                    ...branches.map((b) => PopupMenuItem(
                          value: b['id'],
                          child: Text(b['name']),
                        )),
                  ],
                );
              },
            ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: InventoryData.ordersStream(branchId: _filterBranchId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text('Error loading sales data: ${snapshot.error}',
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No sales data available.'));
          }

          try {
            final orders = snapshot.data!;

            // Calculate stats
            double totalRevenue = 0;
            int totalOrders = orders.length;
            Map<String, double> dailySales = {};
            Map<String, int> flowerPopularity = {};
            Map<String, int> occasionStats = {};

            for (var order in orders) {
              final price = (order['totalAmount'] ?? order['totalPrice'] ?? 0.0)
                  .toDouble();
              totalRevenue += price;

              // Occasion stats
              final occasion = order['occasion'] as String? ?? 'Unknown';
              occasionStats[occasion] = (occasionStats[occasion] ?? 0) + 1;

              DateTime date;
              if (order['createdAt'] != null) {
                if (order['createdAt'] is DateTime) {
                  date = order['createdAt'];
                } else if (order['createdAt'] is String) {
                  date =
                      DateTime.tryParse(order['createdAt']) ?? DateTime.now();
                } else {
                  try {
                    date = (order['createdAt'] as dynamic).toDate();
                  } catch (_) {
                    date = DateTime.now();
                  }
                }
              } else {
                date = DateTime.now();
              }

              final dayKey = DateFormat('yyyy-MM-dd').format(date);
              dailySales[dayKey] = (dailySales[dayKey] ?? 0) + price;

              final items =
                  (order['items'] ?? order['flowers'] ?? []) as List<dynamic>;
              for (var f in items) {
                final name = f['name'] as String? ?? 'Unknown';
                final qty = (f['qty'] ?? f['quantity'] ?? 1) as int;
                flowerPopularity[name] = (flowerPopularity[name] ?? 0) + qty;
              }
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary Cards
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                            'Total Revenue',
                            '₱${totalRevenue.toStringAsFixed(2)}',
                            Icons.payments,
                            Colors.green),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                            'Total Orders',
                            totalOrders.toString(),
                            Icons.shopping_basket,
                            Colors.blue),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Daily Sales Chart (Simple)
                  const Text('Daily Sales Trend',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _buildSimpleChart(dailySales),
                  const SizedBox(height: 32),

                  // Occasion Breakdown
                  const Text('Sales by Occasion',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  if (occasionStats.isEmpty)
                    const Text('No occasion data available.',
                        style: TextStyle(color: Colors.grey, fontSize: 12))
                  else
                    ...occasionStats.entries
                        .map((e) => _buildPopularityRow(e.key, e.value))
                        .toList(),

                  const SizedBox(height: 32),

                  // Popular Flowers
                  const Text('Popular Flowers',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  if (flowerPopularity.isEmpty)
                    const Text('No item data available.',
                        style: TextStyle(color: Colors.grey, fontSize: 12))
                  else
                    ...flowerPopularity.entries
                        .map((e) => _buildPopularityRow(e.key, e.value))
                        .toList(),

                  const SizedBox(height: 32),
                  const Text('Recent Transactions',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  ...orders.take(5).map((order) {
                    DateTime date;
                    if (order['createdAt'] != null) {
                      if (order['createdAt'] is DateTime) {
                        date = order['createdAt'];
                      } else if (order['createdAt'] is String) {
                        date = DateTime.tryParse(order['createdAt']) ??
                            DateTime.now();
                      } else {
                        try {
                          date = (order['createdAt'] as dynamic).toDate();
                        } catch (_) {
                          date = DateTime.now();
                        }
                      }
                    } else {
                      date = DateTime.now();
                    }
                    final price =
                        (order['totalAmount'] ?? order['totalPrice'] ?? 0.0)
                            .toDouble();
                    final orderId = order['id']?.toString() ?? 'UNKNOWN';
                    final displayId = orderId.length > 5
                        ? orderId.substring(0, 5).toUpperCase()
                        : orderId;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Order #$displayId'),
                      subtitle:
                          Text(DateFormat('MMM dd, hh:mm a').format(date)),
                      trailing: Text('₱${price.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    );
                  }).toList(),
                ],
              ),
            );
          } catch (e) {
            return Center(child: Text('Error processing data: $e'));
          }
        },
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSimpleChart(Map<String, double> data) {
    if (data.isEmpty) return const SizedBox();

    final sortedKeys = data.keys.toList()..sort();
    final maxVal = data.values.reduce((a, b) => a > b ? a : b);

    return Container(
      height: 150,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: sortedKeys.map((key) {
          final val = data[key]!;
          final heightFactor = maxVal == 0 ? 0.0 : val / maxVal;
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 80 * heightFactor,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  key.substring(5), // MM-DD
                  style: const TextStyle(fontSize: 8, color: Colors.grey),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPopularityRow(String name, int qty) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(child: Text(name)),
          Container(
            width: 100,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (qty / 50)
                  .clamp(0.0, 1.0), // Arbitrary max 50 for visualization
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(qty.toString(),
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
