import 'package:flutter/material.dart';
import 'saved_address_service.dart';

/// What the customer chose in the "My Address" sheet. The checkout screen
/// reads this and decides what to do next.
enum SavedAddressAction {
  use, // "Confirm" — fill the checkout form with this address
  edit, // "Edit" — fill the form, then let the customer change and update it
  addNew, // "Add New Address" — start a blank address
}

class SavedAddressSheetResult {
  final SavedAddressAction action;
  final SavedAddress? address; // null only for addNew
  const SavedAddressSheetResult(this.action, [this.address]);
}

/// Opens the "My Address" bottom sheet (the app's version of the website popup).
/// Returns null when the customer simply dismisses it.
Future<SavedAddressSheetResult?> showSavedAddressesSheet(
    BuildContext context, {
      String? selectedId,
    }) {
  return showModalBottomSheet<SavedAddressSheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SavedAddressesSheet(selectedId: selectedId),
  );
}

class _SavedAddressesSheet extends StatefulWidget {
  final String? selectedId;
  const _SavedAddressesSheet({this.selectedId});

  @override
  State<_SavedAddressesSheet> createState() => _SavedAddressesSheetState();
}

class _SavedAddressesSheetState extends State<_SavedAddressesSheet> {
  static const Color _accent = Color(0xFFF4B400);

  String? _pickedId; // the radio button the customer tapped
  String? _busyId; // the address currently being deleted / made default
  String? _error; // shown inside the sheet (a SnackBar would hide behind it)

  @override
  void initState() {
    super.initState();
    _pickedId = widget.selectedId;
  }

  Future<void> _makeDefault(SavedAddress a) async {
    setState(() {
      _busyId = a.id;
      _error = null;
    });
    try {
      await SavedAddressService.setDefault(a.id);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not set the default address: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _confirmDelete(SavedAddress a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this address?'),
        content: Text('${a.fullName}\n${a.address}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('KEEP')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busyId = a.id;
      _error = null;
    });
    try {
      await SavedAddressService.delete(a.id);
      if (_pickedId == a.id) _pickedId = null;
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not delete the address: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('My Address',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)),
              const SizedBox(height: 4),
              Text('Pick where this order should go, or add a new address.',
                  style: TextStyle(fontSize: 12, color: subColor)),
              const SizedBox(height: 12),

              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(isDark ? 0.15 : 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
                ),

              // The list is a live stream: delete or "set default" and it redraws by itself.
              Flexible(
                child: StreamBuilder<List<SavedAddress>>(
                  stream: SavedAddressService.watch(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('Could not load your addresses: ${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator(color: _accent)),
                      );
                    }

                    final addresses = snapshot.data!;
                    if (addresses.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Column(
                          children: [
                            Icon(Icons.location_off_outlined, size: 36, color: subColor),
                            const SizedBox(height: 8),
                            Text('No saved addresses yet.',
                                style: TextStyle(fontWeight: FontWeight.w600, color: textColor)),
                            const SizedBox(height: 4),
                            Text('Fill in your delivery details and tick "Save this address".',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: subColor)),
                          ],
                        ),
                      );
                    }

                    // If the chosen address was just deleted, nothing is selected.
                    final pickedStillExists = addresses.any((a) => a.id == _pickedId);

                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: addresses.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final a = addresses[i];
                        final selected = pickedStillExists && a.id == _pickedId;
                        final busy = _busyId == a.id;

                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: busy ? null : () => setState(() => _pickedId = a.id),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF262626) : const Color(0xFFF8F8F6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selected ? _accent : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2, right: 10),
                                  child: Icon(
                                    selected ? Icons.radio_button_checked : Icons.radio_button_off,
                                    color: selected ? _accent : subColor,
                                    size: 20,
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(a.fullName,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold, fontSize: 14, color: textColor)),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(a.phone, style: TextStyle(fontSize: 12, color: subColor)),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(a.address,
                                          style: TextStyle(fontSize: 12, height: 1.35, color: subColor)),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          if (a.isDefault)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                border: Border.all(color: _accent),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text('Default',
                                                  style: TextStyle(
                                                      fontSize: 10, fontWeight: FontWeight.bold, color: _accent)),
                                            )
                                          else
                                            GestureDetector(
                                              onTap: busy ? null : () => _makeDefault(a),
                                              child: Text('Set as default',
                                                  style: TextStyle(
                                                      fontSize: 11, color: subColor, decoration: TextDecoration.underline)),
                                            ),
                                          if (busy)
                                            const SizedBox(
                                                width: 12,
                                                height: 12,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: _accent)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  children: [
                                    TextButton(
                                      onPressed: busy
                                          ? null
                                          : () => Navigator.pop(
                                          context, SavedAddressSheetResult(SavedAddressAction.edit, a)),
                                      style: TextButton.styleFrom(
                                          minimumSize: Size.zero,
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                                      child: const Text('Edit', style: TextStyle(color: _accent, fontSize: 12)),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: busy ? null : () => _confirmDelete(a),
                                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.pop(context, const SavedAddressSheetResult(SavedAddressAction.addNew)),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add New Address'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: const BorderSide(color: _accent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 10),

              // Confirm needs the latest list to find the chosen address, so it reads
              // it fresh instead of keeping a second copy that could go stale.
              ElevatedButton(
                onPressed: (_pickedId == null || _busyId != null)
                    ? null
                    : () async {
                  final all = await SavedAddressService.fetchAll();
                  final match = all.where((a) => a.id == _pickedId).toList();
                  if (!context.mounted) return;
                  if (match.isEmpty) {
                    setState(() => _error = 'That address is no longer available. Please pick another.');
                    return;
                  }
                  Navigator.pop(context, SavedAddressSheetResult(SavedAddressAction.use, match.first));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: const Color(0xFF121212),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('CONFIRM', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
