import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

import 'inventory_data.dart';
import 'app_sidebar.dart';
import 'invoice_portal_page.dart';

class OrdersPage extends StatefulWidget {
  final String role;
  const OrdersPage({super.key, this.role = 'employee'});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  int _selectedTab = 0;
  final TextEditingController _filterController = TextEditingController();
  String _searchFilter = '';

  String? _selectedBranchId;
  String? _branchName = 'Loading...';

  @override
  void initState() {
    super.initState();
    _initializeBranch();
  }

  Future<void> _initializeBranch() async {
    final user = FirebaseAuth.instance.currentUser;
    final bool isSuperAdmin = widget.role == 'super-admin';

    if (isSuperAdmin) {
      if (mounted) {
        setState(() {
          _selectedBranchId = InventoryData.selectedBranchId;
          _branchName = _selectedBranchId == null ? 'All Branches (Super Admin)' : 'Loading...';
        });
      }
    } else {
      final userData = await InventoryData.getUserData(user?.uid ?? '');
      final bId = userData?['branchId'];
      InventoryData.selectedBranchId = bId;

      if (bId != null) {
        final bDetails = await InventoryData.getBranchDetails(bId);
        if (mounted) {
          setState(() {
            _selectedBranchId = bId;
            _branchName = bDetails?['name'] ?? 'Assigned Branch';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _branchName = 'No Branch Assigned';
          });
        }
      }
    }
  }

