import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'inventory_data.dart';
import 'app_sidebar.dart';

class SalesReportPage extends StatefulWidget {
  final String role;
  const SalesReportPage({super.key, this.role = 'admin'});

  @override
  State<SalesReportPage> createState() => _SalesReportPageState();
}

class _SalesReportPageState extends State<SalesReportPage> {
  String? _filterBranchId = InventoryData.selectedBranchId;

  // --- Mirrors web's status check EXACTLY: only 'completed' or
  // 'delivered' orders count toward revenue. Also checks items[0].status
  // as a fallback, matching the JS's `(o.status || (o.items && o.items[0]
  // ? o.items[0].status : "") || "")`. ---
  bool _countsAsSale(Map<String, dynamic> order) {
    String status = (order['status'] ?? '').toString();
    if (status.isEmpty) {
      final items = order['items'] as List?;
      if (items != null && items.isNotEmpty && items[0] is Map) {
        status = (items[0]['status'] ?? '').toString();
      }
    }
    status = status.toLowerCase();
    return status == 'completed' || status == 'delivered';
  }

  // --- Mirrors web's amount fallback chain EXACTLY:
  // totalAmount -> total_amount -> total_price -> items[0].totalAmount ->
  // items[0].total_amount -> 0 ---
  double _amountOf(Map<String, dynamic> order) {
    if (order['totalAmount'] != null) return (order['totalAmount'] as num).toDouble();
    if (order['total_amount'] != null) return (order['total_amount'] as num).toDouble();
    if (order['total_price'] != null) return (order['total_price'] as num).toDouble();
    final items = order['items'] as List?;
    if (items != null && items.isNotEmpty && items[0] is Map) {
      final first = items[0] as Map;
      if (first['totalAmount'] != null) return (first['totalAmount'] as num).toDouble();
      if (first['total_amount'] != null) return (first['total_amount'] as num).toDouble();
    }
    return 0.0;
  }

