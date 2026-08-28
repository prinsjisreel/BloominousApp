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
      if (mounted) {
        setState(() {
          _branchName = 'All Branches (Super Admin)';
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

  String _getFormattedDate() {
    final now = DateTime.now();
    final months = [
      'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
      'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final bool isSuperAdmin = widget.role == 'super-admin';
    final effectiveRole = widget.role;
    final isAdmin = effectiveRole == 'admin' || effectiveRole == 'super-admin';

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Dark mode deep slate vs Clean light mode
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2A2A2A) : Colors.grey.withValues(alpha: 0.2);
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    // Responsive layout breakpoint
    final isDesktop = MediaQuery.of(context).size.width >= 850;

    return Scaffold(
      backgroundColor: bgColor,
      drawer: isDesktop ? null : Drawer(child: _buildSidebar(cardColor, textColor, subTextColor, isDark, effectiveRole, isAdmin)),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sidebar for wide screens
          if (isDesktop) _buildSidebar(cardColor, textColor, subTextColor, isDark, effectiveRole, isAdmin),

          // Main Content Area
          Expanded(
            child: CustomScrollView(
              slivers: [
                // Minimal Mobile App Bar
                if (!isDesktop)
                  SliverAppBar(
                    backgroundColor: cardColor,
                    iconTheme: IconThemeData(color: textColor),
                    elevation: 0,
                    pinned: true,
                    title: Text(
                      'Dashboard',
                      style: GoogleFonts.cormorantGaramond(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                    ),
                  ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The updated top bar (profile beside branch dropdown) with Overlap Fix
                        _buildTopBar(cardColor, textColor, subTextColor, borderColor, isDark, isSuperAdmin, user, effectiveRole, isAdmin),
                        const SizedBox(height: 32),

                        Text(
                          'BUSINESS SUMMARY',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: subTextColor,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Muted Aesthetic Grid Layout for Stat Cards
                        GridView.count(
                          crossAxisCount: isDesktop ? 4 : 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: isDesktop ? 1.6 : 1.3,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _buildMinimalStatCardStream(
                              title: 'Inventory',
                              icon: Icons.inventory_2_outlined,
                              iconColor: Colors.blueAccent,
                              stream: InventoryData.inventoryStream(),
                              calculator: (data) => data.length.toString(),
                              cardColor: cardColor,
                              borderColor: borderColor,
                              textColor: textColor,
                              subTextColor: subTextColor,
                              isDark: isDark,
                            ),
                            _buildMinimalStatCardStream(
                              title: 'Total Sales',
                              icon: Icons.payments_outlined,
                              iconColor: Colors.greenAccent,
                              stream: InventoryData.ordersStream(),
                              calculator: (data) {
                                double total = 0;
                                for (var o in data) {
                                  total += (o['totalAmount'] ?? (o['total_amount'] ?? 0.0)).toDouble();
                                }
                                return '₱${total.toStringAsFixed(0)}';
                              },
                              cardColor: cardColor,
                              borderColor: borderColor,
                              textColor: textColor,
                              subTextColor: subTextColor,
                              isDark: isDark,
                            ),
                            _buildMinimalStatCardStream(
                              title: 'Low Stock',
                              icon: Icons.warning_amber_rounded,
                              iconColor: Colors.orangeAccent,
                              stream: InventoryData.lowStockStream(),
                              calculator: (data) => data.length.toString(),
                              cardColor: cardColor,
                              borderColor: borderColor,
                              textColor: textColor,
                              subTextColor: subTextColor,
                              isDark: isDark,
                            ),
                            _buildMinimalStatCardStream(
                              title: 'Spoilage',
                              icon: Icons.delete_outline_rounded,
                              iconColor: Colors.redAccent,
                              stream: InventoryData.spoilageStream(),
                              calculator: (data) => data.length.toString(),
                              cardColor: cardColor,
                              borderColor: borderColor,
                              textColor: textColor,
                              subTextColor: subTextColor,
                              isDark: isDark,
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),
                        Text(
                          'PERFORMANCE METRICS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: subTextColor,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Top 5 / Bottom 5 Performance Cards (FIXED - Horizontal layout in column)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPerformanceCard('Top 5 - Best Sellers', cardColor, borderColor, textColor, subTextColor, isDark),
                            const SizedBox(height: 12),
                            _buildPerformanceCard('Bottom 5 - Low Performers', cardColor, borderColor, textColor, subTextColor, isDark),
                          ],
                        ),
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
            ),
          ),
        ],
      ),
    );
  }

  // --- Sidebar Component (Untouched) ---
  Widget _buildSidebar(Color cardColor, Color textColor, Color subTextColor, bool isDark, String effectiveRole, bool isAdmin) {
    String displayRole = effectiveRole == 'super-admin' ? 'SUPER ADMIN' : (effectiveRole == 'admin' ? 'ADMINISTRATOR' : 'STAFF MEMBER');

    return Container(
      width: 260,
      color: cardColor,
      child: Column(
        children: [
          const SizedBox(height: 40),
          Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? Colors.grey[800] : Colors.white,
                  boxShadow: [
                    if (!isDark)
                      BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/logo.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.local_florist, color: Color(0xFFF59E0B)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'BLOOMINOUS',
                style: GoogleFonts.cormorantGaramond(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                  color: const Color(0xFFD4AF37),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                ),
                child: Text(
                  displayRole,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: Color(0xFFF59E0B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          // Navigation Links
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(),
              children: [
                _buildSidebarItem('Dashboard', Icons.dashboard, null, isDark, textColor, isActive: true),
                _buildSidebarItem('Orders', Icons.shopping_cart_checkout, OrdersPage(role: effectiveRole), isDark, textColor),
                _buildSidebarItem('Invoice Portal', Icons.receipt_long, InvoicePortalPage(role: effectiveRole), isDark, textColor),
                _buildSidebarItem('Pre-Orders', Icons.calendar_today, const PreordersPage(), isDark, textColor, isHidden: !isAdmin),
                _buildSidebarItem('Fraud Analytics', Icons.security, const FraudAnalyticsPage(), isDark, textColor, isHidden: !isAdmin),
                _buildSidebarItem('Sales Anomalies', Icons.warning_amber, const SalesAnomaliesPage(), isDark, textColor, isHidden: !isAdmin),
                _buildSidebarItem('Inventory', Icons.inventory_2, InventoryPage(role: effectiveRole), isDark, textColor),
                _buildSidebarItem('Freshness Matrix', Icons.health_and_safety, const FreshnessMatrixPage(), isDark, textColor),
                _buildSidebarItem('Spoilage Tracker', Icons.delete_sweep, const SpoilageTrackerPage(), isDark, textColor),
                _buildSidebarItem('AI Stock Alerts', Icons.notification_important, const LowStockAlertsPage(), isDark, textColor),
                _buildSidebarItem('POS Scanner', Icons.qr_code_scanner, const POSScannerPage(), isDark, textColor),
                _buildSidebarItem('Barcode Gen', Icons.barcode_reader, const BarcodeGeneratorPage(), isDark, textColor),
                _buildSidebarItem('Delivery Status', Icons.local_shipping, const DeliveryStatusPage(), isDark, textColor),
                _buildSidebarItem('Profile', Icons.person_outline, const ProfilePage(), isDark, textColor),
                _buildSidebarItem('Manage Employees', Icons.badge, ManageEmployeesPage(role: effectiveRole), isDark, textColor, isHidden: !isAdmin),
                _buildSidebarItem('Sales Report', Icons.analytics, SalesReportPage(role: effectiveRole), isDark, textColor, isHidden: !isAdmin),
                _buildSidebarItem('3D Realism Hub', Icons.auto_awesome_mosaic, const KiriGeneratorPage(), isDark, textColor),
                _buildSidebarItem('Settings', Icons.settings, SettingsPage(role: effectiveRole), isDark, textColor),
              ],
            ),
          ),

          // --- Relocated Logout Button ---
          Container(
            margin: const EdgeInsets.only(bottom: 24, top: 8),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: Colors.transparent, width: 4),
              ),
            ),
            child: ListTile(
              leading: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
              title: const Text(
                'Logout',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.redAccent,
                ),
              ),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                if (mounted) Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(String title, IconData icon, Widget? page, bool isDark, Color textColor, {bool isActive = false, bool isHidden = false}) {
    if (isHidden) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isActive
            ? (isDark ? const Color(0xFFF59E0B).withValues(alpha: 0.15) : const Color(0xFFFFF8E1))
            : Colors.transparent,
        border: Border(
          left: BorderSide(
            color: isActive ? const Color(0xFFF59E0B) : Colors.transparent,
            width: 4,
          ),
        ),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          size: 20,
          color: isActive
              ? const Color(0xFFF59E0B)
              : (isDark ? Colors.grey[400] : Colors.grey[700]),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
            color: isActive ? const Color(0xFFF59E0B) : textColor,
          ),
        ),
        onTap: () {
          if (!isActive && page != null) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => page));
          }
        },
      ),
    );
  }

  // --- Top Navigation Bar ---
  Widget _buildTopBar(Color cardColor, Color textColor, Color subTextColor, Color borderColor, bool isDark, bool isSuperAdmin, User? user, String role, bool isAdmin) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          if (!isDark)
            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          // Expanded gives the Branch Selector room to breathe
          Expanded(
            flex: 3,
            child: isSuperAdmin
                ? DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedBranchId,
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
                      // ignore: cast_from_null_always_fails
                      final branch = [];
                      _branchName = branch.isNotEmpty ? branch[0] : 'Branch Selected';
                    }
                  });
                },
                items: const [
                  DropdownMenuItem(value: null, child: Text('All Branches')),
                ],
              ),
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

          // Flexible allows User Info to shrink gracefully without overflowing
          Flexible(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  user?.email?.split('@')[0] ?? (isAdmin ? 'Admin' : 'Staff'),
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
            child: Text(
              user?.email?.substring(0, 1).toUpperCase() ?? 'A',
              style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // --- Minimalist Stat Cards ---
  Widget _buildMinimalStatCardStream({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Stream<List<Map<String, dynamic>>> stream,
    required String Function(List<Map<String, dynamic>>) calculator,
    required Color cardColor,
    required Color borderColor,
    required Color textColor,
    required Color subTextColor,
    required bool isDark,
  }) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final value = snapshot.hasData ? calculator(snapshot.data!) : '...';
        return Container(
          padding: const EdgeInsets.all(16),
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(height: 16),
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  color: subTextColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Top 5 / Bottom 5 Performance Cards (HORIZONTAL LAYOUT - FIXED) ---
  Widget _buildPerformanceCard(String title, Color cardColor, Color borderColor, Color textColor, Color subTextColor, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Title on the left
          Text(
            title,
            style: GoogleFonts.cormorantGaramond(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          // Status badge on the right
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.grey.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Text(
              'No Data',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: subTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}