import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'inventory_data.dart';
import 'app_sidebar.dart';

/// Mobile equivalent of override_codes.php — reads and writes the exact
/// same `override_codes` / `override_code_batches` collections web does,
/// so a batch generated from either platform shows up live on the
/// other. No separate backend needed; firestore.rules already restrict
/// both collections to isAdmin() on both clients.
class OverrideCodesPage extends StatefulWidget {
  final String role;
  const OverrideCodesPage({super.key, required this.role});

  @override
  State<OverrideCodesPage> createState() => _OverrideCodesPageState();
}

class _OverrideCodesPageState extends State<OverrideCodesPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String? _selectedBranchId;
  String? _branchName;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _initializeBranch();
  }

  Future<void> _initializeBranch() async {
    final user = FirebaseAuth.instance.currentUser;
    final bool isSuperAdmin = widget.role == 'super-admin';

    if (isSuperAdmin) {
      final preselected = InventoryData.selectedBranchId;
      if (preselected != null) {
        final bDetails = await InventoryData.getBranchDetails(preselected);
        if (mounted) {
          setState(() {
            _selectedBranchId = preselected;
            _branchName = bDetails?['name'] ?? preselected;
          });
        }
      }
    } else {
      final userData = await InventoryData.getUserData(user?.uid ?? '');
      final bId = userData?['branchId'];
      if (bId != null) {
        final bDetails = await InventoryData.getBranchDetails(bId);
        if (mounted) {
          setState(() {
            _selectedBranchId = bId;
            _branchName = bDetails?['name'] ?? 'Assigned Branch';
          });
        }
      }
    }
  }

  // Same character set and cryptographically-secure RNG as web's
  // generator — excludes 0/O/1/I so a code read aloud is never
  // misheard, and Random.secure() (not the default Random()) is what
  // makes this genuinely unpredictable.
  String _generateSecureCode({int length = 8}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  Future<void> _generateNewBatch() async {
    if (_selectedBranchId == null) return;
    setState(() => _isGenerating = true);
    try {
      final newBatchId =
          '${DateTime.now().millisecondsSinceEpoch}-${_generateSecureCode(length: 6)}';
      final batch = _db.batch();

      for (int i = 0; i < 8; i++) {
        final ref = _db.collection('override_codes').doc();
        batch.set(ref, {
          'branchId': _selectedBranchId,
          'batchId': newBatchId,
          'code': _generateSecureCode(),
          'used': false,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': FirebaseAuth.instance.currentUser?.email ?? 'unknown',
        });
      }

      // Atomically points the branch at this new batch in the SAME
      // commit as the 8 codes — matches web's exact same guarantee.
      final pointerRef = _db.collection('override_code_batches').doc(_selectedBranchId);
      batch.set(pointerRef, {
        'currentBatchId': newBatchId,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.email ?? 'unknown',
      });

      await batch.commit();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to generate codes: $e')));
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width >= 850;
    final bool isAdmin = widget.role == 'admin' || widget.role == 'super-admin';
    final bool isSuperAdmin = widget.role == 'super-admin';

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Restricted')),
        drawer: isDesktop
            ? null
            : Drawer(child: AppSidebar(role: widget.role, currentPage: 'override_codes')),
        body: Row(
          children: [
            if (isDesktop) AppSidebar(role: widget.role, currentPage: 'override_codes'),
            const Expanded(
              child: Center(child: Text('This section is restricted to administrators.')),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFFFFDF9),
      appBar: AppBar(
        title: Text('Override Codes',
            style: GoogleFonts.cormorantGaramond(fontWeight: FontWeight.bold, fontSize: 24)),
        backgroundColor: isDark ? Colors.black : const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      drawer: isDesktop
          ? null
          : Drawer(child: AppSidebar(role: widget.role, currentPage: 'override_codes')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) AppSidebar(role: widget.role, currentPage: 'override_codes'),
          Expanded(
            child: _selectedBranchId == null
                ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: isSuperAdmin
                    ? StreamBuilder<List<Map<String, dynamic>>>(
                  stream: InventoryData.getBranchesStream(),
                  builder: (context, snapshot) {
                    final branches = snapshot.data ?? [];
                    if (branches.isEmpty) {
                      return const CircularProgressIndicator(
                          color: Color(0xFFF59E0B));
                    }
                    return DropdownButton<String>(
                      hint: const Text('Select a branch to manage its codes'),
                      items: branches
                          .map((b) => DropdownMenuItem(
                          value: b['id'] as String,
                          child: Text(b['name'] as String)))
                          .toList(),
                      onChanged: (val) async {
                        if (val == null) return;
                        InventoryData.selectedBranchId = val;
                        final bDetails = await InventoryData.getBranchDetails(val);
                        setState(() {
                          _selectedBranchId = val;
                          _branchName = bDetails?['name'] ?? val;
                        });
                      },
                    );
                  },
                )
                    : Text('No branch assigned to this account.',
                    style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600])),
              ),
            )
                : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Single-use codes required for an employee\'s 4th+ walk-in cancellation of the day at a branch.',
                    style: TextStyle(
                        fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.withOpacity(0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Current Batch',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: isDark ? Colors.white : Colors.black87)),
                                  Text('Branch: ${_branchName ?? _selectedBranchId}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                ],
                              ),
                            ),
                            if (isSuperAdmin)
                              TextButton(
                                onPressed: () => setState(() {
                                  _selectedBranchId = null;
                                  _branchName = null;
                                }),
                                child: const Text('Change Branch', style: TextStyle(fontSize: 11)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        StreamBuilder<DocumentSnapshot>(
                          stream: _db
                              .collection('override_code_batches')
                              .doc(_selectedBranchId)
                              .snapshots(),
                          builder: (context, pointerSnap) {
                            final pointerData =
                            pointerSnap.data?.data() as Map<String, dynamic>?;
                            final currentBatchId = pointerData?['currentBatchId'];

                            if (currentBatchId == null) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'No codes generated yet for this branch.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                        fontStyle: FontStyle.italic),
                                  ),
                                  const SizedBox(height: 16),
                                  _buildGenerateButton(canGenerate: true),
                                ],
                              );
                            }

                            // Two plain equality filters on
                            // different fields — Firestore supports
                            // this combination via its automatic
                            // single-field indexes without needing
                            // a manual composite index, unlike
                            // pairing an equality filter with
                            // orderBy (see admin_audit_log_page.dart).
                            return StreamBuilder<QuerySnapshot>(
                              stream: _db
                                  .collection('override_codes')
                                  .where('branchId', isEqualTo: _selectedBranchId)
                                  .where('batchId', isEqualTo: currentBatchId)
                                  .snapshots(),
                              builder: (context, codesSnap) {
                                final docs = codesSnap.data?.docs ?? [];
                                final usedCount = docs
                                    .where((d) => (d.data() as Map)['used'] == true)
                                    .length;
                                final remaining = docs.length - usedCount;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: docs.map((doc) {
                                        final data = doc.data() as Map<String, dynamic>;
                                        final isUsed = data['used'] == true;
                                        final code =
                                        (data['code'] ?? '????????').toString();
                                        // Used codes get the
                                        // strikethrough/grey
                                        // treatment — same visual
                                        // language as Google's
                                        // "used backup code" state,
                                        // matching web exactly.
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: isUsed
                                                ? (isDark
                                                ? Colors.grey[850]
                                                : Colors.grey[100])
                                                : const Color(0xFFF59E0B)
                                                .withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: isUsed
                                                  ? Colors.grey.withOpacity(0.3)
                                                  : const Color(0xFFF59E0B)
                                                  .withOpacity(0.4),
                                            ),
                                          ),
                                          child: Text(
                                            code,
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              letterSpacing: 1.2,
                                              color: isUsed
                                                  ? Colors.grey[500]
                                                  : const Color(0xFFB45309),
                                              decoration: isUsed
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 16),
                                    _buildGenerateButton(
                                        canGenerate: remaining == 0, remaining: remaining),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.withOpacity(0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('How This Works',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: isDark ? Colors.white : Colors.black87)),
                        const SizedBox(height: 10),
                        _bullet(
                            'Each code is single-use — the instant it\'s used to approve a cancellation, it\'s permanently marked used, on either web or mobile.',
                            isDark),
                        _bullet('Codes are scoped to this specific branch only.', isDark),
                        _bullet(
                            'A new batch of 8 can only be generated once every code in the current batch has been used.',
                            isDark),
                        _bullet(
                            'Every override used is recorded in the Admin Activity Log, including which employee used it.',
                            isDark),
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

  Widget _bullet(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600])),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600])),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerateButton({required bool canGenerate, int remaining = 0}) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton.icon(
        onPressed: (!canGenerate || _isGenerating) ? null : _generateNewBatch,
        icon: _isGenerating
            ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(canGenerate ? Icons.vpn_key : Icons.lock_clock, size: 18),
        label: Text(
          _isGenerating
              ? 'Generating...'
              : canGenerate
              ? 'Generate New Batch of 8'
              : '$remaining Code${remaining == 1 ? '' : 's'} Still Active',
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: canGenerate ? const Color(0xFFF59E0B) : Colors.grey,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}