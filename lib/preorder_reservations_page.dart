import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

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

  // --- FIXED: reservations live at branches/{branchId}/reservations, not
  // a flat top-level 'reservations' collection. That's why the earlier
  // version hit permission-denied — it was querying a path with no
  // matching rule, which falls through to the global deny-all.
  //
  // When a specific branch is selected: query that branch's subcollection
  // directly. When viewing "All Branches" (branchId == null, super-admin
  // only): use a collectionGroup query, which searches every subcollection
  // named 'reservations' anywhere in the database in one request — the
  // correct tool for "give me this data across every branch at once."
  Stream<List<Map<String, dynamic>>> _reservationsStream() {
    final branchId = InventoryData.selectedBranchId;

    final Query<Map<String, dynamic>> query = branchId != null
        ? _db.collection('branches').doc(branchId).collection('reservations')
        : _db.collectionGroup('reservations');

    return query.orderBy('created_at', descending: true).snapshots().map(
          (snap) => snap.docs.map((d) {
        // doc.reference.parent is the 'reservations' subcollection;
        // .parent again is the specific branch DOCUMENT that owns it.
        // Capturing that branch ID here means every write action below
        // (approve/decline/advance/cancel) knows exactly which
        // branches/{id}/reservations/{docId} path to write back to,
        // even when this list came from a cross-branch collectionGroup
        // query where no single branchId was assumed up front.
        final branchIdFromPath = d.reference.parent.parent?.id ?? '';
        return {...d.data(), 'id': d.id, '_branchId': branchIdFromPath};
      }).toList(),
    );
  }

  DocumentReference<Map<String, dynamic>> _reservationRef(String branchId, String id) {
    return _db.collection('branches').doc(branchId).collection('reservations').doc(id);
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

  Future<void> _approveBooking(String branchId, String id) async {
    final ok = await _confirm(
      'Approve Event Booking?',
      'It will move into the fulfillment pipeline.',
      Colors.blue,
    );
    if (!ok) return;
    try {
      await _reservationRef(branchId, id).update({
        'status': 'Approved',
        'approved_by': FirebaseAuth.instance.currentUser?.email ?? 'Admin',
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Approval blocked: $e')));
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
    if (currentStatus == 'Approved') next = 'Confirmed & Sourcing';
    if (currentStatus == 'Confirmed & Sourcing') next = 'Ready for Pickup';
    if (currentStatus == 'Ready for Pickup') next = 'Completed';

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
      case 'Approved':
        return {'color': Colors.blue[800], 'bg': Colors.blue.withValues(alpha: 0.12), 'action': 'Begin Sourcing'};
      case 'Confirmed & Sourcing':
        return {'color': Colors.teal[700], 'bg': Colors.teal.withValues(alpha: 0.12), 'action': 'Flag as Ready for Pickup'};
      case 'Ready for Pickup':
        return {'color': Colors.blueGrey[700], 'bg': Colors.blueGrey.withValues(alpha: 0.12), 'action': 'Handover / Complete Order'};
      case 'Completed':
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
                          Text(
                            'Pre-Orders',
                            style: GoogleFonts.cormorantGaramond(
                                color: textColor, fontWeight: FontWeight.bold, fontSize: 22),
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
                            'Live monitoring of event reservations submitted through the app\'s AI Visual Stylist — review, approve, and track fulfillment.',
                            style: TextStyle(fontSize: 12, color: subTextColor),
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
                  Row(
                    children: [
                      Icon(Icons.phone, size: 11, color: subTextColor),
                      const SizedBox(width: 4),
                      Text(customerPhone, style: TextStyle(fontSize: 11, color: subTextColor, fontWeight: FontWeight.w600)),
                    ],
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
                // NEW: since a super-admin viewing "All Branches" now sees
                // reservations pulled from many different branches at once
                // via the collectionGroup query, showing which branch each
                // card belongs to avoids ambiguity that didn't exist before.
                Text('Branch: $branchId',
                    style: TextStyle(fontSize: 10, color: subTextColor, fontStyle: FontStyle.italic)),
                const SizedBox(height: 16),

                if (isPendingReview)
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _approveBooking(branchId, id),
                          icon: const Icon(Icons.check, size: 14),
                          label: const Text('Approve', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
                else if (status != 'Completed')
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
                      child: const Text('ORDER CLOSED',
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