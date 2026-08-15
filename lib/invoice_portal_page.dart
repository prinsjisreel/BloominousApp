import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'inventory_data.dart';

class InvoicePortalPage extends StatefulWidget {
  final String role;
  const InvoicePortalPage({super.key, this.role = 'super-admin'});

  @override
  State<InvoicePortalPage> createState() => _InvoicePortalPageState();
}

class _InvoicePortalPageState extends State<InvoicePortalPage> {
  String _searchQuery = '';
  String _selectedPaymentStatus = 'All Payment Statuses';
  String? _selectedBranchId;

  final List<String> _statusOptions = [
    'All Payment Statuses',
    'PAID',
    'PENDING',
    'AWAITING PAYMENT',
    'REFUNDED',
    'FAILED',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSuperAdmin = widget.role == 'super-admin';

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFFAF9F6),
      appBar: AppBar(
        title: Text(
          'INVOICE PORTAL',
          style: GoogleFonts.playfairDisplay(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        centerTitle: false,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0.5,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
        actions: [
          if (isSuperAdmin)
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: InventoryData.getBranchesStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();
                final branches = snapshot.data!;
                return Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: PopupMenuButton<String?>(
                    icon: const Icon(Icons.location_city_rounded,
                        color: Color(0xFFD97706)),
                    tooltip: 'Filter Branch',
                    onSelected: (branchId) {
                      setState(() {
                        _selectedBranchId = branchId;
                      });
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: null,
                        child: Text('All Branches'),
                      ),
                      ...branches.map((b) => PopupMenuItem(
                            value: b['id'] as String,
                            child: Text(b['name'] as String? ?? 'Branch'),
                          )),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: InventoryData.ordersStream(branchId: _selectedBranchId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final rawOrders = snapshot.data ?? [];

          // Filter by search query & payment status
          final filteredOrders = rawOrders.where((order) {
            final orderId = (order['id'] ??
                    order['orderId'] ??
                    order['invoiceNumber'] ??
                    '')
                .toString();
            final customerName =
                (order['customerName'] ?? order['billedTo'] ?? '').toString();
            final customerEmail =
                (order['customerEmail'] ?? order['email'] ?? '').toString();
            final paymentStatus =
                (order['paymentStatus'] ?? order['payment_status'] ?? 'PENDING')
                    .toString()
                    .toUpperCase();
            final channel =
                (order['channel'] ?? 'ONLINE').toString().toUpperCase();

            // Search filter
            final matchesQuery = _searchQuery.isEmpty ||
                orderId.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                customerName
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase()) ||
                customerEmail
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase()) ||
                paymentStatus
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase()) ||
                channel.toLowerCase().contains(_searchQuery.toLowerCase());

            // Payment status filter
            bool matchesStatus = true;
            if (_selectedPaymentStatus != 'All Payment Statuses') {
              matchesStatus = paymentStatus == _selectedPaymentStatus;
            }

            return matchesQuery && matchesStatus;
          }).toList();

          return CustomScrollView(
            slivers: [
              // Subtitle & Header description
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Invoice Portal',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color:
                              isDark ? Colors.white : const Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Every receipt, in one searchable place — view, print, or download.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: isDark
                              ? Colors.grey[400]
                              : const Color(0xFF6B7280),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Filters & Controls Row
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isMobile = constraints.maxWidth < 600;
                          return isMobile
                              ? Column(
                                  children: [
                                    _buildStatusDropdown(isDark),
                                    const SizedBox(height: 12),
                                    _buildSearchField(isDark),
                                  ],
                                )
                              : Row(
                                  children: [
                                    Expanded(
                                        flex: 2,
                                        child: _buildStatusDropdown(isDark)),
                                    const SizedBox(width: 16),
                                    Expanded(
                                        flex: 3,
                                        child: _buildSearchField(isDark)),
                                  ],
                                );
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

              // Orders Table / List View
              if (filteredOrders.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 64,
                            color:
                                isDark ? Colors.grey[600] : Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No invoices found',
                          style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color:
                                  isDark ? Colors.grey[300] : Colors.grey[700]),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Try adjusting your search query or payment status filter',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth > 700) {
                          return _buildDataTable(
                              context, filteredOrders, isDark);
                        } else {
                          return _buildMobileCardList(
                              context, filteredOrders, isDark);
                        }
                      },
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusDropdown(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? Colors.grey[800]! : const Color(0xFFE5E7EB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedPaymentStatus,
          isExpanded: true,
          dropdownColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: Color(0xFFD97706)),
          style: GoogleFonts.inter(
              fontSize: 13,
              color: isDark ? Colors.white : const Color(0xFF374151)),
          items: _statusOptions.map((status) {
            return DropdownMenuItem<String>(
              value: status,
              child: Text(status),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) setState(() => _selectedPaymentStatus = val);
          },
        ),
      ),
    );
  }

  Widget _buildSearchField(bool isDark) {
    return TextField(
      onChanged: (val) => setState(() => _searchQuery = val),
      style: GoogleFonts.inter(
          fontSize: 13, color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        hintText: 'Search invoice #, customer...',
        hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey),
        prefixIcon:
            const Icon(Icons.search_rounded, size: 20, color: Colors.grey),
        filled: true,
        fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: isDark ? Colors.grey[800]! : const Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD97706), width: 1.5),
        ),
      ),
    );
  }

  // Large Desktop/Tablet Data Table Layout
  Widget _buildDataTable(
      BuildContext context, List<Map<String, dynamic>> orders, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark ? Colors.grey[800]! : const Color(0xFFF3F4F6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
                isDark ? const Color(0xFF2A2A2A) : const Color(0xFFFAFAFA)),
            dataRowHeight: 68,
            horizontalMargin: 20,
            columnSpacing: 24,
            columns: [
              _buildTableHeader('INVOICE #', isDark),
              _buildTableHeader('CHANNEL', isDark),
              _buildTableHeader('CUSTOMER', isDark),
              _buildTableHeader('DATE', isDark),
              _buildTableHeader('AMOUNT', isDark),
              _buildTableHeader('PAYMENT STATUS', isDark),
              _buildTableHeader('POD', isDark),
              _buildTableHeader('ACTIONS', isDark),
            ],
            rows: orders.map((order) {
              final rawId = (order['id'] ??
                      order['orderId'] ??
                      order['invoiceNumber'] ??
                      '')
                  .toString();
              final displayInvoice =
                  rawId.length > 10 ? '#${rawId.substring(0, 10)}' : '#$rawId';
              final channel =
                  (order['channel'] ?? 'ONLINE').toString().toUpperCase();
              final customer = order['customerName'] ??
                  order['billedTo'] ??
                  'Walk-in Customer';
              final rawDate = order['createdAt'] ?? order['created_at'];
              final formattedDate = _formatDate(rawDate);
              final totalAmt =
                  (order['totalAmount'] ?? order['totalPrice'] ?? 0.0)
                      .toDouble();
              final payStatus = (order['paymentStatus'] ??
                      order['payment_status'] ??
                      'PENDING')
                  .toString()
                  .toUpperCase();
              final hasPod =
                  (order['proofOfDeliveryPhoto'] ?? order['podPhotoUrl']) !=
                          null ||
                      (order['status'] ?? '').toString().toLowerCase() ==
                          'delivered';

              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      displayInvoice,
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  DataCell(_buildChannelPill(channel)),
                  DataCell(
                    Text(
                      customer,
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          color: isDark
                              ? Colors.grey[300]
                              : const Color(0xFF374151)),
                    ),
                  ),
                  DataCell(
                    Text(
                      formattedDate,
                      style: GoogleFonts.inter(
                          fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
                  DataCell(
                    Text(
                      '₱${totalAmt.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  DataCell(_buildPaymentStatusPill(payStatus)),
                  DataCell(
                    hasPod
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6)),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_outline,
                                    size: 14, color: Colors.green),
                                SizedBox(width: 4),
                                Text('POD',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )
                        : Text('—',
                            style: GoogleFonts.inter(color: Colors.grey)),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_red_eye_outlined,
                              size: 18, color: Colors.blue),
                          tooltip: 'View Invoice',
                          onPressed: () =>
                              _showInvoiceDetailsDialog(context, order),
                        ),
                        IconButton(
                          icon: const Icon(Icons.print_outlined,
                              size: 18, color: Colors.grey),
                          tooltip: 'Print Invoice',
                          onPressed: () => _printInvoice(order),
                        ),
                        IconButton(
                          icon: const Icon(Icons.download_outlined,
                              size: 18, color: Color(0xFFD97706)),
                          tooltip: 'Download PDF',
                          onPressed: () => _downloadPdf(context, order),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // Mobile Clean Card View
  Widget _buildMobileCardList(
      BuildContext context, List<Map<String, dynamic>> orders, bool isDark) {
    return Column(
      children: orders.map((order) {
        final rawId =
            (order['id'] ?? order['orderId'] ?? order['invoiceNumber'] ?? '')
                .toString();
        final displayInvoice =
            rawId.length > 10 ? '#${rawId.substring(0, 10)}' : '#$rawId';
        final channel = (order['channel'] ?? 'ONLINE').toString().toUpperCase();
        final customer =
            order['customerName'] ?? order['billedTo'] ?? 'Walk-in Customer';
        final rawDate = order['createdAt'] ?? order['created_at'];
        final formattedDate = _formatDate(rawDate);
        final totalAmt =
            (order['totalAmount'] ?? order['totalPrice'] ?? 0.0).toDouble();
        final payStatus =
            (order['paymentStatus'] ?? order['payment_status'] ?? 'PENDING')
                .toString()
                .toUpperCase();

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
                color: isDark ? Colors.grey[800]! : const Color(0xFFE5E7EB)),
          ),
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      displayInvoice,
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isDark ? Colors.white : Colors.black87),
                    ),
                    _buildPaymentStatusPill(payStatus),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildChannelPill(channel),
                    const SizedBox(width: 8),
                    Text(customer,
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            color: isDark
                                ? Colors.grey[300]
                                : const Color(0xFF4B5563))),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formattedDate,
                        style: GoogleFonts.inter(
                            fontSize: 12, color: Colors.grey)),
                    Text(
                      '₱${totalAmt.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: const Color(0xFFD97706)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.remove_red_eye, size: 16),
                      label: const Text('View', style: TextStyle(fontSize: 12)),
                      onPressed: () =>
                          _showInvoiceDetailsDialog(context, order),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.print, size: 16),
                      label:
                          const Text('Print', style: TextStyle(fontSize: 12)),
                      onPressed: () => _printInvoice(order),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD97706),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.picture_as_pdf, size: 16),
                      label: const Text('PDF', style: TextStyle(fontSize: 12)),
                      onPressed: () => _downloadPdf(context, order),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  DataColumn _buildTableHeader(String label, bool isDark) {
    return DataColumn(
      label: Text(
        label,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.8,
          color: isDark ? Colors.grey[400] : const Color(0xFF6B7280),
        ),
      ),
    );
  }

  Widget _buildChannelPill(String channel) {
    Color bg = const Color(0xFFFEF3C7);
    Color text = const Color(0xFFD97706);
    if (channel == 'POS' || channel == 'STORE') {
      bg = const Color(0xFFE0F2FE);
      text = const Color(0xFF0369A1);
    } else if (channel == 'WALK-IN') {
      bg = const Color(0xFFF3E8FF);
      text = const Color(0xFF6B21A8);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        channel,
        style: GoogleFonts.inter(
            fontSize: 10, fontWeight: FontWeight.bold, color: text),
      ),
    );
  }

  Widget _buildPaymentStatusPill(String status) {
    Color bg = const Color(0xFFFEF3C7);
    Color text = const Color(0xFFB45309);

    if (status == 'PAID') {
      bg = const Color(0xFFDCFCE7);
      text = const Color(0xFF15803D);
    } else if (status == 'FAILED' || status == 'REFUNDED') {
      bg = const Color(0xFFFEE2E2);
      text = const Color(0xFFB91C1C);
    } else if (status == 'AWAITING PAYMENT') {
      bg = const Color(0xFFF3F4F6);
      text = const Color(0xFF4B5563);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status,
        style: GoogleFonts.inter(
            fontSize: 10, fontWeight: FontWeight.bold, color: text),
      ),
    );
  }

  String _formatDate(dynamic rawDate) {
    if (rawDate == null) return '7/19/2026';
    try {
      if (rawDate is Timestamp) {
        return DateFormat('M/d/yyyy').format(rawDate.toDate());
      } else if (rawDate is String) {
        return DateFormat('M/d/yyyy').format(DateTime.parse(rawDate));
      }
    } catch (_) {}
    return '7/19/2026';
  }

  // DETAILED INVOICE MODAL DIALOG (Matching Screenshot 2)
  void _showInvoiceDetailsDialog(
      BuildContext context, Map<String, dynamic> order) {
    final rawId =
        (order['id'] ?? order['orderId'] ?? order['invoiceNumber'] ?? '')
            .toString();
    final displayInvoiceNumber =
        rawId.length > 10 ? '#${rawId.substring(0, 10)}' : '#$rawId';
    final customerUserId =
        order['userId'] ?? order['customerUserId'] ?? 'kkgEvH3tCyKHhBtuW7AV';
    final paymentMethod =
        (order['paymentMethod'] ?? order['payment_method'] ?? 'COD')
            .toString()
            .toUpperCase();
    final channel = (order['channel'] ?? 'ONLINE').toString().toUpperCase();
    final paymentStatus =
        (order['paymentStatus'] ?? order['payment_status'] ?? 'PENDING')
            .toString()
            .toUpperCase();
    final rawDate = order['createdAt'] ?? order['created_at'];
    final dateTimeStr = rawDate is Timestamp
        ? DateFormat('MMM dd, yyyy, hh:mm a').format(rawDate.toDate())
        : 'Jul 19, 2026, 01:28 AM';

    final billedToName =
        order['customerName'] ?? order['billedTo'] ?? 'prinsqtpotato';
    final billedToEmail =
        order['customerEmail'] ?? order['email'] ?? 'prinsqtpotato@gmail.com';

    final deliveryAddress = order['deliveryAddress'] ??
        '64 Lias Road, Central Luzon, Bulacan, Marilao, Lias, Postal Code: 3019';

    final items = (order['items'] as List<dynamic>?) ?? [];
    final subtotal =
        (order['subtotal'] ?? order['totalPrice'] ?? 1400.0).toDouble();
    final deliveryFee =
        (order['deliveryFee'] ?? order['delivery_fee'] ?? 80.0).toDouble();
    final totalAmount = (order['totalAmount'] ??
            order['total_amount'] ??
            (subtotal + deliveryFee))
        .toDouble();

    final podPhoto =
        (order['proofOfDeliveryPhoto'] ?? order['podPhotoUrl']) as String?;
    final podRecipient =
        order['podRecipient'] ?? order['recipientName'] ?? billedToName;
    final courierName =
        order['courierName'] ?? order['driverName'] ?? 'Express Delivery';

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 750, maxHeight: 850),
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Modal Header Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Order Registry / Invoice View',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _printInvoice(order),
                          icon: const Icon(Icons.print_outlined, size: 16),
                          label: const Text('Reprint',
                              style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black87,
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _downloadPdf(context, order),
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('Download PDF',
                              style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD97706),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(dialogCtx),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Invoice Main Paper Sheet
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF3F4F6)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Brand Header & Invoice #
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'BLOOMINOUS',
                                    style: GoogleFonts.playfairDisplay(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2.0,
                                      color: const Color(0xFF111827),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    customerUserId,
                                    style: GoogleFonts.inter(
                                        fontSize: 12, color: Colors.grey[500]),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'PAYMENT METHOD',
                                    style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[400],
                                        letterSpacing: 0.5),
                                  ),
                                  Text(
                                    paymentMethod,
                                    style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF1F2937)),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    displayInvoiceNumber,
                                    style: GoogleFonts.playfairDisplay(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF111827),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    dateTimeStr,
                                    style: GoogleFonts.inter(
                                        fontSize: 11, color: Colors.grey[600]),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      _buildChannelPill(channel),
                                      const SizedBox(width: 6),
                                      _buildPaymentStatusPill(paymentStatus),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),

                          const SizedBox(height: 24),
                          const Divider(height: 1, color: Color(0xFFE5E7EB)),
                          const SizedBox(height: 24),

                          // Billed To & Recipient / Delivery Address
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('BILLED TO',
                                        style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey[400],
                                            letterSpacing: 0.8)),
                                    const SizedBox(height: 6),
                                    Text(billedToName,
                                        style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF1F2937))),
                                    Text(billedToEmail,
                                        style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: Colors.grey[600])),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('RECIPIENT / DELIVERY ADDRESS',
                                        style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey[400],
                                            letterSpacing: 0.8)),
                                    const SizedBox(height: 6),
                                    Text(deliveryAddress,
                                        style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: const Color(0xFF374151),
                                            height: 1.4)),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 28),

                          // Itemized Table
                          Table(
                            columnWidths: const {
                              0: FlexColumnWidth(3),
                              1: FlexColumnWidth(1),
                              2: FlexColumnWidth(1.5),
                              3: FlexColumnWidth(1.5),
                            },
                            children: [
                              TableRow(
                                decoration: const BoxDecoration(
                                    border: Border(
                                        bottom: BorderSide(
                                            color: Color(0xFFE5E7EB),
                                            width: 1))),
                                children: [
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8),
                                      child: Text('ITEM',
                                          style: _tableHeaderStyle())),
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8),
                                      child: Text('QTY',
                                          textAlign: TextAlign.center,
                                          style: _tableHeaderStyle())),
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8),
                                      child: Text('UNIT PRICE',
                                          textAlign: TextAlign.right,
                                          style: _tableHeaderStyle())),
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8),
                                      child: Text('LINE TOTAL',
                                          textAlign: TextAlign.right,
                                          style: _tableHeaderStyle())),
                                ],
                              ),
                              if (items.isEmpty) ...[
                                _buildSampleRow('Red Rose', 7, 100.0, 700.0),
                                _buildSampleRow(
                                    'Frontera Bouquet', 2, 350.0, 700.0),
                              ] else
                                ...items.map((item) {
                                  final name = item['name'] ??
                                      item['title'] ??
                                      'Product Item';
                                  final qty = (item['quantity'] ??
                                      item['qty'] ??
                                      1) as int;
                                  final price = (item['price'] ??
                                          item['unitPrice'] ??
                                          0.0)
                                      .toDouble();
                                  final lineTotal = price * qty;
                                  return _buildSampleRow(
                                      name, qty, price, lineTotal);
                                }),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // Subtotal, Delivery Fee & Total Amount
                          Align(
                            alignment: Alignment.centerRight,
                            child: SizedBox(
                              width: 250,
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Subtotal',
                                          style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: Colors.grey[600])),
                                      Text('₱${subtotal.toStringAsFixed(2)}',
                                          style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFF374151))),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Delivery Fee',
                                          style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: Colors.grey[600])),
                                      Text('₱${deliveryFee.toStringAsFixed(2)}',
                                          style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFF374151))),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  const Divider(height: 1),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Total',
                                          style: GoogleFonts.inter(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF111827))),
                                      Text('₱${totalAmount.toStringAsFixed(2)}',
                                          style: GoogleFonts.playfairDisplay(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFFD97706))),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Proof of Delivery section if present
                          if (podPhoto != null && podPhoto.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            const Divider(height: 1),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const Icon(Icons.verified,
                                    color: Colors.green, size: 18),
                                const SizedBox(width: 6),
                                Text('PROOF OF DELIVERY (POD)',
                                    style: GoogleFonts.inter(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: Colors.green)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                height: 140,
                                width: double.infinity,
                                color: Colors.grey[200],
                                child: _buildImageFromBase64OrUrl(podPhoto),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('Received By: $podRecipient',
                                style: GoogleFonts.inter(
                                    fontSize: 12, fontWeight: FontWeight.bold)),
                            Text('Courier / Driver: $courierName',
                                style: GoogleFonts.inter(
                                    fontSize: 12, color: Colors.grey[600])),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  TextStyle _tableHeaderStyle() {
    return GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: Colors.grey[400],
        letterSpacing: 0.5);
  }

  TableRow _buildSampleRow(
      String item, int qty, double unitPrice, double lineTotal) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(item,
              style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1F2937))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text('$qty',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 13, color: const Color(0xFF4B5563))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text('₱${unitPrice.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                  fontSize: 13, color: const Color(0xFF4B5563))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text('₱${lineTotal.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1F2937))),
        ),
      ],
    );
  }

  Widget _buildImageFromBase64OrUrl(String strData) {
    try {
      if (strData.startsWith('data:image') || strData.contains(';base64,')) {
        final base64Str = strData.split(',').last;
        final bytes = base64Decode(base64Str);
        return Image.memory(bytes, fit: BoxFit.cover);
      } else if (strData.startsWith('http://') ||
          strData.startsWith('https://')) {
        return Image.network(strData,
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) =>
                const Icon(Icons.broken_image, size: 40));
      } else {
        final bytes = base64Decode(strData);
        return Image.memory(bytes, fit: BoxFit.cover);
      }
    } catch (e) {
      return Container(
        color: Colors.grey[300],
        child:
            const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
      );
    }
  }

  // PDF Printing & Download logic using pdf and printing packages
  Future<void> _printInvoice(Map<String, dynamic> order) async {
    final pdf = await _generatePdfDocument(order);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  Future<void> _downloadPdf(
      BuildContext context, Map<String, dynamic> order) async {
    final pdf = await _generatePdfDocument(order);
    final rawId =
        (order['id'] ?? order['orderId'] ?? order['invoiceNumber'] ?? 'invoice')
            .toString();
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Invoice_$rawId.pdf',
    );
  }

  Future<pw.Document> _generatePdfDocument(Map<String, dynamic> order) async {
    final pdf = pw.Document();
    final rawId =
        (order['id'] ?? order['orderId'] ?? order['invoiceNumber'] ?? '')
            .toString();
    final displayInvoice =
        rawId.length > 10 ? '#${rawId.substring(0, 10)}' : '#$rawId';
    final customer =
        order['customerName'] ?? order['billedTo'] ?? 'prinsqtpotato';
    final email =
        order['customerEmail'] ?? order['email'] ?? 'prinsqtpotato@gmail.com';
    final address = order['deliveryAddress'] ??
        '64 Lias Road, Central Luzon, Bulacan, Marilao, Lias, Postal Code: 3019';
    final items = (order['items'] as List<dynamic>?) ?? [];
    final subtotal =
        (order['subtotal'] ?? order['totalPrice'] ?? 1400.0).toDouble();
    final deliveryFee =
        (order['deliveryFee'] ?? order['delivery_fee'] ?? 80.0).toDouble();
    final total = (order['totalAmount'] ??
            order['total_amount'] ??
            (subtotal + deliveryFee))
        .toDouble();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(30),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('BLOOMINOUS',
                            style: pw.TextStyle(
                                fontSize: 24, fontWeight: pw.FontWeight.bold)),
                        pw.Text('Order / Receipt Invoice',
                            style: const pw.TextStyle(
                                fontSize: 12, color: PdfColors.grey700)),
                      ],
                    ),
                    pw.Text(displayInvoice,
                        style: pw.TextStyle(
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.amber800)),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Divider(),
                pw.SizedBox(height: 10),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('BILLED TO:',
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 10)),
                          pw.Text(customer,
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 12)),
                          pw.Text(email,
                              style: const pw.TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('DELIVERY ADDRESS:',
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 10)),
                          pw.Text(address,
                              style: const pw.TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.TableHelper.fromTextArray(
                  headers: ['ITEM', 'QTY', 'UNIT PRICE', 'LINE TOTAL'],
                  data: items.isEmpty
                      ? [
                          ['Red Rose', '7', 'P100.00', 'P700.00'],
                          ['Frontera Bouquet', '2', 'P350.00', 'P700.00'],
                        ]
                      : items.map((i) {
                          final name = i['name'] ?? i['title'] ?? 'Item';
                          final qty =
                              (i['quantity'] ?? i['qty'] ?? 1).toString();
                          final price =
                              (i['price'] ?? i['unitPrice'] ?? 0.0).toDouble();
                          return [
                            name,
                            qty,
                            'P${price.toStringAsFixed(2)}',
                            'P${(price * (i['quantity'] ?? 1)).toStringAsFixed(2)}'
                          ];
                        }).toList(),
                ),
                pw.SizedBox(height: 20),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Container(
                    width: 200,
                    child: pw.Column(
                      children: [
                        pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('Subtotal:'),
                              pw.Text('P${subtotal.toStringAsFixed(2)}')
                            ]),
                        pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('Delivery Fee:'),
                              pw.Text('P${deliveryFee.toStringAsFixed(2)}')
                            ]),
                        pw.Divider(),
                        pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('TOTAL:',
                                  style: pw.TextStyle(
                                      fontWeight: pw.FontWeight.bold)),
                              pw.Text('P${total.toStringAsFixed(2)}',
                                  style: pw.TextStyle(
                                      fontWeight: pw.FontWeight.bold,
                                      color: PdfColors.amber800)),
                            ]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    return pdf;
  }
}