  // Mirrors web's isOnlineOrder(o): (o.type || 'WEB') !== 'POS'.
  bool _isOnlineOrder(Map<String, dynamic> o) {
    final type = (o['type'] ?? 'WEB').toString().toUpperCase();
    return type != 'POS';
  }

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
    final user = FirebaseAuth.instance.currentUser;
    final bool isSuperAdmin = widget.role == 'super-admin';
    final effectiveRole = widget.role;
    final isAdmin = effectiveRole == 'admin' || effectiveRole == 'super-admin';

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2A2A2A) : Colors.grey.withValues(alpha: 0.2);
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    final isDesktop = MediaQuery.of(context).size.width >= 850;

    return Scaffold(
      backgroundColor: bgColor,
      drawer: isDesktop ? null : Drawer(
        child: AppSidebar(role: effectiveRole, currentPage: 'orders'),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) AppSidebar(role: effectiveRole, currentPage: 'orders'),

          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: InventoryData.ordersStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error loading orders: ${snapshot.error}', style: TextStyle(color: textColor)),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFF59E0B)),
                  );
                }

                final allOrders = snapshot.data ?? [];

                final onlineOrders = allOrders.where(_isOnlineOrder).toList();
                final walkInOrders = allOrders.where((o) => !_isOnlineOrder(o)).toList();

                final currentList = _selectedTab == 0 ? onlineOrders : walkInOrders;

                final filteredList = currentList.where((o) {
                  if (_searchFilter.trim().isEmpty) return true;
                  final q = _searchFilter.toLowerCase();
                  final customer = (o['recipientName'] ?? o['customerName'] ?? o['customer_name'] ?? '').toString().toLowerCase();
                  final payload = (o['items'] ?? o['flowers'] ?? []).toString().toLowerCase();
                  final id = (o['id'] ?? o['orderId'] ?? '').toString().toLowerCase();
                  return customer.contains(q) || payload.contains(q) || id.contains(q);
                }).toList();

                int commerceVolume = currentList.length;
                int pendingResolution = currentList.where((o) {
                  final st = (o['status'] ?? 'pending').toString().toLowerCase();
                  return st.contains('pending') || st.contains('processing');
                }).length;

                double liquidityPipeline = 0.0;
                for (var o in currentList) {
                  liquidityPipeline += (o['totalAmount'] ?? o['totalPrice'] ?? o['total_amount'] ?? o['total_price'] ?? 0.0).toDouble();
                }

                return CustomScrollView(
                  slivers: [
                    if (!isDesktop)
                      SliverAppBar(
                        backgroundColor: cardColor,
                        iconTheme: IconThemeData(color: textColor),
                        elevation: 0,
                        pinned: true,
                        title: Text(
                          'Orders',
                          style: GoogleFonts.cormorantGaramond(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                          ),
                        ),
                        actions: [
                          IconButton(
                            icon: const Icon(Icons.receipt_long_rounded),
                            tooltip: 'Invoice Portal',
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => InvoicePortalPage(role: widget.role),
                                ),
                              );
                            },
                          ),
                        ],
                      ),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTopBar(cardColor, textColor, subTextColor, borderColor, isDark, isSuperAdmin, user, effectiveRole, isAdmin),
                            const SizedBox(height: 32),

                            if (isDesktop)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Orders',
                                        style: GoogleFonts.cormorantGaramond(
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                          color: textColor,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Track and manage customer orders.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: subTextColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(
                                    width: 260,
                                    height: 42,
                                    child: TextField(
                                      controller: _filterController,
                                      onChanged: (val) => setState(() => _searchFilter = val),
                                      style: TextStyle(fontSize: 13, color: textColor),
                                      decoration: InputDecoration(
                                        hintText: 'Filter Manifests...',
                                        hintStyle: TextStyle(fontSize: 12, color: subTextColor),
                                        prefixIcon: Icon(Icons.search, size: 18, color: subTextColor),
                                        contentPadding: EdgeInsets.zero,
                                        filled: true,
                                        fillColor: isDark ? const Color(0xFF222222) : const Color(0xFFF1F5F9),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: borderColor),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: borderColor),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: const BorderSide(color: Color(0xFFF59E0B)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                            const SizedBox(height: 24),

                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: [
                                  _buildTabBtn(
                                    index: 0,
                                    label: 'Online Orders',
                                    count: onlineOrders.length,
                                    icon: Icons.language,
                                    isDark: isDark,
                                    textColor: textColor,
                                    borderColor: borderColor,
                                    cardColor: cardColor,
                                  ),
                                  const SizedBox(width: 12),
                                  _buildTabBtn(
                                    index: 1,
                                    label: 'Walk-in Orders',
                                    count: walkInOrders.length,
                                    icon: Icons.storefront,
                                    isDark: isDark,
                                    textColor: textColor,
                                    borderColor: borderColor,
                                    cardColor: cardColor,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            Row(
                              children: [
                                _buildMetricBox(
                                  'COMMERCE VOLUME',
                                  '$commerceVolume',
                                  Icons.shopping_bag_outlined,
                                  isDark,
                                  cardColor,
                                  borderColor,
                                  textColor,
                                  subTextColor,
                                ),
                                const SizedBox(width: 16),
                                _buildMetricBox(
                                  'PENDING RESOLUTION',
                                  '$pendingResolution',
                                  Icons.history,
                                  isDark,
                                  cardColor,
                                  borderColor,
                                  textColor,
                                  subTextColor,
                                ),
                                const SizedBox(width: 16),
                                _buildMetricBox(
                                  'LIQUIDITY PIPELINE',
                                  '₱${liquidityPipeline.toStringAsFixed(2)}',
                                  Icons.show_chart,
                                  isDark,
                                  cardColor,
                                  borderColor,
                                  textColor,
                                  subTextColor,
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            Container(
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: borderColor, width: 1.5),
                                boxShadow: [
                                  if (!isDark)
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.02),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      _selectedTab == 0 ? 'Online Orders Log' : 'Walk-in Orders Log',
                                      style: GoogleFonts.cormorantGaramond(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: textColor,
                                      ),
                                    ),
                                  ),
                                  Divider(height: 1, color: borderColor),

                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      return SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        physics: const BouncingScrollPhysics(),
                                        child: SizedBox(
                                          width: max(constraints.maxWidth, 900),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                                color: isDark ? const Color(0xFF222222) : const Color(0xFFF8FAFC),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      flex: 3,
                                                      child: Text(
                                                        'CLIENTELE',
                                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: subTextColor, letterSpacing: 1.0),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 4,
                                                      child: Text(
                                                        'PAYLOAD SUMMARY',
                                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: subTextColor, letterSpacing: 1.0),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 2,
                                                      child: Text(
                                                        'VALUATION',
                                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: subTextColor, letterSpacing: 1.0),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 2,
                                                      child: Text(
                                                        'TIMELINE',
                                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: subTextColor, letterSpacing: 1.0),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 3,
                                                      child: Text(
                                                        _selectedTab == 0 ? 'STATUS' : 'ACTIONS / STATUS',
                                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: subTextColor, letterSpacing: 1.0),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Divider(height: 1, color: borderColor),

                                              if (filteredList.isEmpty)
                                                Container(
                                                  height: 160,
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    'No manifests found in this section.',
                                                    style: TextStyle(color: subTextColor, fontSize: 13, fontStyle: FontStyle.italic),
                                                  ),
                                                )
                                              else
                                                ListView.separated(
                                                  shrinkWrap: true,
                                                  physics: const NeverScrollableScrollPhysics(),
                                                  itemCount: filteredList.length,
                                                  separatorBuilder: (context, index) => Divider(
                                                    height: 1,
                                                    color: borderColor,
                                                  ),
                                                  itemBuilder: (context, index) {
                                                    final order = filteredList[index];
                                                    final orderId = (order['id'] ?? order['orderId'] ?? '').toString();
                                                    final customerName = (order['recipientName'] ?? order['customerName'] ?? order['customer_name'] ?? 'Walk-in Customer').toString();

                                                    final rawItems = order['items'] ?? order['flowers'] ?? [];
                                                    List<String> itemSummaries = [];
                                                    if (rawItems is List) {
                                                      for (var item in rawItems) {
                                                        if (item is Map) {
                                                          final name = item['name'] ?? 'Item';
                                                          final qty = item['qty'] ?? item['quantity'] ?? 1;
                                                          itemSummaries.add('$name ($qty)');
                                                        }
                                                      }
                                                    }
                                                    final payloadSummary = itemSummaries.isNotEmpty
                                                        ? itemSummaries.join(', ')
                                                        : (order['occasion'] ?? 'Custom Order Bouquet');

                                                    final totalValuation = (order['totalAmount'] ?? order['totalPrice'] ?? order['total_amount'] ?? order['total_price'] ?? 0.0).toDouble();

                                                    final rawDate = order['createdAt'] ?? order['timestamp'];
                                                    DateTime date = DateTime.now();
                                                    if (rawDate is Timestamp) {
                                                      date = rawDate.toDate();
                                                    } else if (rawDate is String) {
                                                      date = DateTime.tryParse(rawDate) ?? DateTime.now();
                                                    }
                                                    final timelineStr = DateFormat('M/d/yyyy').format(date);

                                                    final currentStatus = (order['status'] ?? 'PENDING').toString().toUpperCase();

                                                    return Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                                                      child: Row(
                                                        children: [
                                                          Expanded(
                                                            flex: 3,
                                                            child: Row(
                                                              children: [
                                                                CircleAvatar(
                                                                  radius: 16,
                                                                  backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                                                  child: Text(
                                                                    customerName.isNotEmpty ? customerName[0].toUpperCase() : 'C',
                                                                    style: const TextStyle(
                                                                      fontSize: 12,
                                                                      fontWeight: FontWeight.bold,
                                                                      color: Color(0xFFF59E0B),
                                                                    ),
                                                                  ),
                                                                ),
                                                                const SizedBox(width: 12),
                                                                Expanded(
                                                                  child: Text(
                                                                    customerName,
                                                                    style: TextStyle(
                                                                      fontWeight: FontWeight.bold,
                                                                      fontSize: 13,
                                                                      color: textColor,
                                                                    ),
                                                                    overflow: TextOverflow.ellipsis,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          Expanded(
                                                            flex: 4,
                                                            child: Padding(
                                                              padding: const EdgeInsets.only(right: 12.0),
                                                              child: Text(
                                                                payloadSummary,
                                                                style: TextStyle(
                                                                  fontSize: 12,
                                                                  color: subTextColor,
                                                                ),
                                                                overflow: TextOverflow.ellipsis,
                                                                maxLines: 2,
                                                              ),
                                                            ),
                                                          ),
                                                          Expanded(
                                                            flex: 2,
                                                            child: Text(
                                                              '₱${totalValuation.toStringAsFixed(2)}',
                                                              style: TextStyle(
                                                                fontWeight: FontWeight.bold,
                                                                fontSize: 13,
                                                                color: textColor,
                                                              ),
                                                            ),
                                                          ),
                                                          Expanded(
                                                            flex: 2,
                                                            child: Text(
                                                              timelineStr,
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                color: subTextColor,
                                                              ),
                                                            ),
                                                          ),
                                                          Expanded(
                                                            flex: 3,
                                                            child: _selectedTab == 0
                                                                ? Container(
                                                              height: 36,
                                                              padding: const EdgeInsets.symmetric(horizontal: 10),
                                                              decoration: BoxDecoration(
                                                                color: isDark ? const Color(0xFF222222) : const Color(0xFFF1F5F9),
                                                                borderRadius: BorderRadius.circular(8),
                                                                border: Border.all(color: borderColor),
                                                              ),
                                                              child: DropdownButtonHideUnderline(
                                                                child: DropdownButton<String>(
                                                                  value: ['PENDING', 'PROCESSING', 'IN TRANSIT'].contains(currentStatus)
                                                                      ? currentStatus
                                                                      : 'PENDING',
                                                                  dropdownColor: cardColor,
                                                                  isExpanded: true,
                                                                  icon: Icon(Icons.keyboard_arrow_down, color: subTextColor, size: 18),
                                                                  style: TextStyle(
                                                                    color: textColor,
                                                                    fontSize: 11,
                                                                    fontWeight: FontWeight.w600,
                                                                  ),
                                                                  items: const [
                                                                    DropdownMenuItem(value: 'PENDING', child: Text('PENDING')),
                                                                    DropdownMenuItem(value: 'PROCESSING', child: Text('PROCESSING')),
                                                                    DropdownMenuItem(value: 'IN TRANSIT', child: Text('IN TRANSIT')),
                                                                  ],
                                                                  onChanged: (val) {
                                                                    if (val != null) _updateOrderStatus(orderId, val);
                                                                  },
                                                                ),
                                                              ),
                                                            )
                                                                : Row(
                                                              children: [
                                                                if (currentStatus == 'CANCELLED')
                                                                  Container(
                                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                                    decoration: BoxDecoration(
                                                                      color: Colors.red.withValues(alpha: 0.1),
                                                                      borderRadius: BorderRadius.circular(6),
                                                                    ),
                                                                    child: const Text(
                                                                      'CANCELLED',
                                                                      style: TextStyle(
                                                                        fontSize: 10,
                                                                        fontWeight: FontWeight.bold,
                                                                        color: Colors.red,
                                                                      ),
                                                                    ),
                                                                  )
                                                                else if (currentStatus == 'COMPLETED')
                                                                  Container(
                                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                                    decoration: BoxDecoration(
                                                                      color: Colors.green.withValues(alpha: 0.1),
                                                                      borderRadius: BorderRadius.circular(6),
                                                                    ),
                                                                    child: const Text(
                                                                      'COMPLETED',
                                                                      style: TextStyle(
                                                                        fontSize: 10,
                                                                        fontWeight: FontWeight.bold,
                                                                        color: Colors.green,
                                                                      ),
                                                                    ),
                                                                  )
                                                                else ...[
                                                                    ElevatedButton(
                                                                      onPressed: () => _updateOrderStatus(orderId, 'COMPLETED'),
                                                                      style: ElevatedButton.styleFrom(
                                                                        backgroundColor: Colors.green[600],
                                                                        foregroundColor: Colors.white,
                                                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                                        minimumSize: Size.zero,
                                                                        elevation: 0,
                                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                                      ),
                                                                      child: const Text('CONFIRM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                                                    ),
                                                                    const SizedBox(width: 8),
                                                                    OutlinedButton(
                                                                      onPressed: () => _updateOrderStatus(orderId, 'CANCELLED'),
                                                                      style: OutlinedButton.styleFrom(
                                                                        foregroundColor: Colors.redAccent,
                                                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                                        minimumSize: Size.zero,
                                                                        side: const BorderSide(color: Colors.redAccent),
                                                                        elevation: 0,
                                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                                      ),
                                                                      child: const Text('CANCEL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
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
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40.0),
                        child: Center(
                          child: Text(
                            '© 2026 BloomyPro Inventory System',
                            style: TextStyle(color: subTextColor, fontSize: 10),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- Top Navigation Bar (dropdown crash-guarded + live profile data) ---
  Widget _buildTopBar(Color cardColor, Color textColor, Color subTextColor, Color borderColor, bool isDark, bool isSuperAdmin, User? user, String role, bool isAdmin) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          if (!isDark)
            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: isSuperAdmin
                ? StreamBuilder<List<Map<String, dynamic>>>(
              stream: InventoryData.getBranchesStream(),
              builder: (context, snapshot) {
                final branches = snapshot.data ?? [];

                final bool selectedExists =
                    _selectedBranchId != null &&
                        branches.any((b) => b['id'] == _selectedBranchId);
                final String? safeValue = selectedExists ? _selectedBranchId : null;

                return DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: safeValue,
                    isExpanded: true,
                    hint: Text(
                      _branchName ?? 'All Branches',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                    icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFFF59E0B)),
                    dropdownColor: cardColor,
                    onChanged: (branchId) {
                      setState(() {
                        _selectedBranchId = branchId;
                        InventoryData.selectedBranchId = branchId;
                        if (branchId == null) {
                          _branchName = 'All Branches (Super Admin)';
                        } else {
                          final branch = branches.firstWhere((b) => b['id'] == branchId);
                          _branchName = branch['name'];
                        }
                      });
                    },
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Branches')),
                      ...branches.map((b) => DropdownMenuItem(
                        value: b['id'] as String,
                        child: Text(b['name'] as String),
                      )),
                    ],
                  ),
                );
              },
            )
                : Text(
              _branchName ?? '',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(width: 12),
          Icon(Icons.notifications_none_rounded, color: subTextColor, size: 20),
          const SizedBox(width: 12),
          Container(height: 20, width: 1, color: borderColor),
          const SizedBox(width: 12),

          StreamBuilder<DocumentSnapshot>(
            stream: user != null
                ? FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots()
                : null,
            builder: (context, snapshot) {
              final userData = snapshot.data?.data() as Map<String, dynamic>?;
              final firstName = (userData?['firstName'] ?? '').toString();
              final displayName = firstName.isNotEmpty
                  ? firstName
                  : (user?.email?.split('@')[0] ?? (isAdmin ? 'Admin' : 'Staff'));
              final photoUrl = (userData?['photoUrl'] ?? '').toString();
              final avatarLetter = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'A';

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          displayName,
                          style: GoogleFonts.inter(
                            color: textColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          role.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.0,
                            fontWeight: FontWeight.w600,
                            color: subTextColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  CircleAvatar(
                    backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    radius: 16,
                    backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                    child: photoUrl.isEmpty
                        ? Text(avatarLetter, style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 12))
                        : null,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // --- Shared Metric Component ---
  Widget _buildMetricBox(
      String label,
      String value,
      IconData icon,
      bool isDark,
      Color cardColor,
      Color borderColor,
      Color textColor,
      Color subTextColor,
      ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: subTextColor,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
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

  // --- Shared Tab Button ---
  Widget _buildTabBtn({
    required int index,
    required String label,
    required int count,
    required IconData icon,
    required bool isDark,
    required Color textColor,
    required Color borderColor,
    required Color cardColor,
  }) {
    final bool isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF59E0B).withValues(alpha: 0.1) : cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFF59E0B) : borderColor,
            width: isSelected ? 1.5 : 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? const Color(0xFFF59E0B) : Colors.grey),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? const Color(0xFFF59E0B) : textColor,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFF59E0B) : Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}