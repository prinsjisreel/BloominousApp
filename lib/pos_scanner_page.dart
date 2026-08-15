import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'inventory_data.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:barcode_widget/barcode_widget.dart' as qr;
import 'sound_helper.dart';

class POSScannerPage extends StatefulWidget {
  const POSScannerPage({super.key});

  @override
  State<POSScannerPage> createState() => _POSScannerPageState();
}

class _POSScannerPageState extends State<POSScannerPage> {
  bool _isScanning = true;
  bool _isTorchOn = false;
  String? _selectedCustomerId;
  String? _selectedCustomerEmail;
  String? _lastScannedCode;

  final MobileScannerController cameraController = MobileScannerController(
    formats: [BarcodeFormat.all],
    autoStart: true,
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  final List<Map<String, dynamic>> _checkoutItems = [];
  double _totalPrice = 0;
  String _paymentMethod = 'Cash'; // Default

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  void _showManualEntryDialog() {
    final TextEditingController codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Manual SKU Entry',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: codeController,
          decoration: InputDecoration(
            hintText: 'e.g., BLOOM-003',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: const Icon(Icons.edit_note_rounded),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('CANCEL', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () {
              final code = codeController.text.trim().toUpperCase();
              if (code.isNotEmpty) {
                Navigator.pop(context);
                _processScannedCode(code);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black, foregroundColor: Colors.white),
            child: const Text('ADD TO LIST'),
          ),
        ],
      ),
    );
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (!_isScanning) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final String? code = barcode.rawValue;
      if (code != null && code.isNotEmpty) {
        setState(() {
          _isScanning = false;
          _lastScannedCode = code;
        });

        SoundHelper.playBeep();
        _processScannedCode(code);

        // Re-enable scanning after a short delay
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _isScanning = true);
        });
        break;
      }
    }
  }

  Future<void> _processScannedCode(String code) async {
    final cleanCode = code.trim();

    // Check if it's a customer QR (Format: BLOOM-CUST-UID)
    if (cleanCode.toUpperCase().startsWith('BLOOM-CUST-')) {
      final uid = cleanCode.substring('BLOOM-CUST-'.length).trim();

      // Show immediate feedback
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Checking Customer QR...'),
            duration: Duration(milliseconds: 500)),
      );

      // Try finding customer data
      try {
        final customerDoc =
            await InventoryData.getCustomerLoyaltyDocStream(uid).first;
        if (customerDoc != null) {
          setState(() {
            _selectedCustomerId = uid;
            _selectedCustomerEmail = customerDoc['email'] ?? 'Member';
          });
          _showStatusMessage('Customer Linked: $_selectedCustomerEmail',
              isError: false);
        } else {
          _showStatusMessage('Unknown Customer QR', isError: true);
        }
      } catch (e) {
        _showStatusMessage('Error linking customer', isError: true);
      }
      return;
    }

    // Otherwise treat as Product SKU
    try {
      final product = await InventoryData.getProductByCode(cleanCode);
      if (product != null) {
        _addItemToCheckout(product);
      } else {
        _showStatusMessage('Product not found: $cleanCode', isError: true);
      }
    } catch (e) {
      _showStatusMessage('Error looking up product: $e', isError: true);
    }
  }

  void _addItemToCheckout(Map<String, dynamic> product) {
    setState(() {
      // Check if already in list
      final index =
          _checkoutItems.indexWhere((item) => item['id'] == product['id']);
      if (index != -1) {
        _checkoutItems[index]['quantity'] += 1;
      } else {
        _checkoutItems.add({
          'id': product['id'],
          'name': product['name'],
          'price': product['price'],
          'quantity': 1,
          'image': product['image'],
          'sku': product['code'],
        });
      }
      _calculateTotal();
    });
    _showStatusMessage('Added: ${product['name']}', isError: false);
  }

  void _calculateTotal() {
    double total = 0;
    for (var item in _checkoutItems) {
      total += (item['price'] * item['quantity']);
    }
    setState(() => _totalPrice = total);
  }

  void _showStatusMessage(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildCorner({required bool top, required bool left}) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        border: Border(
          top: top
              ? const BorderSide(color: Colors.white, width: 4)
              : BorderSide.none,
          bottom: !top
              ? const BorderSide(color: Colors.white, width: 4)
              : BorderSide.none,
          left: left
              ? const BorderSide(color: Colors.white, width: 4)
              : BorderSide.none,
          right: !left
              ? const BorderSide(color: Colors.white, width: 4)
              : BorderSide.none,
        ),
        borderRadius: BorderRadius.only(
          topLeft: top && left ? const Radius.circular(20) : Radius.zero,
          topRight: top && !left ? const Radius.circular(20) : Radius.zero,
          bottomLeft: !top && left ? const Radius.circular(20) : Radius.zero,
          bottomRight: !top && !left ? const Radius.circular(20) : Radius.zero,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8DC),
      appBar: AppBar(
        title: const Text('POS Scanner',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off),
            onPressed: () {
              cameraController.toggleTorch();
              setState(() => _isTorchOn = !_isTorchOn);
            },
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_rounded),
            onPressed: _showManualEntryDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: Stack(
              children: [
                MobileScanner(
                    controller: cameraController, onDetect: _onBarcodeDetected),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                  ),
                ),
                // if (_lastScannedCode != null)
                //   Positioned(
                //     top: 20,
                //     left: 0,
                //     right: 0,
                //     child: Center(
                //       child: Container(
                //         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                //         decoration: BoxDecoration(
                //           color: Colors.black87,
                //           borderRadius: BorderRadius.circular(20),
                //         ),
                //         child: Text(
                //           'Last Scan: $_lastScannedCode',
                //           style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                //         ),
                //       ),
                //     ),
                //   ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: _isScanning
                                  ? Colors.white24
                                  : const Color(0xFFF4B400).withOpacity(0.5),
                              width: 1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                                top: 0,
                                left: 0,
                                child: _buildCorner(top: true, left: true)),
                            Positioned(
                                top: 0,
                                right: 0,
                                child: _buildCorner(top: true, left: false)),
                            Positioned(
                                bottom: 0,
                                left: 0,
                                child: _buildCorner(top: false, left: true)),
                            Positioned(
                                bottom: 0,
                                right: 0,
                                child: _buildCorner(top: false, left: false)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _isScanning
                              ? Colors.black45
                              : const Color(0xFFF4B400),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _isScanning ? 'ALIGN BARCODE HERE' : 'PROCESSING...',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: _selectedCustomerId != null
                          ? Colors.blue.withOpacity(0.1)
                          : Colors.grey[100],
                      borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(30),
                          topRight: Radius.circular(30)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _selectedCustomerId != null
                              ? Icons.verified_user_rounded
                              : Icons.person_add_rounded,
                          color: _selectedCustomerId != null
                              ? Colors.blue
                              : Colors.grey,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _selectedCustomerEmail ??
                                'Scan loyalty card to link customer',
                            style: TextStyle(
                              color: _selectedCustomerId != null
                                  ? Colors.blue
                                  : Colors.grey[600],
                              fontWeight: _selectedCustomerId != null
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (_selectedCustomerId != null)
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() {
                              _selectedCustomerId = null;
                              _selectedCustomerEmail = null;
                            }),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _checkoutItems.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.shopping_basket_outlined,
                                    size: 48, color: Colors.grey[300]),
                                const SizedBox(height: 12),
                                Text('Waiting for items...',
                                    style: TextStyle(color: Colors.grey[400])),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _checkoutItems.length,
                            itemBuilder: (context, index) {
                              final item = _checkoutItems[index];
                              return ListTile(
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    item['image'] ??
                                        'https://via.placeholder.com/50',
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.image),
                                  ),
                                ),
                                title: Text(item['name'],
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                    '₱${item['price']} x ${item['quantity']}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                        '₱${(item['price'] * item['quantity']).toStringAsFixed(2)}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900)),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.remove_circle_outline,
                                          color: Colors.red,
                                          size: 20),
                                      onPressed: () {
                                        setState(() {
                                          if (item['quantity'] > 1) {
                                            item['quantity'] -= 1;
                                          } else {
                                            _checkoutItems.removeAt(index);
                                          }
                                          _calculateTotal();
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, -5))
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Estimated Total',
                                style: TextStyle(
                                    fontSize: 16, color: Colors.grey)),
                            Text('₱${_totalPrice.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.w900)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _checkoutItems.isEmpty
                                    ? null
                                    : _showPaymentDialog,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                ),
                                child: const Text('CHECKOUT NOW',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1)),
                              ),
                            ),
                          ],
                        ),
                      ],
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

  void _showPaymentDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 24),
                  const Text('Payment Method',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  _buildPaymentOption(
                      'Cash',
                      Icons.payments_rounded,
                      _paymentMethod == 'Cash',
                      () => setModalState(() => _paymentMethod = 'Cash')),
                  _buildPaymentOption(
                      'GCash / Maya',
                      Icons.qr_code_2_rounded,
                      _paymentMethod == 'E-Wallet',
                      () => setModalState(() => _paymentMethod = 'E-Wallet')),
                  const SizedBox(height: 30),
                  if (_paymentMethod == 'E-Wallet')
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(20)),
                      child: Column(
                        children: [
                          qr.BarcodeWidget(
                            barcode: qr.Barcode.qrCode(),
                            data:
                                'POS-PAYMENT-${_totalPrice.toStringAsFixed(2)}',
                            width: 150,
                            height: 150,
                          ),
                          const SizedBox(height: 12),
                          const Text('Scan to pay with QRPH',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _processTransaction,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('CONFIRM PAYMENT',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPaymentOption(
      String title, IconData icon, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isSelected ? Colors.green : Colors.grey[200]!, width: 2),
          color: isSelected ? Colors.green.withOpacity(0.05) : Colors.white,
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Colors.green : Colors.grey),
            const SizedBox(width: 16),
            Text(title,
                style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal)),
            const Spacer(),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: Colors.green),
          ],
        ),
      ),
    );
  }

  Future<void> _processTransaction() async {
    Navigator.pop(context); // Close bottom sheet

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
          child: CircularProgressIndicator(color: Color(0xFFF4B400))),
    );

    try {
      final orderId = "POS-${DateTime.now().millisecondsSinceEpoch}";
      final employee = FirebaseAuth.instance.currentUser;

      // 1. Process Stock Decrement
      for (var item in _checkoutItems) {
        await InventoryData.decrementStock(item['id'], item['quantity']);
      }

      // 2. Add to Orders Collection
      await FirebaseFirestore.instance.collection('orders').doc(orderId).set({
        'orderId': orderId,
        'items': _checkoutItems,
        'totalAmount': _totalPrice,
        'paymentMethod': _paymentMethod,
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt':
            FieldValue.serverTimestamp(), // Also add createdAt for consistency
        'status': 'completed',
        'type': 'pos',
        'processedBy': employee?.email ?? 'System',
        'customerId': _selectedCustomerId,
        'branchId': InventoryData
            .selectedBranchId, // Crucial for multi-branch filtering
      });

      // 3. Award Loyalty Points if customer is linked
      if (_selectedCustomerId != null) {
        int pointsGained = (_totalPrice / 100)
            .floor(); // Default fallback: 1 point per 100 PHP

        try {
          final configDoc = await FirebaseFirestore.instance
              .collection('settings')
              .doc('loyalty_config')
              .get();
          if (configDoc.exists) {
            final data = configDoc.data();
            final maxProducts = data?['max_products_eligible'] ?? 5;
            final pointsForMax = data?['points_per_max_purchase'] ?? 50;

            // Count the total number of items in the transaction
            int totalItemsInCart = 0;
            for (var item in _checkoutItems) {
              totalItemsInCart +=
                  (item['quantity'] as num? ?? item['qty'] as num? ?? 1)
                      .toInt();
            }

            if (totalItemsInCart >= maxProducts) {
              pointsGained = (pointsForMax as num).toInt();
              print(
                  'Loyalty Config Triggered! Earned custom max purchase reward: $pointsGained points');
            }
          }
        } catch (e) {
          print('Error fetching loyalty points config: $e');
        }

        if (pointsGained > 0) {
          await InventoryData.updateCustomerLoyalty(
              customerId: _selectedCustomerId!, points: pointsGained);
        }
      }

      if (mounted) {
        Navigator.pop(context); // Close loading
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        _showStatusMessage('Transaction Failed: $e', isError: true);
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.green, size: 80),
            const SizedBox(height: 20),
            const Text('Payment Successful',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _checkoutItems.clear();
                  _totalPrice = 0;
                  _selectedCustomerId = null;
                  _selectedCustomerEmail = null;
                  _lastScannedCode = null;
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50)),
              child: const Text('NEW TRANSACTION'),
            ),
          ],
        ),
      ),
    );
  }
}
