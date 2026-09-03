import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'inventory_data.dart';
import 'app_sidebar.dart';

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

    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2A2A2A) : Colors.grey.withValues(alpha: 0.2);
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    final isDesktop = MediaQuery.of(context).size.width >= 850;

    return Scaffold(
      backgroundColor: bgColor,
      drawer: isDesktop ? null : Drawer(child: AppSidebar(role: effectiveRole, currentPage: 'dashboard')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) AppSidebar(role: effectiveRole, currentPage: 'dashboard'),

          Expanded(
            child: CustomScrollView(
              slivers: [
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

                        GridView.count(
                          crossAxisCount: isDesktop ? 4 : 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: isDesktop ? 1.6 : 1.05,
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
                                  total += (o['totalAmount'] ??
                                      o['total_amount'] ??
                                      o['total_price'] ??
                                      0.0)
                                      .toDouble();
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

  // --- Top Navigation Bar (dropdown crash-guarded + live profile data) ---
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
          Expanded(
            flex: 3,
            child: isSuperAdmin
                ? StreamBuilder<List<Map<String, dynamic>>>(
              stream: InventoryData.getBranchesStream(),
              builder: (context, snapshot) {
                final branches = snapshot.data ?? [];

                // Guard: DropdownButton crashes if `value` isn't found in
                // `items`. _selectedBranchId can already hold a remembered
                // branch ID before this stream has finished its first
                // load — during that gap, `branches` is still empty.
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

          // Live-listens to users/{uid} so name + photo here always
          // matches whatever was last saved from ProfilePage.
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

  // --- Minimalist Stat Cards (overflow-proofed via LayoutBuilder+FittedBox) ---
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: iconColor, size: 22),
                      const SizedBox(height: 12),
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
                ),
              );
            },
          ),
        );
      },
    );
  }

  // --- Top 5 / Bottom 5 Performance Cards (title overflow-guarded) ---
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
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.cormorantGaramond(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          const SizedBox(width: 8),
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