import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'inventory_data.dart';

class ShopLocationPage extends StatefulWidget {
  final String role;
  const ShopLocationPage({super.key, this.role = 'admin'});

  @override
  State<ShopLocationPage> createState() => _ShopLocationPageState();
}

class _ShopLocationPageState extends State<ShopLocationPage> {
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MANAGE BRANCH LOCATIONS'),
        centerTitle: true,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: InventoryData.getBranchesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final branches = snapshot.data ?? [];
          if (branches.isEmpty) {
            return const Center(child: Text('No branches found.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: branches.length,
            itemBuilder: (context, index) {
              final branch = branches[index];
              return _BranchLocationCard(branch: branch, role: widget.role);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddBranchDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddBranchDialog(BuildContext context) {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Branch'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Branch Name'),
            ),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                await InventoryData.addBranch({
                  'name': nameController.text,
                  'address': addressController.text,
                  'latitude': null,
                  'longitude': null,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _BranchLocationCard extends StatefulWidget {
  final Map<String, dynamic> branch;
  final String role;
  const _BranchLocationCard({required this.branch, required this.role});

  @override
  State<_BranchLocationCard> createState() => _BranchLocationCardState();
}

class _BranchLocationCardState extends State<_BranchLocationCard> {
  final addressController = TextEditingController();
  final latController = TextEditingController();
  final lngController = TextEditingController();
  bool isUpdating = false;

  @override
  void initState() {
    super.initState();
    addressController.text = widget.branch['address'] ?? '';
    latController.text =
        (widget.branch['latitude'] as double?)?.toString() ?? '';
    lngController.text =
        (widget.branch['longitude'] as double?)?.toString() ?? '';
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      setState(() {
        latController.text = position.latitude.toString();
        lngController.text = position.longitude.toString();
      });
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _openGoogleMaps() async {
    final url = Uri.parse('https://www.google.com/maps');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _save() async {
    setState(() => isUpdating = true);
    final double? finalLat = double.tryParse(latController.text);
    final double? finalLng = double.tryParse(lngController.text);

    try {
      await InventoryData.updateBranch(widget.branch['id'], {
        'latitude': finalLat,
        'longitude': finalLng,
        'address': addressController.text,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Branch details updated!')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Update failed: $e')));
    } finally {
      setState(() => isUpdating = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Branch'),
        content:
            Text('Are you sure you want to delete ${widget.branch['name']}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await InventoryData.deleteBranch(widget.branch['id']);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(widget.branch['name'] ?? 'Unknown Branch',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete, color: Colors.grey),
                  tooltip: 'Delete Branch',
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(
                  labelText: 'Address', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: latController,
                    decoration: const InputDecoration(
                        labelText: 'Latitude', border: OutlineInputBorder()),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: lngController,
                    decoration: const InputDecoration(
                        labelText: 'Longitude', border: OutlineInputBorder()),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _openGoogleMaps,
                  icon: const Icon(Icons.map, size: 18),
                  label: const Text('Find on Map'),
                ),
                TextButton.icon(
                  onPressed: _getCurrentLocation,
                  icon: const Icon(Icons.my_location, size: 18),
                  label: const Text('Capture Current'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isUpdating ? null : _save,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white),
                child: isUpdating
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('UPDATE BRANCH LOCATION'),
              ),
            ),
            const SizedBox(height: 12),
            if (widget.role == 'super-admin')
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _migrateDataHere,
                  icon: const Icon(Icons.move_to_inbox, size: 18),
                  label: const Text('MIGRATE CURRENT DATA HERE'),
                  style:
                      OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _migrateDataHere() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Migrate All Data?'),
        content: Text(
            'This will copy all products, categories, and inventory from the default "main_branch" to ${widget.branch['name']}. Orders will also be updated. This is irreversible.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Proceed Migration'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => isUpdating = true);
      try {
        await InventoryData.migrateDataToBranch(widget.branch['id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Data migration successful!')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Migration failed: $e')));
        }
      } finally {
        setState(() => isUpdating = false);
      }
    }
  }
}
