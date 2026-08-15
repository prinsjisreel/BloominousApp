import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'inventory_data.dart';
import 'spoilage_tracker_page.dart';
import 'kiri_service.dart';

class InventoryPage extends StatefulWidget {
  final String role;
  const InventoryPage({super.key, this.role = 'employee'});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  void _showItemDialog([Map<String, dynamic>? item]) {
    final isEditing = item != null;
    final nameController =
        TextEditingController(text: isEditing ? item['name'] : '');
    final codeController =
        TextEditingController(text: isEditing ? item['code'] : '');
    final priceController =
        TextEditingController(text: isEditing ? item['price'].toString() : '');
    final stockController =
        TextEditingController(text: isEditing ? item['stock'].toString() : '');
    String? selectedCategory = isEditing ? item['category'] : 'Flowers';

    final List<String> categories = [
      'Flowers',
      'Chocolates',
      'Stuffed Toys',
      'Wines',
      'Bouquets',
      'Other Items'
    ];

    final addStockController = TextEditingController(text: '0');
    final modelController =
        TextEditingController(text: isEditing ? (item['model'] ?? '') : '');
    final imageController =
        TextEditingController(text: isEditing ? (item['image'] ?? '') : '');
    String generationStatus = '';

    final isAdmin = widget.role == 'admin' || widget.role == 'super-admin';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          title: Text(isEditing
              ? (isAdmin ? 'Edit Product' : 'Product Details')
              : 'Add New Product'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    enabled: isAdmin,
                    controller: nameController,
                    decoration: const InputDecoration(
                        labelText: 'Name (e.g., Red Rose)')),
                TextField(
                    enabled: isAdmin,
                    controller: codeController,
                    decoration:
                        const InputDecoration(labelText: 'Barcode/SKU')),
                TextField(
                    enabled: isAdmin,
                    controller: priceController,
                    decoration: const InputDecoration(labelText: 'Price'),
                    keyboardType: TextInputType.number),
                TextField(
                    enabled: isAdmin,
                    controller: stockController,
                    decoration:
                        const InputDecoration(labelText: 'Stock Quantity'),
                    keyboardType: TextInputType.number),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: categories.map((String category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
                  onChanged: !isAdmin
                      ? null
                      : (String? newValue) {
                          setDialogState(() {
                            selectedCategory = newValue;
                          });
                        },
                ),
                const Divider(height: 30),
                const Text("3D & VISUALS",
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
                TextField(
                    enabled: isAdmin,
                    controller: modelController,
                    decoration: const InputDecoration(
                      labelText: '3D Model Path (.glb URL)',
                      hintText: 'https://...',
                      helperText: 'Enter path or URL to .glb file',
                    )),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.help_outline,
                        size: 16, color: Color(0xFFF59E0B)),
                    label: const Text(
                      'How do I add models from Hyper3D (hyper3d.ai)?',
                      style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFF59E0B),
                          fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Row(
                            children: [
                              Icon(Icons.auto_awesome,
                                  color: Color(0xFFF59E0B)),
                              SizedBox(width: 8),
                              Text('Hyper3D.ai Guide'),
                            ],
                          ),
                          content: const SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'How to add custom 3D flower models from hyper3d.ai:',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                ),
                                SizedBox(height: 12),
                                Text(
                                    '1. Go to hyper3d.ai on your browser and create your 3D flower model.',
                                    style: TextStyle(fontSize: 12)),
                                SizedBox(height: 6),
                                Text(
                                    '2. Download or export the completed asset in .glb format.',
                                    style: TextStyle(fontSize: 12)),
                                SizedBox(height: 6),
                                Text(
                                    '3. Upload the .glb file to any free file-hosting service (like Firebase Storage, Discord, Dropbox, or GitHub) to get a public link.',
                                    style: TextStyle(fontSize: 12)),
                                SizedBox(height: 6),
                                Text(
                                    '4. Copy the direct download link (make sure it ends with .glb).',
                                    style: TextStyle(fontSize: 12)),
                                SizedBox(height: 6),
                                Text(
                                    '5. Paste that direct link in the "3D Model Path" field here!',
                                    style: TextStyle(fontSize: 12)),
                                SizedBox(height: 12),
                                Text(
                                    'Note: No coding is required! Once saved, the 3D flower will render immediately in the AR builder.',
                                    style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        fontSize: 11,
                                        color: Colors.grey)),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('GOT IT'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (isAdmin)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: Text(generationStatus.isEmpty
                          ? 'AUTO-GENERATE 3D'
                          : generationStatus),
                      onPressed: generationStatus.isNotEmpty
                          ? null
                          : () async {
                              final picker = ImagePicker();
                              final pickedFile = await picker.pickImage(
                                  source: ImageSource.gallery);
                              if (pickedFile != null) {
                                // Prompt for Kiri API key dynamically
                                final keyController = TextEditingController(
                                    text:
                                        'kiri_R20FEsh6d9JAMTznxYICltXe5d3sioHNA6bq');
                                final userKey = await showDialog<String>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text(
                                        'KIRI Engine Secret Key Required'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                            'Please paste your active KIRI Engine API Secret Key from kiriengine.app/api/keys to run photogrammetry:'),
                                        const SizedBox(height: 14),
                                        TextField(
                                          controller: keyController,
                                          obscureText: true,
                                          style: const TextStyle(fontSize: 13),
                                          decoration: const InputDecoration(
                                            labelText:
                                                'Secret Key (kiri_sk_...)',
                                            prefixIcon: Icon(Icons.key,
                                                color: Colors.purple),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text('CANCEL')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.purple,
                                            foregroundColor: Colors.white),
                                        onPressed: () => Navigator.pop(
                                            ctx, keyController.text.trim()),
                                        child: const Text('PROCEED'),
                                      ),
                                    ],
                                  ),
                                );

