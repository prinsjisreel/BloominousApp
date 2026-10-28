import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

import 'inventory_data.dart';
import 'app_sidebar.dart';
import 'invoice_portal_page.dart';
import 'override_code_service.dart';
import 'admin_audit_service.dart';
import 'proof_of_order_viewer.dart';

class OrdersPage extends StatefulWidget {
  final String role;
  const OrdersPage({super.key, this.role = 'employee'});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  int _selectedTab = 0;
  final TextEditingController _filterController = TextEditingController();
  String _searchFilter = '';

  String? _selectedBranchId;
  String? _branchName = 'Loading...';

  final OverrideCodeService _overrideCodeService = OverrideCodeService();

  // Daily walk-in cancellation threshold before an override code is
  // required — scoped PER BRANCH, so it's a shared pool across every
  // employee working there that day, not an individual quota. Catches
  // patterns spread across colluding staff, matching how a real manager
  // oversees a whole shift's void activity, not one cashier in
  // isolation.
  static const int _dailyCancelLimit = 3;

  @override
  void initState() {
    super.initState();
    _initializeBranch();
  }

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

      if (bId != null) {
        final bDetails = await InventoryData.getBranchDetails(bId);
        if (mounted) {
          setState(() {
            _selectedBranchId = bId;
            _branchName = bDetails?['name'] ?? 'Assigned Branch';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _branchName = 'No Branch Assigned';
          });
        }
      }
    }
  }

  // Mirrors web's isOnlineOrder(o): (o.type || 'WEB') !== 'POS'.
  bool _isOnlineOrder(Map<String, dynamic> o) {
    final type = (o['type'] ?? 'WEB').toString().toUpperCase();
    return type != 'POS';
  }

  // Statuses that mean "this order is finished". The web writes 'confirmed',
  // the app writes 'COMPLETED' — both must count as final on both sides.
  static const List<String> _finalStatuses = ['COMPLETED', 'CONFIRMED', 'DELIVERED', 'CANCELLED'];

  /// Reads the order fresh from Firestore (not the list on screen, which may
  /// be a second behind) and says whether somebody already finalised it —
  /// for example another employee, or the web page, a moment ago.
  Future<bool> _isAlreadyFinal(String orderId) async {
    try {
      final snap = await FirebaseFirestore.instance.collection('orders').doc(orderId).get();
      final data = snap.data();
      if (data == null) return false;
      final status = (data['status'] ?? '').toString().toUpperCase();
      return data['locked'] == true || _finalStatuses.contains(status);
    } catch (_) {
      // Can't check (offline?) — let the real write decide.
      return false;
    }
  }

  void _showAlreadyFinalMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This order is already final and can no longer be changed.'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // STATUS FLOW — mirrors STATUS_FLOW in order_management.php (web)
  // ---------------------------------------------------------------------
  // The position in each list is the step number. A "next" button only ever
  // moves an order ONE position forward, so a stage can never be skipped.
  //   Online  : Pending -> Processing -> Prepared -> In Transit -> Confirmed
  //             (Confirmed is set by the driver's proof of delivery, not here)
  //   Walk-in : Pending -> Processing -> Prepared -> Confirmed
  //             (+ a separate Cancel button any time before Confirmed)
  static const List<String> _onlineFlow = ['PENDING', 'PROCESSING', 'PREPARED', 'IN TRANSIT', 'CONFIRMED'];
  static const List<String> _walkInFlow = ['PENDING', 'PROCESSING', 'PREPARED', 'CONFIRMED'];

  static const Map<String, String> _statusLabels = {
    'PENDING': 'Pending',
    'PROCESSING': 'Processing',
    'PREPARED': 'Prepared',
    'IN TRANSIT': 'In Transit',
    'CONFIRMED': 'Confirmed',
    'CANCELLED': 'Cancelled',
  };

  // Pill colours — the same palette the website uses.
  static const Map<String, Color> _statusColors = {
    'PENDING': Color(0xFFF59E0B),
    'PROCESSING': Color(0xFF8B89F5),
    'PREPARED': Color(0xFF00C4C7),
    'IN TRANSIT': Color(0xFF4DA3FF),
    'CONFIRMED': Color(0xFF2ECC71),
    'CANCELLED': Color(0xFF9A9A9A),
  };

  // What each button SAYS (a verb, so staff know what a tap does) and its icon.
  static const Map<String, String> _nextActionText = {
    'PROCESSING': 'Start Processing',
    'PREPARED': 'Mark Prepared',
    'IN TRANSIT': 'Send Out',
    'CONFIRMED': 'Confirm',
  };
  static const Map<String, IconData> _nextActionIcon = {
    'PROCESSING': Icons.settings_outlined,
    'PREPARED': Icons.inventory_2_outlined,
    'IN TRANSIT': Icons.local_shipping_outlined,
    'CONFIRMED': Icons.check_circle_outline,
  };

  // Orders whose button was just tapped. While an id is in here its buttons
  // are disabled, so a double-tap can't send the same step twice.
  final Set<String> _busyOrderIds = {};

  /// Turns whatever is stored (any casing, older names) into one of this
  /// channel's stages, or 'CANCELLED'. Same job as normalizeStatus() on the web.
  /// The app has always stored 'COMPLETED' for a finished walk-in sale and the
  /// web stores 'confirmed'; both land on 'CONFIRMED' here.
  String _normalizeStatus(dynamic raw, bool online) {
    final s = (raw ?? 'pending').toString().toUpperCase().trim().replaceAll('_', ' ');
    if (s == 'CANCELLED') return 'CANCELLED';

    final flow = online ? _onlineFlow : _walkInFlow;
    if (flow.contains(s)) return s;

    if (s == 'COMPLETED' || s == 'DELIVERED') return 'CONFIRMED';
    if (online && (s == 'SHIPPED' || s == 'OUT FOR DELIVERY' || s == 'ON DELIVERY')) return 'IN TRANSIT';
    return 'PENDING'; // includes 'PAID' and any unknown legacy value
  }

  /// The one stage after [status], or null when there is no button to show.
  String? _nextStatusFor(String status, bool online) {
    if (status == 'CANCELLED') return null;
    final flow = online ? _onlineFlow : _walkInFlow;
    final index = flow.indexOf(status);
    if (index == -1 || index == flow.length - 1) return null;

    final next = flow[index + 1];
    // An online order becomes Confirmed only when the driver uploads the
    // proof of delivery (Delivery Dashboard), never from this list.
    if (online && next == 'CONFIRMED') return null;
    return next;
  }

  void _showSnack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, duration: const Duration(seconds: 3)),
    );
  }

  /// The single write path for EVERY status change on this page (the same
  /// idea as runGuardedTransition() on the web).
  ///
  /// It re-reads the order INSIDE a Firestore transaction and only writes if
  /// the order is still at [expectedFrom]. If another phone or the website moved
  /// it first, this refuses instead of jumping ahead or double-applying a step.
  /// Returns true when the change was saved.
  Future<bool> _runGuardedTransition({
    required String orderId,
    required String expectedFrom,
    required bool online,
    required Map<String, dynamic> updateData,
    required String auditLabel,
  }) async {
    final ref = FirebaseFirestore.instance.collection('orders').doc(orderId);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data();
        if (!snap.exists || data == null) {
          throw _StaleOrderException('This order no longer exists.');
        }
        if (data['locked'] == true) {
          throw _StaleOrderException('This order is already final and can no longer be changed.');
        }
        final current = _normalizeStatus(data['status'], online);
        if (current != expectedFrom) {
          throw _StaleOrderException(
              'This order is already "${_statusLabels[current]}". The list has refreshed — please check it again.');
        }
        tx.update(ref, updateData);
      });
    } on _StaleOrderException catch (e) {
      _showSnack(e.message, color: Colors.orange);
      return false;
    } catch (e) {
      _showSnack('Failed to update status: $e');
      return false;
    }

    // Accountability record — the same 'order_status_change' entry the website
    // writes, so both show up together in the Admin Activity Log. It must
    // never undo or block a status change that already succeeded.
    try {
      await AdminAuditService.logAction(
        action: 'order_status_change',
        targetUid: orderId,
        targetEmail: null,
        details: 'Order status changed to "$auditLabel".',
      );
    } catch (e) {
      debugPrint('Audit log write failed (status still updated): $e');
    }
    return true;
  }

  /// Taps on a row's "next step" button. Moves the order exactly ONE stage forward.
  Future<void> _advanceOrder(String orderId, bool online, String from) async {
    final next = _nextStatusFor(from, online);
    if (next == null || _busyOrderIds.contains(orderId)) return;

    // A finished walk-in sale locks the order for good, so it asks first.
    if (!online && next == 'CONFIRMED') {
      await _handleConfirmWalkIn(orderId, from);
      return;
    }

    setState(() => _busyOrderIds.add(orderId));
    try {
      final saved = await _runGuardedTransition(
        orderId: orderId,
        expectedFrom: from,
        online: online,
        updateData: {
          'status': next,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        auditLabel: _statusLabels[next] ?? next,
      );
      if (saved) {
        // No manual list update needed: the orders stream fires after the
        // write and redraws this row with the new pill and the next button.
        _showSnack('Order moved to "${_statusLabels[next]}"', color: Colors.green);
      }
    } finally {
      if (mounted) setState(() => _busyOrderIds.remove(orderId));
    }
  }

  /// Walk-in CONFIRM (the last step). Asks once ("this is final"), re-checks
  /// that nobody else finalised the order meanwhile, then saves + locks it.
  Future<void> _handleConfirmWalkIn(String orderId, String from) async {
    if (await _isAlreadyFinal(orderId)) {
      _showAlreadyFinalMessage();
      return;
    }
    final confirmed = await _showSimpleConfirm(
      title: 'Confirm this order?',
      message: 'Once confirmed, this order is final and cannot be changed again.',
      keepLabel: 'NOT YET',
      okLabel: 'CONFIRM ORDER',
      okColor: Colors.green,
    );
    if (!confirmed) return;

    setState(() => _busyOrderIds.add(orderId));
    try {
      final saved = await _runGuardedTransition(
        orderId: orderId,
        expectedFrom: from,
        online: false,
        updateData: {
          // The app has always written 'COMPLETED' for a finished walk-in sale
          // (Sales Report counts it); the website reads it as "Confirmed".
          'status': 'COMPLETED',
          'locked': true,
          // A sale completed at the counter is paid (same rule as the website).
          'paymentStatus': 'Paid',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        auditLabel: 'COMPLETED',
      );
      if (saved) _showSnack('Order confirmed', color: Colors.green);
    } finally {
      if (mounted) setState(() => _busyOrderIds.remove(orderId));
    }
  }

  /// Counts today's WALK-IN cancellations for a specific branch, computed
  /// entirely client-side from the order list the page already has
  /// loaded — deliberately avoids a separate Firestore query that would
  /// need a composite index (branchId + type + status + a date range on
  /// cancelledAt all at once).
  int _countTodaysWalkInCancellations(List<Map<String, dynamic>> walkInOrders, String? branchId) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    return walkInOrders.where((o) {
      final status = (o['status'] ?? '').toString().toUpperCase();
      if (status != 'CANCELLED') return false;

      if (branchId != null && (o['branchId']?.toString() ?? '') != branchId) return false;

      final rawCancelledAt = o['cancelledAt'];
      DateTime? cancelledAt;
      if (rawCancelledAt is Timestamp) {
        cancelledAt = rawCancelledAt.toDate();
      } else if (rawCancelledAt is String) {
        cancelledAt = DateTime.tryParse(rawCancelledAt);
      }
      if (cancelledAt == null) return false;

      return !cancelledAt.isBefore(startOfToday);
    }).length;
  }

  /// Entry point for the walk-in "CANCEL" button. Below the daily limit,
  /// cancels immediately after a plain confirmation — same as before. At
  /// or above the limit, requires a valid single-use override code
  /// first, verified server-side (see verify_override_code.php) so the
  /// code itself is never exposed to this app directly.
  Future<void> _handleCancelWalkIn(
      String orderId,
      Map<String, dynamic> order,
      int todaysCancelCount,
      ) async {
    final branchId = (order['branchId'] ?? _selectedBranchId ?? '').toString();

    // The stage the order is at RIGHT NOW on this screen. The cancel write
    // re-checks it inside a transaction, so a stale screen can't cancel an
    // order somebody else just moved or finalised.
    final fromStatus = _normalizeStatus(order['status'], false);
    if (fromStatus == 'CONFIRMED' || fromStatus == 'CANCELLED') {
      _showAlreadyFinalMessage();
      return;
    }

    // Check FIRST, so a wasted override code is never burned on an order
    // that somebody else already finalised.
    if (await _isAlreadyFinal(orderId)) {
      _showAlreadyFinalMessage();
      return;
    }

    // The daily limit is for employees. Admins / super-admins are the ones
    // who create the override codes, so they just get the normal confirm.
    final bool isAdminRole = widget.role == 'admin' || widget.role == 'super-admin';

    if (isAdminRole || todaysCancelCount < _dailyCancelLimit) {
      final confirmed = await _showSimpleConfirm(
        title: 'Cancel this order?',
        message: isAdminRole
            ? 'Once cancelled, this order is final. This cannot be undone.'
            : 'Once cancelled, this order is final. This cannot be undone.\n\n'
            'Cancellations used today at this branch: $todaysCancelCount of $_dailyCancelLimit.',
        keepLabel: 'KEEP ORDER',
        okLabel: 'CANCEL ORDER',
        okColor: Colors.red,
      );
      if (confirmed) await _finalizeCancellation(orderId, fromStatus);
      return;
    }

    // At/above the daily limit — require an override code.
    final code = await _showOverrideCodeDialog(todaysCancelCount);
    if (code == null || code.trim().isEmpty) return;

    if (branchId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No branch context available for this order.')),
        );
      }
      return;
    }

    final result = await _overrideCodeService.verifyAndBurn(
      branchId: branchId,
      code: code.trim(),
      orderId: orderId,
    );

    if (!result.success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message ?? 'Could not verify code. Please try again.')),
        );
      }
      return;
    }

    if (!result.valid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'Invalid or already-used override code.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final cancelled = await _finalizeCancellation(orderId, fromStatus);
    if (cancelled && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Override accepted. Order cancelled.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Cancels a walk-in order through the same guarded transaction as every
  /// other status change. Returns true when the cancellation was saved.
  Future<bool> _finalizeCancellation(String orderId, String fromStatus) async {
    if (_busyOrderIds.contains(orderId)) return false;
    setState(() => _busyOrderIds.add(orderId));
    try {
      return await _runGuardedTransition(
        orderId: orderId,
        expectedFrom: fromStatus,
        online: false,
        updateData: {
          'status': 'CANCELLED',
          'updatedAt': FieldValue.serverTimestamp(),
          // cancelledAt specifically (separate from updatedAt, which any
          // future edit would overwrite) is what the daily-limit count
          // filters on.
          'cancelledAt': FieldValue.serverTimestamp(),
          // Same fields the web page writes, so both sides agree the order is
          // finished and nobody can reopen it.
          'locked': true,
          'paymentStatus': 'Voided',
          'cancelledBy': FirebaseAuth.instance.currentUser?.email ?? 'Staff',
        },
        // Every cancellation (under or over the daily limit) still gets the
        // general order_status_change record, in addition to the override
        // path's own walkin_cancel_override entry.
        auditLabel: 'CANCELLED',
      );
    } finally {
      if (mounted) setState(() => _busyOrderIds.remove(orderId));
    }
  }

  Future<bool> _showSimpleConfirm({
    required String title,
    required String message,
    String keepLabel = 'KEEP ORDER',
    String okLabel = 'CANCEL ORDER',
    Color okColor = Colors.red,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(keepLabel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: okColor, foregroundColor: Colors.white),
            child: Text(okLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<String?> _showOverrideCodeDialog(int todaysCancelCount) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manager Override Required'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This branch has reached $todaysCancelCount walk-in cancellations today. '
                  'A single-use override code from an admin is required to continue.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Override Code',
                hintText: 'e.g. A1B2C3D4',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('VERIFY & CANCEL'),
          ),
        ],
      ),
    );
  }

  /// Admin-only: generate a fresh batch of 8 single-use codes for a
  /// branch, and see how many are currently unused. Direct Firestore
  /// access is fine here — firestore.rules already restricts
  /// override_codes to isAdmin(), and this IS an admin.
  void _showManageOverrideCodesDialog(String branchId, String branchLabel) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Override Codes — $branchLabel'),
            content: SizedBox(
              width: 360,
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('override_codes')
                    .where('branchId', isEqualTo: branchId)
                    .where('used', isEqualTo: false)
                    .snapshots(),
                builder: (context, snapshot) {
                  final unusedDocs = snapshot.data?.docs ?? [];
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${unusedDocs.length} unused code(s) remaining.',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      if (unusedDocs.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: unusedDocs.map((d) {
                            final data = d.data() as Map<String, dynamic>;
                            return Chip(label: Text(data['code']?.toString() ?? '??????'));
                          }).toList(),
                        ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('GENERATE NEW BATCH OF 8'),
                        onPressed: () => _generateNewCodeBatch(branchId),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Generating a new batch does NOT invalidate existing unused codes — it adds 8 more.',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _generateNewCodeBatch(String branchId) async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I — avoids visual mixups when read aloud
    final rng = Random.secure();

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (int i = 0; i < 8; i++) {
        final code = List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
        final ref = FirebaseFirestore.instance.collection('override_codes').doc();
        batch.set(ref, {
          'branchId': branchId,
          'code': code,
          'used': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('8 new override codes generated.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate codes: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final bool isSuperAdmin = widget.role == 'super-admin';
    final effectiveRole = widget.role;
    final isAdmin = effectiveRole == 'admin' || effectiveRole == 'super-admin';

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2A2A2A) : Colors.grey.withValues(alpha: 0.2);
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    final isDesktop = MediaQuery.of(context).size.width >= 850;

    return Scaffold(
      backgroundColor: bgColor,
      drawer: isDesktop ? null : Drawer(
        child: AppSidebar(role: effectiveRole, currentPage: 'orders'),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) AppSidebar(role: effectiveRole, currentPage: 'orders'),

          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: InventoryData.ordersStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error loading orders: ${snapshot.error}', style: TextStyle(color: textColor)),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFF59E0B)),
                  );
                }

                final allOrders = snapshot.data ?? [];

                final onlineOrders = allOrders.where(_isOnlineOrder).toList();
                final walkInOrders = allOrders.where((o) => !_isOnlineOrder(o)).toList();

                final currentList = _selectedTab == 0 ? onlineOrders : walkInOrders;

                final filteredList = currentList.where((o) {
                  if (_searchFilter.trim().isEmpty) return true;
                  final q = _searchFilter.toLowerCase();
                  final customer = (o['recipientName'] ?? o['customerName'] ?? o['customer_name'] ?? '').toString().toLowerCase();
                  final payload = (o['items'] ?? o['flowers'] ?? []).toString().toLowerCase();
                  final id = (o['id'] ?? o['orderId'] ?? '').toString().toLowerCase();
                  return customer.contains(q) || payload.contains(q) || id.contains(q);
                }).toList();

                int commerceVolume = currentList.length;
                int pendingResolution = currentList.where((o) {
                  final st = (o['status'] ?? 'pending').toString().toLowerCase();
                  // "Prepared" is still open work: the order has not left the shop yet.
                  return st.contains('pending') || st.contains('processing') || st.contains('prepared');
                }).length;

                double liquidityPipeline = 0.0;
                for (var o in currentList) {
                  liquidityPipeline += (o['totalAmount'] ?? o['totalPrice'] ?? o['total_amount'] ?? o['total_price'] ?? 0.0).toDouble();
                }

                // Today's walk-in cancellation count for the CURRENTLY
                // relevant branch — used both to decide whether the
                // override dialog is needed, and to show a small warning
                // banner once the branch is approaching the limit.
                final relevantBranchId = _selectedBranchId;
                final todaysCancelCount = _countTodaysWalkInCancellations(walkInOrders, relevantBranchId);

                return CustomScrollView(
                  slivers: [
                    if (!isDesktop)
                      SliverAppBar(
                        backgroundColor: cardColor,
                        iconTheme: IconThemeData(color: textColor),
                        elevation: 0,
                        pinned: true,
                        title: Text(
                          'Orders',
                          style: GoogleFonts.cormorantGaramond(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                          ),
                        ),
                        actions: [
                          if (isAdmin && relevantBranchId != null)
                            IconButton(
                              icon: const Icon(Icons.vpn_key_outlined),
                              tooltip: 'Manage Override Codes',
                              onPressed: () => _showManageOverrideCodesDialog(
                                  relevantBranchId, _branchName ?? 'This Branch'),
                            ),
                          IconButton(
                            icon: const Icon(Icons.receipt_long_rounded),
                            tooltip: 'Invoice Portal',
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => InvoicePortalPage(role: widget.role),
                                ),
                              );
                            },
                          ),
                        ],
                      ),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTopBar(cardColor, textColor, subTextColor, borderColor, isDark, isSuperAdmin, user, effectiveRole, isAdmin),
                            const SizedBox(height: 32),

                            if (isDesktop)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Orders',
                                        style: GoogleFonts.cormorantGaramond(
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                          color: textColor,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Track and manage customer orders.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: subTextColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      if (isAdmin && relevantBranchId != null)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 12),
                                          child: OutlinedButton.icon(
                                            icon: const Icon(Icons.vpn_key_outlined, size: 16),
                                            label: const Text('Override Codes'),
                                            onPressed: () => _showManageOverrideCodesDialog(
                                                relevantBranchId, _branchName ?? 'This Branch'),
                                          ),
                                        ),
                                      SizedBox(
                                        width: 260,
                                        height: 42,
                                        child: TextField(
                                          controller: _filterController,
                                          onChanged: (val) => setState(() => _searchFilter = val),
                                          style: TextStyle(fontSize: 13, color: textColor),
                                          decoration: InputDecoration(
                                            hintText: 'Filter Manifests...',
                                            hintStyle: TextStyle(fontSize: 12, color: subTextColor),
                                            prefixIcon: Icon(Icons.search, size: 18, color: subTextColor),
                                            contentPadding: EdgeInsets.zero,
                                            filled: true,
                                            fillColor: isDark ? const Color(0xFF222222) : const Color(0xFFF1F5F9),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: BorderSide(color: borderColor),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: BorderSide(color: borderColor),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: const BorderSide(color: Color(0xFFF59E0B)),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),

                            const SizedBox(height: 24),

                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: [
                                  _buildTabBtn(
                                    index: 0,
                                    label: 'Online Orders',
                                    count: onlineOrders.length,
                                    icon: Icons.language,
                                    isDark: isDark,
                                    textColor: textColor,
                                    borderColor: borderColor,
                                    cardColor: cardColor,
                                  ),
                                  const SizedBox(width: 12),
                                  _buildTabBtn(
                                    index: 1,
                                    label: 'Walk-in Orders',
                                    count: walkInOrders.length,
                                    icon: Icons.storefront,
                                    isDark: isDark,
                                    textColor: textColor,
                                    borderColor: borderColor,
                                    cardColor: cardColor,
                                  ),
                                ],
                              ),
                            ),

                            if (_selectedTab == 1 && todaysCancelCount >= _dailyCancelLimit) ...[
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(isDark ? 0.15 : 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.lock_clock, color: Colors.redAccent, size: 18),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'This branch has hit $todaysCancelCount walk-in cancellations today. Further cancellations need a manager override code.',
                                        style: const TextStyle(
                                            fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 20),

                            Row(
                              children: [
                                _buildMetricBox(
                                  'COMMERCE VOLUME',
                                  '$commerceVolume',
                                  Icons.shopping_bag_outlined,
                                  isDark,
                                  cardColor,
                                  borderColor,
                                  textColor,
                                  subTextColor,
                                ),
                                const SizedBox(width: 16),
                                _buildMetricBox(
                                  'PENDING RESOLUTION',
                                  '$pendingResolution',
                                  Icons.history,
                                  isDark,
                                  cardColor,
                                  borderColor,
                                  textColor,
                                  subTextColor,
                                ),
                                const SizedBox(width: 16),
                                _buildMetricBox(
                                  'LIQUIDITY PIPELINE',
                                  '₱${liquidityPipeline.toStringAsFixed(2)}',
                                  Icons.show_chart,
                                  isDark,
                                  cardColor,
                                  borderColor,
                                  textColor,
                                  subTextColor,
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            Container(
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: borderColor, width: 1.5),
                                boxShadow: [
                                  if (!isDark)
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.02),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      _selectedTab == 0 ? 'Online Orders Log' : 'Walk-in Orders Log',
                                      style: GoogleFonts.cormorantGaramond(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: textColor,
                                      ),
                                    ),
                                  ),
                                  Divider(height: 1, color: borderColor),

                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      return SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        physics: const BouncingScrollPhysics(),
                                        child: SizedBox(
                                          width: max(constraints.maxWidth, 900),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                                color: isDark ? const Color(0xFF222222) : const Color(0xFFF8FAFC),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      flex: 3,
                                                      child: Text(
                                                        'CLIENTELE',
                                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: subTextColor, letterSpacing: 1.0),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 3,
                                                      child: Text(
                                                        'PAYLOAD SUMMARY',
                                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: subTextColor, letterSpacing: 1.0),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 2,
                                                      child: Text(
                                                        'VALUATION',
                                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: subTextColor, letterSpacing: 1.0),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 2,
                                                      child: Text(
                                                        'TIMELINE',
                                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: subTextColor, letterSpacing: 1.0),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 4,
                                                      child: Text(
                                                        'FULFILLMENT STEP',
                                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: subTextColor, letterSpacing: 1.0),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Divider(height: 1, color: borderColor),

                                              if (filteredList.isEmpty)
                                                Container(
                                                  height: 160,
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    'No manifests found in this section.',
                                                    style: TextStyle(color: subTextColor, fontSize: 13, fontStyle: FontStyle.italic),
                                                  ),
                                                )
                                              else
                                                ListView.separated(
                                                  shrinkWrap: true,
                                                  physics: const NeverScrollableScrollPhysics(),
                                                  itemCount: filteredList.length,
                                                  separatorBuilder: (context, index) => Divider(
                                                    height: 1,
                                                    color: borderColor,
                                                  ),
                                                  itemBuilder: (context, index) {
                                                    final order = filteredList[index];
                                                    final orderId = (order['id'] ?? order['orderId'] ?? '').toString();
                                                    final customerName = (order['recipientName'] ?? order['customerName'] ?? order['customer_name'] ?? 'Walk-in Customer').toString();

                                                    final rawItems = order['items'] ?? order['flowers'] ?? [];
                                                    List<String> itemSummaries = [];
                                                    if (rawItems is List) {
                                                      for (var item in rawItems) {
                                                        if (item is Map) {
                                                          final name = item['name'] ?? 'Item';
                                                          final qty = item['qty'] ?? item['quantity'] ?? 1;
                                                          itemSummaries.add('$name ($qty)');
                                                        }
                                                      }
                                                    }
                                                    final payloadSummary = itemSummaries.isNotEmpty
                                                        ? itemSummaries.join(', ')
                                                        : (order['occasion'] ?? 'Custom Order Bouquet');

                                                    final totalValuation = (order['totalAmount'] ?? order['totalPrice'] ?? order['total_amount'] ?? order['total_price'] ?? 0.0).toDouble();

                                                    final rawDate = order['createdAt'] ?? order['timestamp'];
                                                    DateTime date = DateTime.now();
                                                    if (rawDate is Timestamp) {
                                                      date = rawDate.toDate();
                                                    } else if (rawDate is String) {
                                                      date = DateTime.tryParse(rawDate) ?? DateTime.now();
                                                    }
                                                    final timelineStr = DateFormat('M/d/yyyy').format(date);


                                                    // POS proof-of-order photo (null when the order has none).
                                                    final proofUrl = proofOfOrderUrl(order);

                                                    return Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                                                      child: Row(
                                                        children: [
                                                          Expanded(
                                                            flex: 3,
                                                            child: Row(
                                                              children: [
                                                                CircleAvatar(
                                                                  radius: 16,
                                                                  backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                                                  child: Text(
                                                                    customerName.isNotEmpty ? customerName[0].toUpperCase() : 'C',
                                                                    style: const TextStyle(
                                                                      fontSize: 12,
                                                                      fontWeight: FontWeight.bold,
                                                                      color: Color(0xFFF59E0B),
                                                                    ),
                                                                  ),
                                                                ),
                                                                const SizedBox(width: 12),
                                                                Expanded(
                                                                  child: Text(
                                                                    customerName,
                                                                    style: TextStyle(
                                                                      fontWeight: FontWeight.bold,
                                                                      fontSize: 13,
                                                                      color: textColor,
                                                                    ),
                                                                    overflow: TextOverflow.ellipsis,
                                                                  ),
                                                                ),
                                                                if (proofUrl != null)
                                                                  IconButton(
                                                                    tooltip: 'View proof of order',
                                                                    visualDensity: VisualDensity.compact,
                                                                    icon: const Icon(Icons.photo_camera_outlined,
                                                                        size: 18, color: Color(0xFFF59E0B)),
                                                                    onPressed: () => showProofOfOrderViewer(
                                                                      context,
                                                                      url: proofUrl,
                                                                      caption: 'Proof of order • ${customerName}',
                                                                    ),
                                                                  ),
                                                              ],
                                                            ),
                                                          ),
                                                          Expanded(
                                                            flex: 3,
                                                            child: Padding(
                                                              padding: const EdgeInsets.only(right: 12.0),
                                                              child: Text(
                                                                payloadSummary,
                                                                style: TextStyle(
                                                                  fontSize: 12,
                                                                  color: subTextColor,
                                                                ),
                                                                overflow: TextOverflow.ellipsis,
                                                                maxLines: 2,
                                                              ),
                                                            ),
                                                          ),
                                                          Expanded(
                                                            flex: 2,
                                                            child: Text(
                                                              '₱${totalValuation.toStringAsFixed(2)}',
                                                              style: TextStyle(
                                                                fontWeight: FontWeight.bold,
                                                                fontSize: 13,
                                                                color: textColor,
                                                              ),
                                                            ),
                                                          ),
                                                          Expanded(
                                                            flex: 2,
                                                            child: Text(
                                                              timelineStr,
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                color: subTextColor,
                                                              ),
                                                            ),
                                                          ),
                                                    Expanded(
                                                      flex: 4,
                                                      child: _buildStatusCell(
                                                        orderId: orderId,
                                                        order: order,
                                                        online: _selectedTab == 0,
                                                        todaysCancelCount: todaysCancelCount,
                                                        isDark: isDark,
                                                        textColor: textColor,
                                                        subTextColor: subTextColor,
                                                      ),
                                                    ),
                                                        ],
                                                      ),
                                                    );
                                                  },
                                                ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40.0),
                        child: Center(
                          child: Text(
                            '© 2026 BloomyPro Inventory System',
                            style: TextStyle(color: subTextColor, fontSize: 10),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The "Fulfillment Step" cell of one row (the app's version of
  /// buildStatusCell() on the website): a coloured status pill, small progress
  /// dots, and ONE button for the next step. There is no dropdown any more, so a
  /// stage can't be skipped. Walk-in orders also get a Cancel button.
  Widget _buildStatusCell({
    required String orderId,
    required Map<String, dynamic> order,
    required bool online,
    required int todaysCancelCount,
    required bool isDark,
    required Color textColor,
    required Color subTextColor,
  }) {
    final status = _normalizeStatus(order['status'], online);
    final flow = online ? _onlineFlow : _walkInFlow;
    final reachedIndex = flow.indexOf(status); // -1 for cancelled
    final next = _nextStatusFor(status, online);
    final busy = _busyOrderIds.contains(orderId);

    final bool isCancelled = status == 'CANCELLED';
    final bool isConfirmed = status == 'CONFIRMED';
    // Locked by something other than "finished" (e.g. a void in progress): hands off.
    final bool isLockedOther = order['locked'] == true && !isCancelled && !isConfirmed;
    final bool awaitingDriver = online && status == 'IN TRANSIT';

    final pillColor = _statusColors[status] ?? Colors.grey;

    // ---- Buttons / note ----
    final List<Widget> actions = [];

    if (!isLockedOther && next != null) {
      actions.add(
        ElevatedButton.icon(
          onPressed: busy ? null : () => _advanceOrder(orderId, online, status),
          icon: busy
              ? const SizedBox(
              width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(_nextActionIcon[next] ?? Icons.arrow_forward, size: 14),
          label: Text(
            (_nextActionText[next] ?? 'Next').toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.3),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF59E0B),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            minimumSize: Size.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );
    }

    // Walk-in only: Cancel stays available until the sale is Confirmed.
    if (!online && !isConfirmed && !isCancelled && !isLockedOther) {
      actions.add(
        OutlinedButton.icon(
          onPressed: busy ? null : () => _handleCancelWalkIn(orderId, order, todaysCancelCount),
          icon: const Icon(Icons.block, size: 13),
          label: const Text('CANCEL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.redAccent,
            side: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            minimumSize: Size.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );
    }

    String? note;
    if (isLockedOther) {
      note = 'Locked — no further steps.';
    } else if (isCancelled) {
      note = 'Order voided — no further steps.';
    } else if (isConfirmed) {
      note = 'Completed — no further steps.';
    } else if (awaitingDriver) {
      note = "Waiting for the driver's proof of delivery.";
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: pillColor.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  (_statusLabels[status] ?? status).toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                    color: pillColor,
                    decoration: isCancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ),
            if (!isCancelled) ...[
              const SizedBox(width: 8),
              // Progress dots: one per stage in this channel's flow; filled = already reached.
              for (int i = 0; i < flow.length; i++)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i <= reachedIndex
                        ? const Color(0xFFF59E0B)
                        : (isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E5E5)),
                  ),
                ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 6, children: actions),
        if (note != null)
          Padding(
            padding: EdgeInsets.only(top: actions.isNotEmpty ? 6 : 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLockedOther || isConfirmed) ...[
                  const Icon(Icons.lock, size: 11, color: Colors.green),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(note, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: subTextColor)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTopBar(Color cardColor, Color textColor, Color subTextColor, Color borderColor, bool isDark, bool isSuperAdmin, User? user, String role, bool isAdmin) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          if (!isDark)
            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: isSuperAdmin
                ? StreamBuilder<List<Map<String, dynamic>>>(
              stream: InventoryData.getBranchesStream(),
              builder: (context, snapshot) {
                final branches = snapshot.data ?? [];

                final bool selectedExists =
                    _selectedBranchId != null &&
                        branches.any((b) => b['id'] == _selectedBranchId);
                final String? safeValue = selectedExists ? _selectedBranchId : null;

                return DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: safeValue,
                    isExpanded: true,
                    hint: Text(
                      _branchName ?? 'All Branches',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                    icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFFF59E0B)),
                    dropdownColor: cardColor,
                    onChanged: (branchId) {
                      setState(() {
                        _selectedBranchId = branchId;
                        InventoryData.selectedBranchId = branchId;
                        if (branchId == null) {
                          _branchName = 'All Branches (Super Admin)';
                        } else {
                          final branch = branches.firstWhere((b) => b['id'] == branchId);
                          _branchName = branch['name'];
                        }
                      });
                    },
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Branches')),
                      ...branches.map((b) => DropdownMenuItem(
                        value: b['id'] as String,
                        child: Text(b['name'] as String),
                      )),
                    ],
                  ),
                );
              },
            )
                : Text(
              _branchName ?? '',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(width: 12),
          Icon(Icons.notifications_none_rounded, color: subTextColor, size: 20),
          const SizedBox(width: 12),
          Container(height: 20, width: 1, color: borderColor),
          const SizedBox(width: 12),

          StreamBuilder<DocumentSnapshot>(
            stream: user != null
                ? FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots()
                : null,
            builder: (context, snapshot) {
              final userData = snapshot.data?.data() as Map<String, dynamic>?;
              final firstName = (userData?['firstName'] ?? '').toString();
              final displayName = firstName.isNotEmpty
                  ? firstName
                  : (user?.email?.split('@')[0] ?? (isAdmin ? 'Admin' : 'Staff'));
              final photoUrl = (userData?['photoUrl'] ?? '').toString();
              final avatarLetter = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'A';

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          displayName,
                          style: GoogleFonts.inter(
                            color: textColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          role.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.0,
                            fontWeight: FontWeight.w600,
                            color: subTextColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  CircleAvatar(
                    backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    radius: 16,
                    backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                    child: photoUrl.isEmpty
                        ? Text(avatarLetter, style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 12))
                        : null,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMetricBox(
      String label,
      String value,
      IconData icon,
      bool isDark,
      Color cardColor,
      Color borderColor,
      Color textColor,
      Color subTextColor,
      ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: subTextColor,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: const Color(0xFFF59E0B), size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBtn({
    required int index,
    required String label,
    required int count,
    required IconData icon,
    required bool isDark,
    required Color textColor,
    required Color borderColor,
    required Color cardColor,
  }) {
    final bool isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF59E0B).withValues(alpha: 0.1) : cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFF59E0B) : borderColor,
            width: isSelected ? 1.5 : 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? const Color(0xFFF59E0B) : Colors.grey),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? const Color(0xFFF59E0B) : textColor,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFF59E0B) : Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thrown inside the status transaction when the order is no longer where this
/// screen thinks it is (moved, locked, or deleted by someone else).
class _StaleOrderException implements Exception {
  final String message;
  _StaleOrderException(this.message);
}
