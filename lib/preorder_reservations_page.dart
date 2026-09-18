import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'inventory_data.dart';
import 'app_sidebar.dart';

class PreordersPage extends StatefulWidget {
  final String role;
  const PreordersPage({super.key, this.role = 'employee'});

  @override
  State<PreordersPage> createState() => _PreordersPageState();
}

class _PreordersPageState extends State<PreordersPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<Map<String, dynamic>>> _reservationsStream() {
    final branchId = InventoryData.selectedBranchId;

    final Query<Map<String, dynamic>> query = branchId != null
        ? _db.collection('branches').doc(branchId).collection('reservations')
        : _db.collectionGroup('reservations');

    return query.orderBy('created_at', descending: true).snapshots().map(
          (snap) => snap.docs.map((d) {
        final branchIdFromPath = d.reference.parent.parent?.id ?? '';
        return {...d.data(), 'id': d.id, '_branchId': branchIdFromPath};
      }).toList(),
    );
  }

  DocumentReference<Map<String, dynamic>> _reservationRef(String branchId, String id) {
    return _db.collection('branches').doc(branchId).collection('reservations').doc(id);
  }

  String _formatDateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _callCustomer(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    final launched = await launchUrl(uri);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open dialer for $phone')),
      );
    }
  }

  // --- Reservation Settings (GLOBAL, not per-branch) ---

  // FIXED: defaults to 1 instead of null when the config doc doesn't
  // exist yet or has no value saved -- "unlimited" is no longer a valid
  // state anywhere in this feature. A brand-new install, before the
  // owner ever opens this settings sheet, now behaves as "max 1
  // reservation per day" rather than accidentally allowing unlimited
  // bookings by default.
  Stream<int> _maxDailyCapacityStream() {
    return _db.collection('settings').doc('reservation_config').snapshots().map(
          (doc) => (doc.data()?['maxDailyCapacity'] as int?) ?? 1,
    );
  }

  // FIXED: added error handling + user feedback. Previously a failed
  // write here (permission issue, network drop, anything) produced
  // zero visible feedback -- the sheet just looked like nothing
  // happened, which is exactly the symptom reported. Also removed the
  // "leave blank for unlimited" behavior -- blank input now saves as 1,
  // the enforced minimum, not null/unlimited.
  Future<void> _saveMaxDailyCapacity(String rawValue) async {
    final parsed = int.tryParse(rawValue.trim());
    final value = (parsed == null || parsed < 1) ? 1 : parsed;
    try {
      await _db.collection('settings').doc('reservation_config').set({
        'maxDailyCapacity': value,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved: max $value reservation(s) per day'), backgroundColor: const Color(0xFF10B981)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Already global/branch-independent -- top-level 'blocked_dates'
  // collection, no branchId anywhere in this query. A blocked date
  // shows here and blocks bookings regardless of which branch (or "All
  // Branches") is currently selected elsewhere in the app.
  Stream<List<Map<String, dynamic>>> _blockedDatesStream() {
    final todayStr = _formatDateStr(DateTime.now());
    return _db.collection('blocked_dates').snapshots().map((snap) {
      final docs = snap.docs
          .map((d) => {...d.data(), 'date': d.id})
          .where((d) => (d['date'] as String).compareTo(todayStr) >= 0)
          .toList();
      docs.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
      return docs;
    });
  }

  // FIXED: wrapped in try/catch with explicit success/failure feedback --
  // this was the actual bug. A silent failure here (e.g. a rules-publish
  // delay, a stale connection) previously left no trace at all, making
  // it look like "blocking a date does nothing."
  Future<void> _blockDate(DateTime date) async {
    final dateStr = _formatDateStr(date);
    try {
      await _db.collection('blocked_dates').doc(dateStr).set({
        'isBlocked': true,
        'blocked_at': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${DateFormat('MMM d, yyyy').format(date)} is now blocked'), backgroundColor: const Color(0xFF10B981)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not block this date: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _unblockDate(String dateStr) async {
    try {
      await _db.collection('blocked_dates').doc(dateStr).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Date unblocked'), backgroundColor: Color(0xFF10B981)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not unblock this date: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showReservationSettings(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
            final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
            final subTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
            final borderColor = isDark ? const Color(0xFF2A2A2A) : Colors.grey.withValues(alpha: 0.2);

            return Container(
              decoration: BoxDecoration(color: cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Reservation Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)),
                        Text('Applies to all branches — booking availability is set once, business-wide.',
                            style: TextStyle(fontSize: 11, color: subTextColor)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        // --- Section 1: max reservations per day (global, minimum 1) ---
                        Text('MAX RESERVATIONS PER DAY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: subTextColor, letterSpacing: 0.5)),
                        const SizedBox(height: 8),
                        StreamBuilder<int>(
                          stream: _maxDailyCapacityStream(),
                          builder: (context, snap) {
                            // Rebuilds the controller's starting text whenever
                            // the live value changes -- since this stream
                            // now always resolves to a real int (default 1),
                            // the field is never blank/ambiguous.
                            final current = snap.data ?? 1;
                            final controller = TextEditingController(text: current.toString());
                            return Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: controller,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Minimum 1',
                                      isDense: true,
                                      filled: true,
                                      fillColor: isDark ? const Color(0xFF262626) : const Color(0xFFFAFAFA),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () => _saveMaxDailyCapacity(controller.text),
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.white),
                                  child: const Text('SAVE'),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Caps how many reservations can be booked on any single day, counted across every branch combined. There is no unlimited option — the minimum is 1.',
                          style: TextStyle(fontSize: 10.5, color: subTextColor, fontStyle: FontStyle.italic),
                        ),

                        const SizedBox(height: 28),
                        Divider(color: borderColor),
                        const SizedBox(height: 16),

                        // --- Section 2: blocked dates (global, no capacity here) ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text('UNAVAILABLE DATES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: subTextColor, letterSpacing: 0.5)),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(const Duration(days: 365)),
                                );
                                if (picked != null) await _blockDate(picked);
                              },
                              icon: const Icon(Icons.block, size: 14),
                              label: const Text('Block a Date', style: TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(foregroundColor: Colors.red),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Dates marked here cannot be selected by customers at all, regardless of the daily cap above. Shown here for every branch — this list is not filtered by branch selection.',
                          style: TextStyle(fontSize: 10.5, color: subTextColor, fontStyle: FontStyle.italic),
                        ),
                        const SizedBox(height: 12),
                        StreamBuilder<List<Map<String, dynamic>>>(
                          stream: _blockedDatesStream(),
                          builder: (context, snap) {
                            if (snap.hasError) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Text('Could not load blocked dates: ${snap.error}',
                                    style: const TextStyle(fontSize: 12, color: Colors.red)),
                              );
                            }
                            if (snap.connectionState == ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B))),
                              );
                            }
                            final blocked = snap.data ?? [];
                            if (blocked.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Text('No dates are currently blocked.', style: TextStyle(fontSize: 12, color: subTextColor)),
                              );
                            }
                            return Column(
                              children: blocked.map((b) {
                                final dateStr = b['date'] as String;
                                final parsed = DateTime.tryParse(dateStr);
                                final label = parsed != null ? DateFormat('MMM d, yyyy (EEE)').format(parsed) : dateStr;
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.block, size: 16, color: Colors.red),
                                      const SizedBox(width: 10),
                                      Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor))),
                                      TextButton(
                                        onPressed: () => _unblockDate(dateStr),
                                        child: const Text('Unblock', style: TextStyle(fontSize: 11, color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _confirm(String title, String message, Color color) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: color),
            child: const Text('CONFIRM', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _reserveBooking(String branchId, String id) async {
    final ok = await _confirm(
      'Reserve This Booking?',
      'It will move into the fulfillment pipeline.',
      Colors.blue,
    );
    if (!ok) return;
    try {
      await _reservationRef(branchId, id).update({
        'status': 'Reserved',
        'approved_by': FirebaseAuth.instance.currentUser?.email ?? 'Admin',
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reservation blocked: $e')));
      }
    }
  }

  Future<void> _declineBooking(String branchId, String id) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline Booking'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Reason (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('DECLINE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (reason == null) return;
    try {
      await _reservationRef(branchId, id).update({
        'status': 'Declined',
        'decline_reason': reason,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Decline update blocked: $e')));
      }
    }
  }

  Future<void> _advanceStatus(String branchId, String id, String currentStatus) async {
    String next = 'Confirmed & Sourcing';
    if (currentStatus == 'Reserved') next = 'Confirmed & Sourcing';
    if (currentStatus == 'Confirmed & Sourcing') next = 'Ready for Pickup';
    if (currentStatus == 'Ready for Pickup') next = 'Fulfilled';

    final ok = await _confirm(
      'Advance Booking State?',
      'Move to next milestone: "$next"?',
      Colors.blue,
    );
    if (!ok) return;
    try {
      await _reservationRef(branchId, id).update({
        'status': next,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('State update blocked: $e')));
      }
    }
  }

  Future<void> _cancelBooking(String branchId, String id) async {
    final ok = await _confirm(
      'Delete This Reservation?',
      'This permanently removes the design pre-order record. This cannot be undone.',
      Colors.red,
    );
    if (!ok) return;
    try {
      await _reservationRef(branchId, id).delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  Map<String, dynamic> _statusMeta(String? status) {
    switch (status) {
      case 'Reserved':
        return {'color': Colors.blue[800], 'bg': Colors.blue.withValues(alpha: 0.12), 'action': 'Begin Sourcing'};
      case 'Confirmed & Sourcing':
        return {'color': Colors.teal[700], 'bg': Colors.teal.withValues(alpha: 0.12), 'action': 'Flag as Ready for Pickup'};
      case 'Ready for Pickup':
        return {'color': Colors.blueGrey[700], 'bg': Colors.blueGrey.withValues(alpha: 0.12), 'action': 'Mark as Fulfilled'};
      case 'Fulfilled':
        return {'color': Colors.green[700], 'bg': Colors.green.withValues(alpha: 0.12), 'action': null};
      case 'Declined':
        return {'color': Colors.red[700], 'bg': Colors.red.withValues(alpha: 0.12), 'action': null};
      default:
        return {'color': Colors.amber[800], 'bg': Colors.amber.withValues(alpha: 0.15), 'action': null};
    }
  }

  Widget _buildStyleImage(String url) {
    if (url.startsWith('data:')) {
      try {
        final bytes = base64Decode(url.split(',').last);
        return Image.memory(bytes, fit: BoxFit.cover, width: double.infinity, height: 170);
      } catch (_) {
        return _imagePlaceholder();
      }
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: 170,
      errorBuilder: (_, __, ___) => _imagePlaceholder(),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      height: 170,
      color: Colors.grey.withValues(alpha: 0.1),
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
    );
  }

  @override
  Widget build(BuildContext context) {
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
      drawer: isDesktop ? null : Drawer(child: AppSidebar(role: widget.role, currentPage: 'preorders')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) AppSidebar(role: widget.role, currentPage: 'preorders'),
          Expanded(
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isDesktop)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
                      child: Row(
                        children: [
                          Builder(builder: (ctx) => IconButton(
                            icon: Icon(Icons.menu, color: textColor),
                            onPressed: () => Scaffold.of(ctx).openDrawer(),
                          )),
                          Expanded(
                            child: Text(
                              'Pre-Orders',
                              style: GoogleFonts.cormorantGaramond(
                                  color: textColor, fontWeight: FontWeight.bold, fontSize: 22),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.settings_outlined, color: textColor),
                            tooltip: 'Reservation Settings',
                            onPressed: () => _showReservationSettings(context),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Event Organizer & Reservations',
                                      style: GoogleFonts.cormorantGaramond(
                                        fontSize: isDesktop ? 32 : 24,
                                        fontWeight: FontWeight.bold,
                                        color: textColor,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Live monitoring of event reservations submitted through the app\'s AI Visual Stylist — review, reserve, and track fulfillment.',
                                      style: TextStyle(fontSize: 12, color: subTextColor),
                                    ),
                                  ],
                                ),
                              ),
                              if (isDesktop)
                                OutlinedButton.icon(
                                  onPressed: () => _showReservationSettings(context),
                                  icon: const Icon(Icons.settings_outlined, size: 16),
                                  label: const Text('Reservation Settings'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFF59E0B),
                                    side: const BorderSide(color: Color(0xFFF59E0B)),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          StreamBuilder<List<Map<String, dynamic>>>(
                            stream: _reservationsStream(),
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return Text('Error loading reservations: ${snapshot.error}',
                                    style: TextStyle(color: textColor));
                              }
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 60),
                                  child: Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B))),
                                );
                              }

                              final reservations = snapshot.data ?? [];

                              if (reservations.isEmpty) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(vertical: 60),
                                  alignment: Alignment.center,
                                  child: Column(
                                    children: [
                                      Icon(Icons.calendar_month_outlined, size: 48, color: subTextColor.withValues(alpha: 0.4)),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No event reservations submitted via the Visual Stylist yet.',
                                        style: TextStyle(color: subTextColor, fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              return Wrap(
                                spacing: 20,
                                runSpacing: 20,
                                children: reservations
                                    .map((data) => SizedBox(
                                  width: isDesktop ? 340 : double.infinity,
                                  child: _buildReservationCard(
                                      data, isDark, cardColor, borderColor, textColor, subTextColor),
                                ))
                                    .toList(),
                              );
                            },
                          ),
                        ],
                      ),
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

  Widget _buildReservationCard(
      Map<String, dynamic> data,
      bool isDark,
      Color cardColor,
      Color borderColor,
      Color textColor,
      Color subTextColor,
      ) {
    final id = data['id'] as String;
    final branchId = data['_branchId'] as String;
    final status = data['status'] as String?;
    final meta = _statusMeta(status);
    final isPendingReview = status == null || status == 'Pending Review';
    final isVisualStylist = data['source'] == 'visual_stylist';
    final photoUrl = (data['style_photo_url'] ?? '').toString();
    final detectedTheme = (data['detected_theme'] ?? '').toString();
    final customerName = (data['customer_name'] ?? 'Customer').toString();
    final customerPhone = (data['customer_phone'] ?? '').toString();
    final arrangementDetails = (data['arrangement_details'] ?? 'No notes provided.').toString();
    final recommendedFlowers = (data['recommended_flowers'] is List)
        ? (data['recommended_flowers'] as List).map((e) => e.toString()).toList()
        : <String>[];

    final depositRequired = data['deposit_required'];
    final totalAmount = data['total_amount'];
    final paymentMethod = (data['payment_method'] ?? '').toString();

    final rawFulfillment = data['fulfillment_date'];
    String targetDateStr = 'N/A';
    if (rawFulfillment != null) {
      DateTime? parsed;
      if (rawFulfillment is Timestamp) parsed = rawFulfillment.toDate();
      if (rawFulfillment is String) parsed = DateTime.tryParse(rawFulfillment);
      if (parsed != null) targetDateStr = DateFormat('MMM d, yyyy').format(parsed);
    }

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              photoUrl.isNotEmpty
                  ? Stack(
                children: [
                  _buildStyleImage(photoUrl),
                  if (detectedTheme.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black54],
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.auto_awesome, size: 12, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              detectedTheme,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              )
                  : Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Icon(Icons.image_outlined, size: 14, color: subTextColor),
                    const SizedBox(width: 6),
                    Text('No visual style attached',
                        style: TextStyle(fontSize: 11, color: subTextColor, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), shape: BoxShape.circle),
                    child: const Icon(Icons.delete_outline, size: 16, color: Colors.white),
                  ),
                  onPressed: () => _cancelBooking(branchId, id),
                  tooltip: 'Delete record',
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: meta['bg'], borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        status ?? 'Pending Review',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: meta['color'], letterSpacing: 0.5),
                      ),
                    ),
                    if (isVisualStylist)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.smartphone, size: 10, color: Colors.purple[700]),
                            const SizedBox(width: 3),
                            Text('APP',
                                style: TextStyle(
                                    fontSize: 9, fontWeight: FontWeight.w800, color: Colors.purple[700], letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  customerName,
                  style: GoogleFonts.cormorantGaramond(fontSize: 20, fontWeight: FontWeight.w900, color: textColor),
                ),
                if (customerPhone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  InkWell(
                    onTap: () => _callCustomer(customerPhone),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.phone, size: 11, color: Colors.blue[600]),
                          const SizedBox(width: 4),
                          Text(customerPhone,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue[600],
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline)),
                          const SizedBox(width: 4),
                          Icon(Icons.call, size: 12, color: Colors.blue[600]),
                        ],
                      ),
                    ),
                  ),
                ],
                if (depositRequired != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.payments_outlined, size: 12, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Budget: ₱${(totalAmount ?? 0).toStringAsFixed(0)} · Deposit: ₱${(depositRequired as num).toStringAsFixed(0)}${paymentMethod.isNotEmpty ? ' via $paymentMethod' : ''}',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFF59E0B)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CUSTOM DESIGN MANIFEST',
                          style: TextStyle(
                              fontSize: 8, fontWeight: FontWeight.w800, color: subTextColor, letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Text(arrangementDetails, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor)),
                    ],
                  ),
                ),
                if (recommendedFlowers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: recommendedFlowers
                        .map((f) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                      child: Text(f,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.amber[800])),
                    ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text('FULFILLMENT TARGET',
                        style: TextStyle(
                            fontSize: 8, fontWeight: FontWeight.w800, color: subTextColor, letterSpacing: 0.5)),
                    const SizedBox(width: 8),
                    Text(targetDateStr, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
                  ],
                ),
                const SizedBox(height: 4),
                FutureBuilder<Map<String, dynamic>?>(
                  future: InventoryData.getBranchDetails(branchId),
                  builder: (context, snap) {
                    final name = snap.data?['name'] ?? branchId;
                    return Text('Branch: $name',
                        style: TextStyle(fontSize: 10, color: subTextColor, fontStyle: FontStyle.italic));
                  },
                ),
                const SizedBox(height: 16),

                if (isPendingReview)
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _reserveBooking(branchId, id),
                          icon: const Icon(Icons.event_available, size: 14),
                          label: const Text('Reserve', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF59E0B),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _declineBooking(branchId, id),
                          icon: const Icon(Icons.close, size: 14),
                          label: const Text('Decline', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red, width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  )
                else if (status == 'Declined')
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.red, style: BorderStyle.solid, width: 1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Text('DECLINED',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.red)),
                  )
                else if (status != 'Fulfilled')
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => _advanceStatus(branchId, id, status!),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF59E0B),
                          side: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(meta['action'] ?? 'Advance',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.green, width: 1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: const Text('FULFILLED',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.green)),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}