                                if (userKey == null ||
                                    userKey.isEmpty ||
                                    userKey.contains('placeholder')) {
                                  return;
                                }

                                try {
                                  setDialogState(() => generationStatus =
                                      'Initializing Kiri...');
                                  final service = KiriService(userKey);
                                  final glbUrl = await service.generateModel(
                                    File(pickedFile.path),
                                    onStatusUpdate: (status) {
                                      setDialogState(
                                          () => generationStatus = status);
                                    },
                                  );

                                  // Save history record
                                  await InventoryData.saveTripoModel({
                                    'name': nameController.text.isNotEmpty
                                        ? nameController.text
                                        : 'Kiri generated flower model',
                                    'url': glbUrl,
                                    'type': 'kiri_image_to_3d',
                                    'userId': 'admin_uploader',
                                  });

                                  setDialogState(() {
                                    modelController.text = glbUrl;
                                    generationStatus = '';
                                  });
                                } catch (e) {
                                  setDialogState(
                                      () => generationStatus = 'Error!');
                                  await Future.delayed(
                                      const Duration(seconds: 3));
                                  setDialogState(() => generationStatus = '');

                                  if (context.mounted) {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text(
                                            'KIRI Generation Failsafe'),
                                        content: Text(
                                          'Error details: $e\n\n'
                                          'Alternative (Adviser Plan A): Use Polycam, Luma, or Kiri on your mobile device to scan the flower, export .glb, host it, and paste its URL directly.',
                                        ),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx),
                                              child: const Text('OK')),
                                        ],
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                    ),
                  ),
                TextField(
                    enabled: isAdmin,
                    controller: imageController,
                    decoration: const InputDecoration(
                        labelText: 'Image URL',
                        hintText: 'https://...',
                        helperText: 'URL for the 2D preview image')),
                if (!isAdmin && isEditing) ...[
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  TextField(
                    controller: addStockController,
                    decoration: const InputDecoration(
                      labelText: 'Add Stock (+)',
                      suffixText: 'units',
                      helperText: 'Enter amount to ADD to current stock',
                      border: OutlineInputBorder(),
                      prefixIcon:
                          Icon(Icons.add_business_rounded, color: Colors.green),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(isAdmin ? 'CANCEL' : 'CLOSE')),
            if (isAdmin)
              ElevatedButton(
                onPressed: () async {
                  final data = {
                    'name': nameController.text,
                    'code': codeController.text,
                    'price': double.tryParse(priceController.text) ?? 0.0,
                    'stock': int.tryParse(stockController.text) ?? 0,
                    'category': selectedCategory,
                    'model': modelController.text,
                    'image': imageController.text,
                    'branchId': InventoryData.selectedBranchId,
                  };
                  if (isEditing) {
                    await InventoryData.updateProduct(item['id'], data);
                  } else {
                    await InventoryData.addProduct(data);
                  }
                  if (mounted) Navigator.pop(context);
                },
                child: const Text('SAVE'),
              ),
            if (!isAdmin && isEditing)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white),
                onPressed: () async {
                  final amount = int.tryParse(addStockController.text) ?? 0;
                  if (amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Please enter a positive number to add stock'),
                          backgroundColor: Colors.red),
                    );
                    return;
                  }

                  final currentStock = item['stock'] ?? 0;
                  final newStock = currentStock + amount;

                  await InventoryData.updateProduct(
                      item['id'], {'stock': newStock});
                  if (mounted) Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Increased stock by $amount units'),
                        backgroundColor: Colors.green),
                  );
                },
                child: const Text('ADD STOCK'),
              ),
          ],
        );
      }),
    );
  }

  void _showArchiveConfirmDialog(
      BuildContext context, Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive Item?'),
        content: const Text(
            'Are you sure you want to archive/deactivate this product? This hides it from active inventory but keeps historic data for reports.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL')),
          TextButton(
            onPressed: () async {
              await InventoryData.deleteProduct(item['id']);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('ARCHIVE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isAdmin = widget.role == 'admin' || widget.role == 'super-admin';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          children: [
            const Text('Inventory Management', style: TextStyle(fontSize: 16)),
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
        backgroundColor: isDark ? Colors.black : const Color(0xFFF59E0B),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: InventoryData.inventoryStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Center(child: Text('Error: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());

          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      size: 60, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No items in this branch inventory',
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 8),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final has3D =
                  item['model'] != null && item['model'].toString().isNotEmpty;
              final isRecycled = item['name'] == 'Recycled Bouquet';

              return Card(
                elevation: isRecycled ? 2 : 0,
                color: isRecycled ? Colors.green[50] : null,
                child: ListTile(
                  leading: item['image'] != null &&
                          item['image'].toString().isNotEmpty
                      ? Image.network(item['image'],
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.image))
                      : const Icon(Icons.image),
                  title: Row(
                    children: [
                      Text(item['name']),
                      if (has3D) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.view_in_ar,
                            size: 16, color: Colors.blue),
                      ]
                    ],
                  ),
                  subtitle: Text('Stock: ${item['stock']}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete_sweep_rounded,
                            color: Colors.orangeAccent, size: 20),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => SpoilageTrackerPage(
                                    initialProductId: item['id'])),
                          );
                        },
                        tooltip: 'Report Spoilage',
                      ),
                      if (isAdmin)
                        IconButton(
                          icon: const Icon(Icons.archive_outlined,
                              color: Colors.redAccent, size: 20),
                          onPressed: () =>
                              _showArchiveConfirmDialog(context, item),
                          tooltip: 'Archive Item',
                        ),
                      Text('₱${item['price']}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  onTap: () => _showItemDialog(item),
                  onLongPress: !isAdmin
                      ? null
                      : () => _showArchiveConfirmDialog(context, item),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: () => _showItemDialog(),
              backgroundColor: const Color(0xFFF59E0B),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }
}
