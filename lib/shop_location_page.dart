import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'inventory_data.dart';

/// Sensible limits for a branch's delivery radius (in kilometres).
/// The customer checkout and submit_order.php both read the same
/// `deliveryRadiusKm` field on branches/{branchId}.
const double kMinDeliveryRadiusKm = 0.5;
const double kMaxDeliveryRadiusKm = 200;

/// One shared rule for "is this branch location valid?", used by BOTH the
/// Add Branch dialog and the Update button on a branch card, so they can
/// never disagree. Returns a message when something is wrong, or null when
/// everything is fine.
String? _validateBranchGeo({
  required double? lat,
  required double? lng,
  required double? radiusKm,
}) {
  if (lat == null || lng == null) {
    return 'Please enter the branch latitude and longitude. The delivery radius is measured from this point.';
  }
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    return 'Latitude must be between -90 and 90, and longitude between -180 and 180.';
  }
  if (radiusKm == null) {
    return 'Please enter a delivery radius in kilometres.';
  }
  if (radiusKm < kMinDeliveryRadiusKm || radiusKm > kMaxDeliveryRadiusKm) {
    return 'Delivery radius must be between ${kMinDeliveryRadiusKm.toStringAsFixed(1)} and ${kMaxDeliveryRadiusKm.toStringAsFixed(0)} km.';
  }
  return null;
}

/// Asks for GPS permission and returns the phone's current position,
/// or throws a readable message.
Future<Position> _readCurrentPosition() async {
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw 'Location permission was denied.';
  }
  return Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
}

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
            // Extra bottom space so the last card is never hidden behind the
            // floating "+" button or the phone's gesture bar.
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, 100 + MediaQuery.of(context).viewPadding.bottom),
            itemCount: branches.length,
            itemBuilder: (context, index) {
              final branch = branches[index];
              return _BranchLocationCard(
                // The key ties each card to its branch, so editing one card
                // never leaks its text into another when the list changes.
                key: ValueKey(branch['id']),
                branch: branch,
                role: widget.role,
              );
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
    showDialog(
      context: context,
      builder: (context) => const _AddBranchDialog(),
    );
  }
}

/// "Add New Branch" form. Name, address, coordinates and delivery radius are
/// ALL required: the radius is what tells the app and the server which
/// customers this branch is allowed to deliver to.
class _AddBranchDialog extends StatefulWidget {
  const _AddBranchDialog();

  @override
  State<_AddBranchDialog> createState() => _AddBranchDialogState();
}

class _AddBranchDialogState extends State<_AddBranchDialog> {
  final nameController = TextEditingController();
  final addressController = TextEditingController();
  final latController = TextEditingController();
  final lngController = TextEditingController();
  final radiusController = TextEditingController();

  String? errorText;
  bool isLocating = false;
  bool isSaving = false;

  // The dialog owns its controllers, so it is also the one that disposes
  // them - after its closing animation, never while it is still on screen.
  @override
  void dispose() {
    nameController.dispose();
    addressController.dispose();
    latController.dispose();
    lngController.dispose();
    radiusController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      isLocating = true;
      errorText = null;
    });
    try {
      final position = await _readCurrentPosition();
      if (!mounted) return;
      setState(() {
        latController.text = position.latitude.toString();
        lngController.text = position.longitude.toString();
      });
    } catch (e) {
      if (mounted) setState(() => errorText = 'Could not get location: $e');
    } finally {
      if (mounted) setState(() => isLocating = false);
    }
  }

  Future<void> _submit() async {
    final name = nameController.text.trim();
    final address = addressController.text.trim();
    final lat = double.tryParse(latController.text.trim());
    final lng = double.tryParse(lngController.text.trim());
    final radius = double.tryParse(radiusController.text.trim());

    if (name.isEmpty) {
      setState(() => errorText = 'Please enter the branch name.');
      return;
    }
    final geoProblem = _validateBranchGeo(lat: lat, lng: lng, radiusKm: radius);
    if (geoProblem != null) {
      setState(() => errorText = geoProblem);
      return;
    }

    setState(() {
      isSaving = true;
      errorText = null;
    });
    try {
      await InventoryData.addBranch({
        'name': name,
        'address': address,
        // BloominousWeb's branch page reads `location`, so keep both in step.
        'location': address,
        'latitude': lat,
        'longitude': lng,
        'deliveryRadiusKm': radius,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          isSaving = false;
          errorText = 'Could not add the branch: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New Branch'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Branch Name *'),
            ),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: latController,
                    decoration: const InputDecoration(labelText: 'Latitude *'),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: lngController,
                    decoration: const InputDecoration(labelText: 'Longitude *'),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: isLocating ? null : _useCurrentLocation,
                icon: isLocating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location, size: 18),
                label: const Text('Use my current location'),
              ),
            ),
            TextField(
              controller: radiusController,
              decoration: const InputDecoration(
                labelText: 'Delivery Radius (km) *',
                helperText:
                    'Customers farther than this from the branch cannot order delivery.',
                helperMaxLines: 2,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            if (errorText != null) ...[
              const SizedBox(height: 12),
              Text(errorText!,
                  style: const TextStyle(color: Colors.red, fontSize: 12.5)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: isSaving ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: isSaving ? null : _submit,
          child: isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add'),
        ),
      ],
    );
  }
}

