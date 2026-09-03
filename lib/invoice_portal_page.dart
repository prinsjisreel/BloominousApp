import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'inventory_data.dart';
import 'app_sidebar.dart';
import 'invoice_detail_page.dart';

// Matches the <select> in invoice_management.php exactly, including
// casing — these values are compared directly against the computed
// paymentStatus, so a mismatch here would silently break the filter.
const List<String> _statusOptions = [
  'All Payment Statuses',
  'Paid',
  'Pending',
  'Voided',
  'Refunded',
  'Partially Refunded',
];

class InvoicePortalPage extends StatefulWidget {
  final String role;
  const InvoicePortalPage({super.key, this.role = 'employee'});

  @override
  State<InvoicePortalPage> createState() => _InvoicePortalPageState();
}

class _InvoicePortalPageState extends State<InvoicePortalPage> {
  String _searchQuery = '';
  String _selectedStatus = 'All Payment Statuses';
  String? _selectedBranchId;
  String? _branchName = 'Loading...';

  @override
  void initState() {
    super.initState();
    _initializeBranch();
  }

  // Same branch-init pattern as every other admin page — reads the
  // remembered selection for super-admins, or the staff member's
  // assigned branch. Previously this page ignored branch scoping
  // entirely for non-super-admins, meaning staff saw every branch's
  // invoices at once.
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
      if (mounted) {
        setState(() {
          _selectedBranchId = bId;
          _branchName = bId ?? 'No Branch Assigned';
        });
      }
    }
  }

  // --- Mirrors invoice_management.php's paymentStatus fallback exactly:
  // an explicit paymentStatus field wins if present; otherwise it's
  // derived from `status`. Getting this formula wrong means every badge
  // in the table would disagree with what clicking into the invoice
  // actually shows. ---
  String _paymentStatusOf(Map<String, dynamic> o) {
    if (o['paymentStatus'] != null) return o['paymentStatus'].toString();
    final status = (o['status'] ?? '').toString();
    if (status == 'cancelled') return 'Voided';
    if (status == 'completed' || status == 'delivered') return 'Paid';
    return 'Pending';
  }

  String _channelOf(Map<String, dynamic> o) => (o['type'] == 'POS') ? 'Walk-In' : 'Online';

  String _invoiceIdOf(Map<String, dynamic> o) {
    final raw = (o['invoiceId'] ?? '').toString();
    if (raw.isNotEmpty) return raw;
    final id = (o['id'] ?? '').toString();
    return '#${id.length > 10 ? id.substring(0, 10) : id}';
  }

  double _amountOf(Map<String, dynamic> o) =>
      (o['total_price'] ?? o['total_amount'] ?? 0.0).toDouble();

  String _customerOf(Map<String, dynamic> o) =>
      (o['customer_name'] ?? o['customerName'] ?? 'Walk-in Customer').toString();

  DateTime? _dateOf(Map<String, dynamic> o) {
    final raw = o['createdAt'] ?? o['timestamp'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  Color _statusBg(String status) {
    switch (status) {
      case 'Paid':
        return Colors.green.withValues(alpha: 0.12);
      case 'Pending':
        return Colors.amber.withValues(alpha: 0.15);
      default: // Voided / Refunded / Partially Refunded
        return Colors.grey.withValues(alpha: 0.15);
    }
  }

  Color _statusFg(String status) {
    switch (status) {
      case 'Paid':
        return Colors.green[700]!;
      case 'Pending':
        return Colors.amber[800]!;
      default:
        return Colors.grey[700]!;
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
    final isWideTable = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: bgColor,
      drawer: isDesktop ? null : Drawer(child: AppSidebar(role: widget.role, currentPage: 'invoice')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) AppSidebar(role: widget.role, currentPage: 'invoice'),
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
                          Text('Invoice Portal',
                              style: GoogleFonts.cormorantGaramond(color: textColor, fontWeight: FontWeight.bold, fontSize: 22)),
                        ],
                      ),
                    ),
                  Expanded(
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: InventoryData.ordersStream(branchId: _selectedBranchId),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)));
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text('Error loading invoices: ${snapshot.error}', style: TextStyle(color: textColor)));
                        }

                        final orders = snapshot.data ?? [];

                        final filtered = orders.where((o) {
                          final status = _paymentStatusOf(o);
                          if (_selectedStatus != 'All Payment Statuses' && status != _selectedStatus) return false;

                          if (_searchQuery.trim().isEmpty) return true;
                          final q = _searchQuery.toLowerCase();
                          final haystack = '${_invoiceIdOf(o)} ${_customerOf(o)} ${_channelOf(o)} $status'.toLowerCase();
                          return haystack.contains(q);
                        }).toList()
                          ..sort((a, b) {
                            final da = _dateOf(a);
                            final db = _dateOf(b);
                            if (da == null || db == null) return 0;
                            return db.compareTo(da);
                          });

                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Invoice Portal',
                                style: GoogleFonts.cormorantGaramond(
                                    fontSize: isDesktop ? 32 : 24, fontWeight: FontWeight.bold, color: textColor),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Every receipt, in one searchable place — view, print, or download.',
                                style: TextStyle(fontSize: 12, color: subTextColor),
                              ),
                              const SizedBox(height: 16),

                              // FIXED: Wrap instead of a plain Row — on a narrow
                              // phone, the dropdown + search field together no
                              // longer force a RenderFlex overflow warning.
                              // They just drop to a second line instead.
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  SizedBox(
                                    width: isDesktop ? 260 : double.infinity,
                                    child: _buildStatusDropdown(isDark, cardColor, borderColor, textColor),
                                  ),
                                  SizedBox(
                                    width: isDesktop ? 320 : double.infinity,
                                    child: _buildSearchField(isDark, cardColor, borderColor, textColor),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              if (filtered.isEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 60),
                                  width: double.infinity,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: cardColor,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(Icons.receipt_long_outlined, size: 48, color: subTextColor.withValues(alpha: 0.4)),
                                      const SizedBox(height: 12),
                                      Text('No invoices match your search/filter.',
                                          style: TextStyle(color: subTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                )
                              else if (isWideTable)
                                _buildTable(filtered, isDark, cardColor, borderColor, textColor, subTextColor)
                              else
                                Column(
                                  children: filtered
                                      .map((o) => _buildCard(o, isDark, cardColor, borderColor, textColor, subTextColor))
                                      .toList(),
                                ),
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

  Widget _buildStatusDropdown(bool isDark, Color cardColor, Color borderColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      height: 44,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedStatus,
          isExpanded: true,
          dropdownColor: cardColor,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFFF59E0B)),
          style: TextStyle(fontSize: 13, color: textColor),
          items: _statusOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: (val) {
            if (val != null) setState(() => _selectedStatus = val);
          },
        ),
      ),
    );
  }

  Widget _buildSearchField(bool isDark, Color cardColor, Color borderColor, Color textColor) {
    return SizedBox(
      height: 44,
      child: TextField(
        onChanged: (val) => setState(() => _searchQuery = val),
        style: TextStyle(fontSize: 13, color: textColor),
        decoration: InputDecoration(
          hintText: 'Search invoice #, customer...',
          hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
          prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
          filled: true,
          fillColor: cardColor,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFF59E0B), width: 1.5)),
        ),
      ),
    );
  }

  Widget _pill(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> orders, bool isDark, Color cardColor, Color borderColor, Color textColor, Color subTextColor) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(isDark ? const Color(0xFF222222) : const Color(0xFFFAFAFA)),
            columns: [
              DataColumn(label: Text('INVOICE #', style: _headerStyle(subTextColor))),
              DataColumn(label: Text('CHANNEL', style: _headerStyle(subTextColor))),
              DataColumn(label: Text('CUSTOMER', style: _headerStyle(subTextColor))),
              DataColumn(label: Text('DATE', style: _headerStyle(subTextColor))),
              DataColumn(label: Text('AMOUNT', style: _headerStyle(subTextColor))),
              DataColumn(label: Text('STATUS', style: _headerStyle(subTextColor))),
              DataColumn(label: Text('ACTIONS', style: _headerStyle(subTextColor))),
            ],
            rows: orders.map((o) {
              final status = _paymentStatusOf(o);
              final channel = _channelOf(o);
              final date = _dateOf(o);
              return DataRow(cells: [
                DataCell(Text(_invoiceIdOf(o), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor))),
                DataCell(_pill(channel, channel == 'Walk-In' ? Colors.deepPurple.withValues(alpha: 0.12) : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    channel == 'Walk-In' ? Colors.deepPurple[700]! : const Color(0xFFB45309))),
                DataCell(Text(_customerOf(o), style: TextStyle(fontSize: 13, color: textColor))),
                DataCell(Text(date != null ? DateFormat('M/d/yyyy').format(date) : 'N/A', style: TextStyle(fontSize: 12, color: subTextColor))),
                DataCell(Text('₱${_amountOf(o).toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor))),
                DataCell(_pill(status, _statusBg(status), _statusFg(status))),
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.remove_red_eye_outlined, size: 18), tooltip: 'View', onPressed: () => _openDetail(o)),
                  IconButton(icon: const Icon(Icons.print_outlined, size: 18), tooltip: 'Print', onPressed: () => _openDetail(o, action: 'print')),
                  IconButton(icon: const Icon(Icons.download_outlined, size: 18, color: Color(0xFFF59E0B)), tooltip: 'Download', onPressed: () => _openDetail(o, action: 'download')),
                ])),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  TextStyle _headerStyle(Color c) => TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: c);

  Widget _buildCard(Map<String, dynamic> o, bool isDark, Color cardColor, Color borderColor, Color textColor, Color subTextColor) {
    final status = _paymentStatusOf(o);
    final channel = _channelOf(o);
    final date = _dateOf(o);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(_invoiceIdOf(o),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor), overflow: TextOverflow.ellipsis),
              ),
              _pill(status, _statusBg(status), _statusFg(status)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _pill(channel, channel == 'Walk-In' ? Colors.deepPurple.withValues(alpha: 0.12) : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  channel == 'Walk-In' ? Colors.deepPurple[700]! : const Color(0xFFB45309)),
              const SizedBox(width: 8),
              Expanded(child: Text(_customerOf(o), style: TextStyle(fontSize: 13, color: subTextColor), overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: borderColor),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(date != null ? DateFormat('M/d/yyyy').format(date) : 'N/A', style: TextStyle(fontSize: 12, color: subTextColor)),
              // FittedBox guards against a long peso amount overflowing on
              // a narrow card — same fix pattern as the Orders metric boxes.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text('₱${_amountOf(o).toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFF59E0B))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openDetail(o),
                icon: const Icon(Icons.remove_red_eye, size: 14),
                label: const Text('View', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                onPressed: () => _openDetail(o, action: 'print'),
                icon: const Icon(Icons.print, size: 14),
                label: const Text('Print', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                onPressed: () => _openDetail(o, action: 'download'),
                icon: const Icon(Icons.picture_as_pdf, size: 14),
                label: const Text('PDF', style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openDetail(Map<String, dynamic> order, {String? action}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InvoiceDetailPage(orderId: order['id'], role: widget.role, autoAction: action)),
    );
  }
}