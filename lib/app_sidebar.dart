import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'admin_dashboard.dart';
import 'orders_page.dart';
import 'inventory_page.dart';
import 'pos_scanner_page.dart';
import 'profile_page.dart';
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
import 'admin_audit_log_page.dart';
import 'override_codes_page.dart';

class AppSidebar extends StatelessWidget {
  final String role;
  final String currentPage;

  const AppSidebar({
    super.key,
    required this.role,
    required this.currentPage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);

    final bool isAdmin = role == 'admin' || role == 'super-admin';
    final String displayRole = role == 'super-admin'
        ? 'SUPER ADMIN'
        : (role == 'admin' ? 'ADMINISTRATOR' : 'STAFF MEMBER');

    // FIXED: wrapping the whole sidebar in SafeArea keeps its content —
    // most visibly the Logout tile at the very bottom — from rendering
    // underneath the phone's on-screen system navigation bar. Without
    // this, Flutter has no idea that strip of the physical screen is
    // reserved by the OS, so it just draws content all the way to the
    // true bottom edge, and the nav bar visually covers whatever lands
    // there. Since every page's Drawer builds THIS widget, one fix here
    // resolves it everywhere at once — no need to touch each page.
    return SafeArea(
      child: Container(
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
                      errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.local_florist, color: Color(0xFFF59E0B)),
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
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                physics: const BouncingScrollPhysics(),
                children: [
                  _item(context, 'Dashboard', Icons.dashboard, 'dashboard', AdminDashboard(role: role), isDark, textColor),
                  _item(context, 'Orders', Icons.shopping_cart_checkout, 'orders', OrdersPage(role: role), isDark, textColor),
                  _item(context, 'Invoice Portal', Icons.receipt_long, 'invoice', InvoicePortalPage(role: role), isDark, textColor),
                  _item(context, 'Pre-Orders', Icons.calendar_today, 'preorders', PreordersPage(role: role), isDark, textColor, isHidden: !isAdmin),
                  _item(context, 'Fraud Analytics', Icons.security, 'fraud', FraudAnalyticsPage(role: role), isDark, textColor, isHidden: !isAdmin),
                  _item(context, 'Admin Activity Log', Icons.fact_check, 'audit_log', AdminAuditLogPage(role: role), isDark, textColor, isHidden: !isAdmin),
                  // New — mobile equivalent of override_codes.php. Shares
                  // the exact same Firestore collections as web, so a
                  // batch generated on either platform shows up live on
                  // the other.
                  _item(context, 'Override Codes', Icons.vpn_key, 'override_codes', OverrideCodesPage(role: role), isDark, textColor, isHidden: !isAdmin),
                  _item(context, 'Sales Anomalies', Icons.warning_amber, 'anomalies', SalesAnomaliesPage(role: role), isDark, textColor, isHidden: !isAdmin),
                  _item(context, 'Inventory', Icons.inventory_2, 'inventory', InventoryPage(role: role), isDark, textColor),
                  _item(context, 'Freshness Matrix', Icons.health_and_safety, 'freshness', FreshnessMatrixPage(role: role), isDark, textColor),
                  _item(context, 'Spoilage Tracker', Icons.delete_sweep, 'spoilage', const SpoilageTrackerPage(), isDark, textColor),
                  _item(context, 'AI Stock Alerts', Icons.notification_important, 'alerts', LowStockAlertsPage(role: role), isDark, textColor),                  _item(context, 'POS Scanner', Icons.qr_code_scanner, 'pos', const POSScannerPage(), isDark, textColor),
                  _item(context, 'Barcode Gen', Icons.barcode_reader, 'barcode', const BarcodeGeneratorPage(), isDark, textColor),
                  _item(context, 'Delivery Status', Icons.local_shipping, 'delivery', DeliveryStatusPage(role: role), isDark, textColor),
                  _item(context, 'Profile', Icons.person_outline, 'profile', ProfilePage(role: role), isDark, textColor),                  _item(context, 'Manage Employees', Icons.badge, 'employees', ManageEmployeesPage(role: role), isDark, textColor, isHidden: !isAdmin),
                  _item(context, 'Sales Report', Icons.analytics, 'sales_report', SalesReportPage(role: role), isDark, textColor, isHidden: !isAdmin),
                  _item(context, '3D Realism Hub', Icons.auto_awesome_mosaic, 'kiri', KiriGeneratorPage(role: role), isDark, textColor),                  _item(context, 'Settings', Icons.settings, 'settings', SettingsPage(role: role), isDark, textColor),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(bottom: 24, top: 8),
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: Colors.transparent, width: 4)),
              ),
              child: ListTile(
                leading: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                title: const Text(
                  'Logout',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.redAccent),
                ),
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) {
                    Navigator.of(context, rootNavigator: true)
                        .popUntil((route) => route.isFirst);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(
      BuildContext context,
      String title,
      IconData icon,
      String pageKey,
      Widget page,
      bool isDark,
      Color textColor, {
        bool isHidden = false,
      }) {
    if (isHidden) return const SizedBox.shrink();
    final bool isActive = currentPage == pageKey;

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
          color: isActive ? const Color(0xFFF59E0B) : (isDark ? Colors.grey[400] : Colors.grey[700]),
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
          if (!isActive) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => page));
          }
        },
      ),
    );
  }
}