class _BranchLocationCard extends StatefulWidget {
  final Map<String, dynamic> branch;
  final String role;
  const _BranchLocationCard(
      {super.key, required this.branch, required this.role});

  @override
  State<_BranchLocationCard> createState() => _BranchLocationCardState();
}

class _BranchLocationCardState extends State<_BranchLocationCard> {
  final addressController = TextEditingController();
  final latController = TextEditingController();
  final lngController = TextEditingController();
  final radiusController = TextEditingController();
  bool isUpdating = false;

  // Older branches were created before radius existed.
  bool get _hasRadius => (widget.branch['deliveryRadiusKm'] as num?) != null;

  @override
  void initState() {
    super.initState();
    addressController.text =
        (widget.branch['address'] ?? widget.branch['location'] ?? '').toString();
    // `as num?` (not `as double?`): Firestore hands back a whole number such
    // as 15 as an int, and casting an int to double would crash the card.
    latController.text = (widget.branch['latitude'] as num?)?.toString() ?? '';
    lngController.text = (widget.branch['longitude'] as num?)?.toString() ?? '';
    radiusController.text =
        (widget.branch['deliveryRadiusKm'] as num?)?.toString() ?? '';
  }

  @override
  void dispose() {
    addressController.dispose();
    latController.dispose();
    lngController.dispose();
    radiusController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await _readCurrentPosition();
      if (!mounted) return;
      setState(() {
        latController.text = position.latitude.toString();
        lngController.text = position.longitude.toString();
      });
    } catch (e) {
      if (!mounted) return;
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
    final double? finalLat = double.tryParse(latController.text.trim());
    final double? finalLng = double.tryParse(lngController.text.trim());
    final double? finalRadius = double.tryParse(radiusController.text.trim());

    // Same rule as the Add dialog: no saving a branch without a usable
    // point and radius, because customers are checked against them.
    final problem =
        _validateBranchGeo(lat: finalLat, lng: finalLng, radiusKm: finalRadius);
    if (problem != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(problem)));
      return;
    }

    setState(() => isUpdating = true);
    try {
      await InventoryData.updateBranch(widget.branch['id'], {
        'latitude': finalLat,
        'longitude': finalLng,
        'deliveryRadiusKm': finalRadius,
        'address': addressController.text.trim(),
        'location': addressController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Branch details updated!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    } finally {
      if (mounted) setState(() => isUpdating = false);
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
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: lngController,
                    decoration: const InputDecoration(
                        labelText: 'Longitude', border: OutlineInputBorder()),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: radiusController,
              decoration: InputDecoration(
                labelText: 'Delivery Radius (km)',
                border: const OutlineInputBorder(),
                helperText: _hasRadius
                    ? 'Customers farther than this cannot order delivery from this branch.'
                    : 'Not set yet: this branch currently delivers to ANY distance. Enter a radius to limit it.',
                helperMaxLines: 3,
                helperStyle:
                    TextStyle(color: _hasRadius ? null : Colors.orange[800]),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
        if (mounted) setState(() => isUpdating = false);
      }
    }
  }
}
