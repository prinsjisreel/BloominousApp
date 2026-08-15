import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'inventory_data.dart';
import 'inventory_page.dart';
import 'pos_scanner_page.dart';
import 'profile_page.dart';
import 'orders_page.dart';
import 'sales_report_page.dart';
import 'settings_page.dart';
import 'low_stock_alerts_page.dart';
import 'spoilage_tracker_page.dart';
import 'manage_employees_page.dart';
import 'barcode_generator_page.dart';
import 'kiri_generator_page.dart';
import 'freshness_matrix_page.dart';
import 'preorder_reservations_page.dart';
import 'fraud_analytics_page.dart';
import 'sales_anomalies_page.dart';
import 'delivery_status_page.dart';
import 'invoice_portal_page.dart';

class AdminDashboard extends StatefulWidget {
  final String role;
  const AdminDashboard({super.key, this.role = 'employee'});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
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
      InventoryData.selectedBranchId = null;
      if (mounted)
        setState(() {
          _branchName = 'All Branches (Super Admin)';
        });
    } else {
      final userData = await InventoryData.getUserData(user?.uid ?? '');
      final bId = userData?['branchId'];
      InventoryData.selectedBranchId = bId;

      if (bId != null) {
        final bDetails = await InventoryData.getBranchDetails(bId);
        if (mounted)
          setState(() {
            _selectedBranchId = bId;
            _branchName = bDetails?['name'] ?? 'Assigned Branch';
          });
      } else {
        if (mounted)
          setState(() {
            _branchName = 'No Branch Assigned';
          });
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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200.0,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: isDark ? Colors.black : const Color(0xFF121212),
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: true,
              title: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    effectiveRole == 'super-admin'
                        ? 'SUPER ADMIN'
                        : (isAdmin ? 'ADMIN DASHBOARD' : 'STAFF PORTAL'),
                    style: GoogleFonts.inter(
                      color: const Color(0xFFF59E0B),
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      letterSpacing: 2.0,
                    ),
                  ),
                  Text(
                    _branchName ?? '',
                    style: GoogleFonts.inter(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      isDark ? Colors.black : const Color(0xFF121212),
                      isDark
                          ? Colors.black.withOpacity(0.8)
                          : const Color(0xFF121212).withOpacity(0.8),
                    ],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Image.asset(
                            'assets/images/logo.jpg',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.business_center,
                                    color: Color(0xFFF59E0B)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Welcome, ${user?.email?.split('@')[0] ?? (isAdmin ? 'Admin' : 'Staff')}',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              if (isSuperAdmin)
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: InventoryData.getBranchesStream(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox();
                    final branches = snapshot.data!;
                    return PopupMenuButton<String?>(
                      icon: const Icon(Icons.filter_list_rounded,
                          color: Color(0xFFF59E0B)),
                      onSelected: (branchId) {
                        setState(() {
                          _selectedBranchId = branchId;
                          InventoryData.selectedBranchId = branchId;
                          if (branchId == null) {
                            _branchName = 'All Branches (Super Admin)';
                          } else {
                            final branch =
                                branches.firstWhere((b) => b['id'] == branchId);
                            _branchName = branch['name'];
                          }
                        });
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: null,
                          child: Text('All Branches'),
                        ),
                        ...branches.map((b) => PopupMenuItem(
                              value: b['id'] as String,
                              child: Text(b['name'] as String),
                            )),
                      ],
                    );
                  },
                ),
              IconButton(
                icon:
                    const Icon(Icons.logout_rounded, color: Color(0xFFF59E0B)),
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'BUSINESS SUMMARY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _buildStatCardStream(
                          title: 'Inventory',
                          icon: Icons.inventory_2_rounded,
                          color: Colors.blue,
                          stream: InventoryData.inventoryStream(),
                          calculator: (data) => data.length.toString(),
                        ),
                        _buildStatCardStream(
                          title: 'Total Sales',
                          icon: Icons.payments_rounded,
                          color: Colors.green,
                          stream: InventoryData.ordersStream(),
                          calculator: (data) {
                            double total = 0;
                            for (var o in data) {
                              total += (o['totalAmount'] ??
                                      (o['total_amount'] ?? 0.0))
                                  .toDouble();
                            }
                            return '₱${total.toStringAsFixed(0)}';
                          },
                        ),
                        _buildStatCardStream(
                          title: 'Low Stock',
                          icon: Icons.warning_amber_rounded,
                          color: Colors.orange,
                          stream: InventoryData.lowStockStream(),
                          calculator: (data) => data.length.toString(),
                        ),
                        _buildStatCardStream(
                          title: 'Spoilage',
                          icon: Icons.delete_outline_rounded,
                          color: Colors.red,
                          stream: InventoryData.spoilageStream(),
                          calculator: (data) => data.length.toString(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(24.0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
                childAspectRatio: 1.1,
              ),
              delegate: SliverChildListDelegate([
                _buildMenuCard(context, 'POS Scanner',
                    Icons.qr_code_scanner_rounded, const POSScannerPage()),
                _buildMenuCard(context, 'Inventory', Icons.inventory_2_rounded,
                    InventoryPage(role: effectiveRole)),
                _buildMenuCard(
                    context,
                    'Freshness Matrix',
                    Icons.health_and_safety_rounded,
                    const FreshnessMatrixPage()),
                _buildMenuCard(context, 'Barcode Gen', Icons.barcode_reader,
                    const BarcodeGeneratorPage()),
                _buildMenuCard(
                    context,
                    'Orders',
                    Icons.shopping_cart_checkout_rounded,
                    OrdersPage(role: effectiveRole)),
                _buildMenuCard(context, 'Delivery Status',
                    Icons.local_shipping_rounded, const DeliveryStatusPage()),
                _buildMenuCard(
                    context,
                    'Invoice Portal',
                    Icons.receipt_long_rounded,
                    InvoicePortalPage(role: effectiveRole)),
                _buildMenuCard(context, 'Spoilage Tracker',
                    Icons.delete_sweep_rounded, const SpoilageTrackerPage()),
                _buildMenuCard(
                    context,
                    '3D Realism Hub',
                    Icons.auto_awesome_mosaic_rounded,
                    const KiriGeneratorPage()),
                _buildMenuCard(
                    context,
                    'AI Stock Alerts',
                    Icons.notification_important_rounded,
                    const LowStockAlertsPage()),
                _buildMenuCard(context, 'Profile', Icons.person_pin_rounded,
                    const ProfilePage()),
                if (isAdmin)
                  _buildMenuCard(
                      context,
                      'Sales Report',
                      Icons.analytics_rounded,
                      SalesReportPage(role: effectiveRole)),
                if (isAdmin)
                  _buildMenuCard(
                      context,
                      'Manage Employees',
                      Icons.badge_rounded,
                      ManageEmployeesPage(role: effectiveRole)),
                if (isAdmin) ...[
                  _buildMenuCard(context, 'Pre-Orders',
                      Icons.pending_actions_rounded, const PreordersPage()),
                  _buildMenuCard(context, 'Fraud Analytics',
                      Icons.security_rounded, const FraudAnalyticsPage()),
                  _buildMenuCard(context, 'Sales Anomalies',
                      Icons.warning_amber_rounded, const SalesAnomaliesPage()),
                ],
                _buildMenuCard(
                    context,
                    'Settings',
                    Icons.settings_suggest_rounded,
                    SettingsPage(role: effectiveRole)),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40.0),
              child: Center(
                child: Text(
                  '© 2026 BloomyPro Inventory System',
                  style: TextStyle(color: Colors.grey[400], fontSize: 10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCardStream({
    required String title,
    required IconData icon,
    required Color color,
    required Stream<List<Map<String, dynamic>>> stream,
    required String Function(List<Map<String, dynamic>>) calculator,
  }) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final value = snapshot.hasData ? calculator(snapshot.data!) : '...';
        return Container(
          width: 140,
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMenuCard(
      BuildContext context, String title, IconData icon, Widget? page,
      {bool comingSoon = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: comingSoon
                ? null
                : () {
                    if (page != null) {
                      Navigator.push(context,
                          MaterialPageRoute(builder: (context) => page));
                    }
                  },
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: comingSoon
                          ? Colors.grey[100]
                          : const Color(0xFFF4B400).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon,
                        size: 32,
                        color: comingSoon
                            ? Colors.grey
                            : (isDark
                                ? Colors.white
                                : const Color(0xFF121212))),
                  ),
                  const SizedBox(height: 12),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: comingSoon
                            ? Colors.grey
                            : (isDark ? Colors.white : const Color(0xFF121212)),
                        letterSpacing: -0.2,
                      )),
                  if (comingSoon)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text('Coming Soon',
                          style: TextStyle(
                              fontSize: 9,
                              color: Colors.grey[400],
                              fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
