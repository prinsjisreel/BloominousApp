import 'package:flutter/material.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'inventory_data.dart';

class BarcodeGeneratorPage extends StatefulWidget {
  const BarcodeGeneratorPage({super.key});

  @override
  State<BarcodeGeneratorPage> createState() => _BarcodeGeneratorPageState();
}

class _BarcodeGeneratorPageState extends State<BarcodeGeneratorPage> {
  final List<String> _barcodeList = [];
  final TextEditingController _manualController = TextEditingController();
  final TextEditingController _prefixController =
      TextEditingController(text: 'BLOOM-');

  void _addBarcode(String data) {
    if (data.trim().isEmpty) return;
    setState(() {
      if (!_barcodeList.contains(data.trim())) {
        _barcodeList.add(data.trim());
      }
    });
    _manualController.clear();
  }

  void _removeBarcode(int index) {
    setState(() {
      _barcodeList.removeAt(index);
    });
  }

  void _clearAll() {
    setState(() {
      _barcodeList.clear();
    });
  }

  Future<void> _bulkGenerate() async {
    int start = 1;
    int count = 3;
    final startController = TextEditingController(text: '1');
    final countController = TextEditingController(text: '3');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bulk Generate Barcodes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _prefixController,
              decoration:
                  const InputDecoration(labelText: 'Prefix (e.g., BLOOM-)'),
            ),
            TextField(
              controller: startController,
              decoration: const InputDecoration(labelText: 'Start Number'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: countController,
              decoration: const InputDecoration(labelText: 'Quantity'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              int s = int.tryParse(startController.text) ?? 1;
              int c = int.tryParse(countController.text) ?? 3;
              String prefix = _prefixController.text.trim();

              setState(() {
                for (int i = 0; i < c; i++) {
                  String code = '$prefix${(s + i).toString().padLeft(3, '0')}';
                  if (!_barcodeList.contains(code)) {
                    _barcodeList.add(code);
                  }
                }
              });
              Navigator.pop(context);
            },
            child: const Text('GENERATE'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportToPdf() async {
    if (_barcodeList.isEmpty) return;

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text('BLOOMINOUS Barcode Labels',
                  style: pw.TextStyle(
                      fontSize: 24, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 20),
            pw.GridView(
              crossAxisCount: 3,
              childAspectRatio: 1.5,
              children: _barcodeList.map((data) {
                return pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey),
                  ),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.code128(),
                        data: data,
                        width: 120,
                        height: 50,
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(data,
                          style: pw.TextStyle(
                              fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save());
  }

  Future<void> _showInventoryPicker() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Text(
                      'Select Items',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Playfair Display',
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('DONE'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: InventoryData.inventoryStream(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());
                    final items = snapshot.data!;
                    return ListView.builder(
                      controller: scrollController,
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final barcode = item['sku'] ?? item['id'];
                        final isAdded = _barcodeList.contains(barcode);

                        return ListTile(
                          leading: Icon(
                            isAdded
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            color: isAdded ? Colors.green : Colors.grey,
                          ),
                          title: Text(item['name'] ?? 'Unnamed Product'),
                          subtitle: Text('Barcode: $barcode'),
                          onTap: () {
                            setState(() {
                              if (isAdded) {
                                _barcodeList.remove(barcode);
                              } else {
                                _barcodeList.add(barcode);
                              }
                            });
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch Barcode Generator',
            style: TextStyle(fontFamily: 'Playfair Display')),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_barcodeList.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.print),
              onPressed: _exportToPdf,
              tooltip: 'Export to PDF',
            ),
          if (_barcodeList.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _clearAll,
              tooltip: 'Clear All',
            ),
        ],
      ),
      body: Column(
        children: [
          _buildInputSection(isDark),
          Expanded(
            child: _barcodeList.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _barcodeList.length,
                    itemBuilder: (context, index) => _BarcodeCard(
                      data: _barcodeList[index],
                      onDelete: () => _removeBarcode(index),
                      index: index + 1,
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            onPressed: _bulkGenerate,
            heroTag: 'bulk',
            backgroundColor: Colors.blue[800],
            icon: const Icon(Icons.auto_awesome, color: Colors.white),
            label: const Text('BULK GENERATE (PREFIX)',
                style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            onPressed: _showInventoryPicker,
            heroTag: 'inventory',
            backgroundColor: Colors.orange[800],
            icon: const Icon(Icons.add_shopping_cart, color: Colors.white),
            label: const Text('PICK FROM INVENTORY',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildInputSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[50],
        border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _manualController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.qr_code_2),
                hintText: 'Enter SKU or ID',
                filled: true,
                fillColor: isDark ? Colors.black26 : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: _addBarcode,
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filled(
            onPressed: () {
              String data = _manualController.text.trim();
              if (data.isNotEmpty) {
                _addBarcode(data);
              }
            },
            icon: const Icon(Icons.add),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_scanner,
              size: 80, color: Colors.grey.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            'Enter data above or pick from inventory\nto generate barcodes',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _bulkGenerate,
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('BULK GENERATE BLOOM- ITEMS'),
          ),
        ],
      ),
    );
  }
}

class _BarcodeCard extends StatelessWidget {
  final String data;
  final VoidCallback onDelete;
  final int index;
  final GlobalKey _cardKey = GlobalKey();

  _BarcodeCard(
      {required this.data, required this.onDelete, required this.index});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[200],
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  'Barcode $index',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                  onPressed: onDelete,
                  color: Colors.red[300],
                ),
                IconButton(
                  icon: const Icon(Icons.share_outlined, size: 20),
                  onPressed: () => _shareBarcode(context),
                  color: Colors.blue[300],
                ),
              ],
            ),
          ),
          RepaintBoundary(
            key: _cardKey,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[200],
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  BarcodeWidget(
                    barcode: Barcode.code128(),
                    data: data,
                    width: double.infinity,
                    height: 100,
                    drawText: true,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareBarcode(BuildContext context) async {
    try {
      RenderRepaintBoundary boundary =
          _cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/barcode_$data.png').create();
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles([XFile(file.path)], text: 'Barcode for $data');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing barcode: $e')),
      );
    }
  }
}
