import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

class InvoiceDetailPage extends StatefulWidget {
  final String orderId;
  final String role;
  final String? autoAction; // 'print' | 'download' | null

  const InvoiceDetailPage({super.key, required this.orderId, required this.role, this.autoAction});

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  bool _autoActionDone = false;
  bool _isProcessing = false;

  final GlobalKey _invoiceKey = GlobalKey();

  String _peso(dynamic n) => '₱${(n ?? 0).toDouble().toStringAsFixed(2)}';

  Future<Uint8List?> _captureInvoiceImage() async {
    try {
      final boundary = _invoiceKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      return null;
    }
  }

  Future<pw.Document> _buildPdfFromImage(Uint8List pngBytes) async {
    final pdf = pw.Document();
    final image = pw.MemoryImage(pngBytes);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (context) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
      ),
    );
    return pdf;
  }

  Future<void> _printInvoice() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final bytes = await _captureInvoiceImage();
      if (bytes == null) {
        _showMessage('Could not capture the invoice for printing.');
        return;
      }
      final pdf = await _buildPdfFromImage(bytes);
      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _downloadPdf(String invoiceId) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final bytes = await _captureInvoiceImage();
      if (bytes == null) {
        _showMessage('Could not capture the invoice.');
        return;
      }
      final pdf = await _buildPdfFromImage(bytes);
      final pdfBytes = await pdf.save();

      final dir = await getApplicationDocumentsDirectory();
      final safeName = invoiceId.replaceAll(RegExp(r'[^\w\-]'), '_');
      final file = File('${dir.path}/$safeName.pdf');
      await file.writeAsBytes(pdfBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved $safeName.pdf to app storage.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      _showMessage('Download failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showMessage(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isAdmin = widget.role == 'admin' || widget.role == 'super-admin' || widget.role == 'employee';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text('Invoice', style: GoogleFonts.cormorantGaramond(fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? Colors.black : const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      // FIXED: SafeArea wraps the whole body so the Print/Download button
      // row never renders underneath the phone's on-screen gesture/nav bar.
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('orders').doc(widget.orderId).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)));
            }
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Center(child: Text('Order not found.'));
            }

            final o = snapshot.data!.data() as Map<String, dynamic>;

            final paymentStatus = (o['paymentStatus'] ?? ((o['status'] ?? '') == 'cancelled' ? 'Voided' : 'Pending')).toString();
            final channel = (o['type'] == 'POS') ? 'Walk-In' : 'Online';
            final invoiceId = (o['invoiceId'] ?? '#${widget.orderId.length > 10 ? widget.orderId.substring(0, 10) : widget.orderId}').toString();
            final branch = (o['branchId'] ?? 'Main Branch').toString();
            final paymentMethod = (o['payment_method'] ?? 'Not recorded').toString();
            final customerName = (o['customer_name'] ?? o['customerName'] ?? 'Walk-in Customer').toString();
            final customerEmail = (o['email'] ?? o['customer_email'] ?? (channel == 'Walk-In' ? 'Walk-in (no email on file)' : 'N/A')).toString();
            final address = (o['address'] ?? (channel == 'Walk-In' ? 'Walk-in — no delivery' : 'No delivery address provided')).toString();
            final items = (o['items'] as List?) ?? [];
            final rawDate = o['createdAt'] ?? o['timestamp'];
            final dateStr = rawDate is Timestamp ? DateFormat('MMM d, yyyy, h:mm a').format(rawDate.toDate()) : 'N/A';

            double subtotal = (o['subtotal'] as num?)?.toDouble() ??
                items.fold<double>(0, (s, i) => s + ((i['price'] ?? 0).toDouble() * (i['qty'] ?? 0)));
            final shippingFee = (o['shipping_fee'] as num?)?.toDouble();
            final total = (o['total_price'] ?? o['total_amount'] ?? subtotal).toDouble();

            final podUrl = (o['podPhotoUrl'] ?? o['deliveryPhoto'])?.toString();
            final courier = (o['courierName'] ?? o['podCourier'] ?? '—').toString();
            final podRecipient = (o['podRecipient'] ?? o['recipientName'] ?? '—').toString();
            final podDateRaw = o['podTimestamp'] ?? o['deliveredAt'];
            final podDateStr = podDateRaw is Timestamp ? DateFormat('MMM d, yyyy, h:mm a').format(podDateRaw.toDate()) : '—';

            if (!_autoActionDone && widget.autoAction != null) {
              _autoActionDone = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (widget.autoAction == 'print') {
                  _printInvoice();
                } else if (widget.autoAction == 'download') {
                  _downloadPdf(invoiceId);
                }
              });
            }

            return SingleChildScrollView(
              // FIXED: extra bottom padding beyond SafeArea's own inset so
              // the button row has visible breathing room above the nav bar.
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    children: [
                      RepaintBoundary(
                        key: _invoiceKey,
                        child: Stack(
                          children: [
                            // Invoice card colors are hardcoded LIGHT always
                            // — a receipt is a fixed business document, not
                            // a themed UI screen, so it never follows dark
                            // mode regardless of the app's current theme.
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LayoutBuilder(builder: (context, c) {
                                    final narrow = c.maxWidth < 500;
                                    final brandCol = Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('BLOOMINOUS',
                                            style: GoogleFonts.cormorantGaramond(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFFD4AF37))),
                                        const SizedBox(height: 4),
                                        Text(branch, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                                        const SizedBox(height: 8),
                                        Text('PAYMENT METHOD', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 0.5)),
                                        Text(paymentMethod, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87)),
                                      ],
                                    );
                                    final numCol = Column(
                                      crossAxisAlignment: narrow ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                                      children: [
                                        Text(invoiceId, style: GoogleFonts.cormorantGaramond(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
                                        const SizedBox(height: 4),
                                        Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                        const SizedBox(height: 8),
                                        Wrap(spacing: 6, children: [
                                          _pill(channel, channel == 'Walk-In' ? Colors.deepPurple.withValues(alpha: 0.12) : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                              channel == 'Walk-In' ? Colors.deepPurple[700]! : const Color(0xFFB45309)),
                                          _pill(paymentStatus, _statusBg(paymentStatus), _statusFg(paymentStatus)),
                                        ]),
                                      ],
                                    );
                                    return narrow
                                        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [brandCol, const SizedBox(height: 16), numCol])
                                        : Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                      Flexible(child: brandCol),
                                      const SizedBox(width: 16),
                                      Flexible(child: numCol),
                                    ]);
                                  }),
                                  const SizedBox(height: 20),
                                  Divider(color: Colors.grey.withValues(alpha: 0.2)),
                                  const SizedBox(height: 20),

                                  LayoutBuilder(builder: (context, c) {
                                    final narrow = c.maxWidth < 500;
                                    final billed = Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('BILLED TO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 0.5)),
                                        const SizedBox(height: 4),
                                        Text(customerName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                                        Text(customerEmail, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                                      ],
                                    );
                                    final addr = Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('RECIPIENT / DELIVERY ADDRESS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 0.5)),
                                        const SizedBox(height: 4),
                                        Text(address, style: TextStyle(fontSize: 12, color: Colors.grey[800])),
                                      ],
                                    );
                                    return narrow
                                        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [billed, const SizedBox(height: 16), addr])
                                        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: billed), const SizedBox(width: 16), Expanded(child: addr)]);
                                  }),
                                  const SizedBox(height: 24),

                                  Text('ITEMS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 0.5)),
                                  const SizedBox(height: 8),
                                  if (items.isEmpty)
                                    Text('No items on this invoice.', style: TextStyle(color: Colors.grey[500], fontStyle: FontStyle.italic))
                                  else
                                    ...items.map((it) {
                                      final name = (it['name'] ?? 'Item').toString();
                                      final qty = (it['qty'] ?? 0) as num;
                                      final price = (it['price'] ?? 0.0).toDouble();
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                        child: Row(
                                          children: [
                                            Expanded(flex: 3, child: Text(name, style: const TextStyle(color: Colors.black87))),
                                            Expanded(flex: 1, child: Text('x$qty', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500]))),
                                            Expanded(flex: 2, child: Text(_peso(price * qty), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87))),
                                          ],
                                        ),
                                      );
                                    }),
                                  const Divider(height: 24),

                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: SizedBox(
                                      width: 260,
                                      child: Column(
                                        children: [
                                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                            Text('Subtotal', style: TextStyle(color: Colors.grey[500])),
                                            Text(_peso(subtotal), style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
                                          ]),
                                          if (shippingFee != null) ...[
                                            const SizedBox(height: 6),
                                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                              Text('Delivery Fee', style: TextStyle(color: Colors.grey[500])),
                                              Text(_peso(shippingFee), style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
                                            ]),
                                          ],
                                          const SizedBox(height: 10),
                                          const Divider(),
                                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                            Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                                            Text(_peso(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFFF59E0B))),
                                          ]),
                                        ],
                                      ),
                                    ),
                                  ),

                                  if (podUrl != null && podUrl.isNotEmpty) ...[
                                    const SizedBox(height: 24),
                                    Divider(color: Colors.grey.withValues(alpha: 0.2)),
                                    const SizedBox(height: 16),
                                    Row(children: [
                                      const Icon(Icons.local_shipping, size: 16, color: Colors.green),
                                      const SizedBox(width: 6),
                                      Text('PROOF OF DELIVERY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 0.5)),
                                    ]),
                                    const SizedBox(height: 10),
                                    LayoutBuilder(builder: (context, c) {
                                      final narrow = c.maxWidth < 450;
                                      final img = ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: SizedBox(width: narrow ? double.infinity : 130, height: 130, child: _buildImage(podUrl)),
                                      );
                                      final info = Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Courier: $courier', style: const TextStyle(color: Colors.black87)),
                                          const SizedBox(height: 4),
                                          Text('Delivered: $podDateStr', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                                          const SizedBox(height: 4),
                                          Text('Received by: $podRecipient', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                                        ],
                                      );
                                      return narrow
                                          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [img, const SizedBox(height: 12), info])
                                          : Row(children: [img, const SizedBox(width: 16), Expanded(child: info)]);
                                    }),
                                  ],

                                  if (isAdmin && (o['locked'] == true)) ...[
                                    const SizedBox(height: 16),
                                    Row(children: [
                                      const Icon(Icons.lock, size: 12, color: Colors.grey),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'This invoice is finalized — changes can only be made through the Void module.',
                                          style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ]),
                                  ],
                                ],
                              ),
                            ),
                            if (paymentStatus == 'Voided')
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Center(
                                    child: Transform.rotate(
                                      angle: -0.4,
                                      child: Text('VOIDED',
                                          style: TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: Colors.red.withValues(alpha: 0.08), letterSpacing: 8)),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _isProcessing ? null : _printInvoice,
                            icon: _isProcessing
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.print, size: 16),
                            label: const Text('Reprint'),
                          ),
                          ElevatedButton.icon(
                            onPressed: _isProcessing ? null : () => _downloadPdf(invoiceId),
                            icon: _isProcessing
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.download, size: 16),
                            label: const Text('Download PDF'),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _pill(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  Color _statusBg(String s) => s == 'Paid' ? Colors.green.withValues(alpha: 0.12) : s == 'Pending' ? Colors.amber.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.15);
  Color _statusFg(String s) => s == 'Paid' ? Colors.green[700]! : s == 'Pending' ? Colors.amber[800]! : Colors.grey[700]!;

  Widget _buildImage(String url) {
    if (url.startsWith('data:') || url.contains(';base64,')) {
      try {
        return Image.memory(base64Decode(url.split(',').last), fit: BoxFit.cover);
      } catch (_) {
        return const Icon(Icons.broken_image);
      }
    }
    return Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image));
  }
}