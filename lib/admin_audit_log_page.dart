import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'app_sidebar.dart';

class AdminAuditLogPage extends StatefulWidget {
  final String role;
  const AdminAuditLogPage({super.key, required this.role});

  @override
  State<AdminAuditLogPage> createState() => _AdminAuditLogPageState();
}

class _AdminAuditLogPageState extends State<AdminAuditLogPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // 'All', 'Admin', or 'Staff'. Only meaningful (and only shown) for
  // super-admin's full-log view — a plain admin already only ever sees
  // their own single-actor entries under Option B, so a role filter
  // there would just be trivially "one role, always."
  String _roleFilter = 'All';

  static const Set<String> _adminRoles = {'admin', 'super-admin'};
  static const Set<String> _staffRoles = {'staff', 'employee'};

  static const Map<String, String> _actionLabels = {
    'manual_restrict': 'MANUAL RESTRICT',
    'lift_restriction': 'RESTRICTION LIFTED',
    'ban_devices': 'DEVICE(S) BANNED',
    'walkin_cancel_override': 'WALK-IN OVERRIDE USED',
    'create_employee_account': 'ACCOUNT CREATED',
    'update_employee_role': 'ROLE/BRANCH CHANGED',
  };

  static const Map<String, Color> _actionColors = {
    'manual_restrict': Color(0xFFDC2626),
    'lift_restriction': Color(0xFF16A34A),
    'ban_devices': Color(0xFF0F172A),
    'walkin_cancel_override': Color(0xFF7C3AED),
    'create_employee_account': Color(0xFF2563EB),
    'update_employee_role': Color(0xFFB45309),
  };

  bool _matchesRoleFilter(String actorRole) {
    if (_roleFilter == 'All') return true;
    if (_roleFilter == 'Admin') return _adminRoles.contains(actorRole);
    if (_roleFilter == 'Staff') return _staffRoles.contains(actorRole);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width >= 850;

    final bool isAdmin = widget.role == 'admin' || widget.role == 'super-admin';
    final bool isSuperAdmin = widget.role == 'super-admin';
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Restricted')),
        drawer: isDesktop
            ? null
            : Drawer(child: AppSidebar(role: widget.role, currentPage: 'audit_log')),
        body: Row(
          children: [
            if (isDesktop) AppSidebar(role: widget.role, currentPage: 'audit_log'),
            const Expanded(
              child: Center(
                child: Text('This section is restricted to administrators.'),
              ),
            ),
          ],
        ),
      );
    }

    final Query baseQuery = isSuperAdmin
        ? _db.collection('admin_actions').limit(200)
        : _db
        .collection('admin_actions')
        .where('actorUid', isEqualTo: currentUid)
        .limit(200);

    return Scaffold(
      backgroundColor:
      isDark ? const Color(0xFF121212) : const Color(0xFFFFFDF9),
      appBar: AppBar(
        title: Text(
          isSuperAdmin ? 'Admin Activity Log' : 'My Activity Log',
          style: GoogleFonts.cormorantGaramond(
              fontWeight: FontWeight.bold, fontSize: 24),
        ),
        backgroundColor: isDark ? Colors.black : const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      drawer: isDesktop
          ? null
          : Drawer(child: AppSidebar(role: widget.role, currentPage: 'audit_log')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) AppSidebar(role: widget.role, currentPage: 'audit_log'),
          Expanded(
            child: Column(
              children: [
                if (!isSuperAdmin)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(isDark ? 0.15 : 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.blue, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'You are viewing only your own logged actions. The full activity log across all admins and employees is visible to Super Admins only.',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? Colors.blue[100] : Colors.blue[900]),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      hintText: isSuperAdmin
                          ? 'Search by admin/employee email, target UID, or action...'
                          : 'Search by target UID or action...',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                          : null,
                      filled: true,
                      fillColor: isDark ? Colors.grey[900] : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
                      ),
                    ),
                  ),
                ),
                // Only meaningful for super-admin's full-log view — a
                // plain admin's own entries are all the same role
                // (theirs), so the filter would have nothing to do.
                if (isSuperAdmin)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        _roleFilterChip('All', isDark),
                        const SizedBox(width: 8),
                        _roleFilterChip('Admin', isDark),
                        const SizedBox(width: 8),
                        _roleFilterChip('Staff', isDark),
                      ],
                    ),
                  ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: baseQuery.snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                            child: Text('Error loading audit log: ${snapshot.error}'));
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator(color: Color(0xFFF59E0B)));
                      }

                      final docs = List<QueryDocumentSnapshot>.from(snapshot.data?.docs ?? []);
                      docs.sort((a, b) {
                        final aTime = (a.data() as Map)['timestamp'];
                        final bTime = (b.data() as Map)['timestamp'];
                        if (aTime is! Timestamp || bTime is! Timestamp) return 0;
                        return bTime.compareTo(aTime);
                      });

                      final filtered = docs.where((d) {
                        final data = d.data() as Map<String, dynamic>;

                        final actorRole = (data['actorRole'] ?? '').toString();
                        if (!_matchesRoleFilter(actorRole)) return false;

                        if (_searchQuery.trim().isEmpty) return true;
                        final q = _searchQuery.toLowerCase();
                        return (data['actorEmail'] ?? '').toString().toLowerCase().contains(q) ||
                            (data['targetUid'] ?? '').toString().toLowerCase().contains(q) ||
                            (data['targetEmail'] ?? '').toString().toLowerCase().contains(q) ||
                            (data['action'] ?? '').toString().toLowerCase().contains(q);
                      }).toList();

                      if (filtered.isEmpty) {
                        return Center(
                          child: Text(
                            isSuperAdmin
                                ? 'No matching audit entries.'
                                : 'No logged actions from you yet.',
                            style: TextStyle(color: Colors.grey[400], fontSize: 13),
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final data = filtered[index].data() as Map<String, dynamic>;
                          final action = (data['action'] ?? '').toString();
                          final label = _actionLabels[action] ?? action.toUpperCase();
                          final color = _actionColors[action] ?? Colors.grey;
                          final ts = data['timestamp'];
                          final dateText = ts is Timestamp
                              ? DateFormat('MMM d, y • h:mm a').format(ts.toDate())
                              : 'Just now';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey[900] : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.withOpacity(0.15)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            color: color),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      dateText,
                                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (isSuperAdmin)
                                  Text(
                                    'By: ${data['actorEmail'] ?? 'unknown'} (${data['actorRole'] ?? 'unknown'})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                const SizedBox(height: 2),
                                Text(
                                  'Target: ${data['targetEmail'] ?? data['targetUid'] ?? 'unknown'}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                ),
                                if ((data['details'] ?? '').toString().isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    data['details'].toString(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleFilterChip(String label, bool isDark) {
    final selected = _roleFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _roleFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFF59E0B)
              : (isDark ? Colors.grey[900] : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? const Color(0xFFF59E0B) : Colors.grey.withOpacity(0.25)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : (isDark ? Colors.white : Colors.black87),
          ),
        ),
      ),
    );
  }
}