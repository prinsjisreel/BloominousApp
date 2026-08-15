import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'inventory_data.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SpoilageTrackerPage extends StatefulWidget {
  final String? initialProductId;
  const SpoilageTrackerPage({super.key, this.initialProductId});

  @override
  State<SpoilageTrackerPage> createState() => _SpoilageTrackerPageState();
}

class _SpoilageTrackerPageState extends State<SpoilageTrackerPage> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedProductId;
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();
  double _lossAmount = 0.0;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedProductId = widget.initialProductId;
    if (_selectedProductId != null) {
      InventoryData.inventoryStream().first.then((products) {
        if (mounted) _calculateLoss(products);
      });
    }
  }

  final List<String> _reasons = [
    'Natural Wilting',
    'Damaged during delivery',
    'Handling Error',
    'Pest/Disease',
    'Salvaged / Reusable Scraps',
    'Other'
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text('SPOILAGE TRACKER',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1.2)),
            FutureBuilder<Map<String, dynamic>?>(
                future: InventoryData.getBranchDetails(
                    InventoryData.selectedBranchId ?? 'main_branch'),
                builder: (context, snapshot) {
                  final name = snapshot.data?['name'] ??
                      (InventoryData.selectedBranchId == null
                          ? 'All Branches'
                          : 'Main Branch');
                  return Text('Viewing: $name',
                      style: const TextStyle(fontSize: 10, color: Colors.grey));
                }),
          ],
        ),
        centerTitle: true,
        backgroundColor: isDark ? Colors.black : const Color(0xFF121212),
        foregroundColor: const Color(0xFFF4B400),
        elevation: 0,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: InventoryData.spoilageStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFFF4B400)));
          }

          final spoilageHistory = snapshot.data ?? [];
          double totalLoss = 0;
          int totalWasted = 0;

          for (var item in spoilageHistory) {
            totalLoss += (item['loss_amount'] as num? ?? 0.0).toDouble();
            totalWasted += (item['quantity'] as num? ?? 0).toInt();
          }

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryCards(totalLoss, totalWasted),
                      const SizedBox(height: 30),
                      _buildReportForm(isDark),
                      const SizedBox(height: 30),
                      const Text(
                        'SPOILAGE HISTORY',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 1.0),
                      ),
                      const SizedBox(height: 15),
                    ],
                  ),
                ),
              ),
              if (spoilageHistory.isEmpty)
                const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 60.0),
                      child: Column(
                        children: [
                          Icon(Icons.eco_rounded, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No spoilage recorded yet.',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = spoilageHistory[index];
                      return _buildHistoryItem(item, isDark);
                    },
                    childCount: spoilageHistory.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryCards(double totalLoss, int totalWasted) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'TOTAL LOSS',
            '₱${NumberFormat('#,###.00').format(totalLoss)}',
            Colors.redAccent,
            Icons.trending_down_rounded,
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: _buildStatCard(
            'WASTED QTY',
            '$totalWasted pcs',
            Colors.orangeAccent,
            Icons.delete_sweep_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String title, String value, Color color, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(title,
              style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Widget _buildReportForm(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.redAccent.withOpacity(0.1)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('REPORT WILTED/DAMAGED',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            const SizedBox(height: 20),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: InventoryData.inventoryStream(),
              builder: (context, snapshot) {
                final products = snapshot.data ?? [];
                return DropdownButtonFormField<String>(
                  value: _selectedProductId,
                  decoration: _inputDecoration(
                      'Select Product', Icons.local_florist_rounded),
                  items: products.map<DropdownMenuItem<String>>((p) {
                    return DropdownMenuItem<String>(
                      value: p['id'] as String,
                      child: Text('${p['name']} (Stock: ${p['stock']})'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedProductId = val;
                      _calculateLoss(products);
                    });
                  },
                  validator: (val) => val == null ? 'Required' : null,
                );
              },
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration('Qty', Icons.numbers_rounded),
                    onChanged: (val) {
                      InventoryData.inventoryStream().first.then((products) {
                        _calculateLoss(products);
                      });
                    },
                    validator: (val) =>
                        (val == null || val.isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black : Colors.grey[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('LOSS AMOUNT',
                            style: TextStyle(
                                fontSize: 9,
                                color: Colors.grey[500],
                                fontWeight: FontWeight.w800)),
                        Text('₱${_lossAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Colors.redAccent)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            DropdownButtonFormField<String>(
              value: _reasonController.text.isEmpty
                  ? null
                  : _reasonController.text,
              decoration:
                  _inputDecoration('Reason', Icons.info_outline_rounded),
              items: _reasons
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (val) {
                setState(() {
                  _reasonController.text = val ?? '';
                  InventoryData.inventoryStream().first.then((products) {
                    _calculateLoss(products);
                  });
                });
              },
              validator: (val) =>
                  (val == null || val.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('SAVE REPORT & DEDUCT STOCK',
                        style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: isDark ? Colors.black : Colors.grey[50],
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.1))),
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    );
  }

  void _calculateLoss(List<Map<String, dynamic>> products) {
    if (_selectedProductId == null || _quantityController.text.isEmpty) {
      setState(() => _lossAmount = 0.0);
      return;
    }

    try {
      final product = products.firstWhere((p) => p['id'] == _selectedProductId);
      final price = (product['price'] ?? 0.0).toDouble();
      final qty = int.tryParse(_quantityController.text) ?? 0;
      final reason = _reasonController.text;

      if (reason == 'Salvaged / Reusable Scraps') {
        setState(() => _lossAmount = 0.0);
      } else {
        setState(() => _lossAmount = price * qty);
      }
    } catch (e) {
      setState(() => _lossAmount = 0.0);
    }
  }

  Future<void> _saveReport() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final products = await InventoryData.inventoryStream().first;
      final product = products.firstWhere((p) => p['id'] == _selectedProductId);
      final qty = int.parse(_quantityController.text);

      if (qty > (product['stock'] ?? 0)) {
        throw Exception('Quantity exceeds current stock!');
      }

      final user = FirebaseAuth.instance.currentUser;
      final userData = await InventoryData.getUserData(user?.uid ?? '');
      final isSalvaged = _reasonController.text == 'Salvaged / Reusable Scraps';

      await InventoryData.reportSpoilage(
        productId: _selectedProductId!,
        flowerName: product['name'] ?? 'Unknown',
        quantity: qty,
        lossAmount: _lossAmount,
        reason: _reasonController.text,
        reportedBy: userData?['name'] ?? user?.email ?? 'Staff',
        isSalvaged: isSalvaged,
      );

      if (mounted) {
        final successMsg = isSalvaged
            ? 'Items salvaged and added to Recycled Flowers inventory!'
            : 'Spoilage recorded successfully!';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMsg), backgroundColor: Colors.green),
        );
        _formKey.currentState!.reset();
        _reasonController.clear();
        _quantityController.clear();
        setState(() {
          _selectedProductId = null;
          _lossAmount = 0.0;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildHistoryItem(Map<String, dynamic> item, bool isDark) {
    final rawDate = item['createdAt'] ?? item['created_at'];
    final date =
        rawDate != null ? (rawDate as dynamic).toDate() : DateTime.now();

    final isSalvaged = item['is_salvaged'] == true ||
        item['reason'] == 'Salvaged / Reusable Scraps';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 5,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSalvaged
                  ? Colors.green.withOpacity(0.1)
                  : Colors.redAccent.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
                isSalvaged
                    ? Icons.recycling_rounded
                    : Icons.delete_outline_rounded,
                color: isSalvaged ? Colors.green : Colors.redAccent,
                size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item['flower_name'] ?? 'Unknown',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    if (isSalvaged)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('SALVAGED',
                            style: TextStyle(
                                color: Colors.green,
                                fontSize: 8,
                                fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                Text(
                  '${item['quantity']} pcs • ${item['reason']}',
                  style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 11,
                      fontWeight: FontWeight.w500),
                ),
                Text(
                  'By: ${item['reported_by']}',
                  style: TextStyle(color: Colors.grey[400], fontSize: 9),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₱${NumberFormat('#,###.00').format(item['loss_amount'] ?? 0.0)}',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: isSalvaged ? Colors.green : Colors.redAccent,
                    fontSize: 14),
              ),
              Text(
                DateFormat('MMM dd, yyyy').format(date),
                style: TextStyle(color: Colors.grey[400], fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