  DateTime _dateOf(Map<String, dynamic> order) {
    final raw = order['createdAt'] ?? order['timestamp'];
    if (raw == null) return DateTime.now();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
    try {
      return (raw as dynamic).toDate();
    } catch (_) {
      return DateTime.now();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2A2A2A) : Colors.grey.withValues(alpha: 0.2);
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final isDesktop = MediaQuery.of(context).size.width >= 850;
    final isSuperAdmin = widget.role == 'super-admin';

    return Scaffold(
      backgroundColor: bgColor,
      drawer: isDesktop ? null : Drawer(child: AppSidebar(role: widget.role, currentPage: 'sales_report')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) AppSidebar(role: widget.role, currentPage: 'sales_report'),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  if (!isDesktop)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
                      child: Row(
                        children: [
                          Builder(builder: (ctx) => IconButton(
                            icon: Icon(Icons.menu, color: textColor),
                            onPressed: () => Scaffold.of(ctx).openDrawer(),
                          )),
                          Expanded(
                            child: Text('Sales Report',
                                style: GoogleFonts.cormorantGaramond(color: textColor, fontWeight: FontWeight.bold, fontSize: 22)),
                          ),
                          if (isSuperAdmin)
                            StreamBuilder<List<Map<String, dynamic>>>(
                              stream: InventoryData.getBranchesStream(),
                              builder: (context, snapshot) {
                                final branches = snapshot.data ?? [];
                                return PopupMenuButton<String?>(
                                  icon: Icon(Icons.filter_list_alt, color: textColor),
                                  tooltip: 'Filter by Branch',
                                  onSelected: (val) => setState(() => _filterBranchId = val),
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(value: null, child: Text('All Branches')),
                                    ...branches.map((b) => PopupMenuItem(value: b['id'], child: Text(b['name']))),
                                  ],
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: InventoryData.ordersStream(branchId: _filterBranchId),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(child: Text('Error loading sales data: ${snapshot.error}', style: TextStyle(color: textColor)));
                        }
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)));
                        }

                        final orders = snapshot.data ?? [];

                        final now = DateTime.now();
                        final today = DateTime(now.year, now.month, now.day);
                        // Monday-start week, matching web's exact
                        // `diff = date - day + (day === 0 ? -6 : 1)` logic.
                        final weekday = now.weekday; // 1=Mon..7=Sun
                        final weekStart = today.subtract(Duration(days: weekday - 1));
                        final monthStart = DateTime(now.year, now.month, 1);
                        final yearStart = DateTime(now.year, 1, 1);

                        double daily = 0, weekly = 0, monthly = 0, yearly = 0;

                        // Fixed 7-day slots, matching web's pre-filled
                        // last7Days map — every day shows on the chart
                        // even with zero sales, instead of only days that
                        // happen to have data.
                        final Map<String, Map<String, dynamic>> last7Days = {};
                        for (int i = 6; i >= 0; i--) {
                          final d = today.subtract(Duration(days: i));
                          final key = DateFormat('yyyy-MM-dd').format(d);
                          last7Days[key] = {'label': DateFormat('MMM d').format(d), 'total': 0.0};
                        }

                        // Bonus sections (beyond web parity) — unchanged
                        // in spirit from before, now using the same
                        // _amountOf/_dateOf helpers for consistency.
                        double totalRevenueAllOrders = 0;
                        int totalOrders = orders.length;
                        Map<String, int> flowerPopularity = {};
                        Map<String, int> occasionStats = {};

                        for (final order in orders) {
                          final amount = _amountOf(order);
                          totalRevenueAllOrders += amount;

                          final occasion = order['occasion'] as String? ?? 'Unknown';
                          occasionStats[occasion] = (occasionStats[occasion] ?? 0) + 1;

                          final items = (order['items'] ?? order['flowers'] ?? []) as List<dynamic>;
                          for (var f in items) {
                            if (f is! Map) continue;
                            final name = f['name'] as String? ?? 'Unknown';
                            final qty = (f['qty'] ?? f['quantity'] ?? 1);
                            final parsedQty = qty is num ? qty.toInt() : 1;
                            flowerPopularity[name] = (flowerPopularity[name] ?? 0) + parsedQty;
                          }

                          if (_countsAsSale(order)) {
                            final date = _dateOf(order);
                            if (!date.isBefore(today)) daily += amount;
                            if (!date.isBefore(weekStart)) weekly += amount;
                            if (!date.isBefore(monthStart)) monthly += amount;
                            if (!date.isBefore(yearStart)) yearly += amount;

                            final key = DateFormat('yyyy-MM-dd').format(date);
                            if (last7Days.containsKey(key)) {
                              last7Days[key]!['total'] = (last7Days[key]!['total'] as double) + amount;
                            }
                          }
                        }

                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isDesktop)
                                Text('Sales Report',
                                    style: GoogleFonts.cormorantGaramond(fontSize: 32, fontWeight: FontWeight.bold, color: textColor)),
                              const SizedBox(height: 4),
                              Text('Real-time sales, revenue, and product analytics.',
                                  style: TextStyle(fontSize: 12, color: subTextColor)),
                              const SizedBox(height: 20),

                              // 4 stat cards, matching web's Daily Flux /
                              // Weekly Momentum / Monthly Volume / Annual
                              // Trajectory exactly — same labels, same
                              // color family, same underlying math.
                              LayoutBuilder(builder: (context, constraints) {
                                final cardWidth = constraints.maxWidth < 600
                                    ? (constraints.maxWidth - 12) / 2
                                    : (constraints.maxWidth - 36) / 4;
                                return Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    _statCard('DAILY FLUX', daily, Icons.calendar_today_rounded, const Color(0xFFE91E63), textColor, subTextColor, cardColor, borderColor, cardWidth),
                                    _statCard('WEEKLY MOMENTUM', weekly, Icons.date_range_rounded, const Color(0xFFF39C12), textColor, subTextColor, cardColor, borderColor, cardWidth),
                                    _statCard('MONTHLY VOLUME', monthly, Icons.event_available_rounded, const Color(0xFF7B79F2), textColor, subTextColor, cardColor, borderColor, cardWidth),
                                    _statCard('ANNUAL TRAJECTORY', yearly, Icons.trending_up_rounded, const Color(0xFF00CED1), textColor, subTextColor, cardColor, borderColor, cardWidth),
                                  ],
                                );
                              }),
                              const SizedBox(height: 28),

                              Row(
                                children: [
                                  Icon(Icons.show_chart_rounded, color: const Color(0xFF7B79F2), size: 20),
                                  const SizedBox(width: 8),
                                  Text('Revenue Dynamics', style: GoogleFonts.cormorantGaramond(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                                    child: Text('LIVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: subTextColor, letterSpacing: 0.5)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _buildRevenueChart(last7Days, cardColor, borderColor, textColor, subTextColor),

                              const SizedBox(height: 32),
                              Text('Sales by Occasion', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
                              const SizedBox(height: 12),
                              if (occasionStats.isEmpty)
                                Text('No occasion data available.', style: TextStyle(color: subTextColor, fontSize: 12))
                              else
                                ...occasionStats.entries.map((e) => _popularityRow(e.key, e.value, textColor, subTextColor, isDark)),

                              const SizedBox(height: 32),
                              Text('Popular Flowers', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
                              const SizedBox(height: 12),
                              if (flowerPopularity.isEmpty)
                                Text('No item data available.', style: TextStyle(color: subTextColor, fontSize: 12))
                              else
                                ...flowerPopularity.entries.map((e) => _popularityRow(e.key, e.value, textColor, subTextColor, isDark)),

                              const SizedBox(height: 32),
                              Text('Recent Transactions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
                              const SizedBox(height: 12),
                              ...orders.take(5).map((order) {
                                final date = _dateOf(order);
                                final amount = _amountOf(order);
                                final orderId = order['id']?.toString() ?? 'UNKNOWN';
                                final displayId = orderId.length > 5 ? orderId.substring(0, 5).toUpperCase() : orderId;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: borderColor))),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Order #$displayId', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: textColor)),
                                            Text(DateFormat('MMM dd, hh:mm a').format(date), style: TextStyle(fontSize: 11, color: subTextColor)),
                                          ],
                                        ),
                                      ),
                                      Text('₱${amount.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, double amount, IconData icon, Color accent, Color textColor, Color subTextColor, Color cardColor, Color borderColor, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20), border: Border.all(color: borderColor)),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: subTextColor, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('₱${amount.toStringAsFixed(2)}',
                      style: GoogleFonts.cormorantGaramond(fontSize: 20, fontWeight: FontWeight.w800, color: textColor)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueChart(Map<String, Map<String, dynamic>> last7Days, Color cardColor, Color borderColor, Color textColor, Color subTextColor) {
    final entries = last7Days.entries.toList();
    final maxVal = entries.map((e) => e.value['total'] as double).fold<double>(0, (a, b) => b > a ? b : a);

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: borderColor)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: entries.map((e) {
          final total = e.value['total'] as double;
          final heightFactor = maxVal == 0 ? 0.0 : total / maxVal;
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('₱${total.toStringAsFixed(0)}', style: TextStyle(fontSize: 8, color: subTextColor, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 130 * heightFactor,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xFFE91E63), Color(0xFFF59E0B)]),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Text(e.value['label'], style: TextStyle(fontSize: 9, color: subTextColor, fontWeight: FontWeight.w600)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _popularityRow(String name, int qty, Color textColor, Color subTextColor, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(child: Text(name, style: TextStyle(color: textColor, fontSize: 13), overflow: TextOverflow.ellipsis)),
          Container(
            width: 100,
            height: 8,
            decoration: BoxDecoration(color: (isDark ? Colors.grey[800] : Colors.grey[200]), borderRadius: BorderRadius.circular(4)),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (qty / 50).clamp(0.0, 1.0),
              child: Container(decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(4))),
            ),
          ),
          const SizedBox(width: 12),
          Text(qty.toString(), style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
        ],
      ),
    );
  }
}