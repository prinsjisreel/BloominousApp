import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'inventory_data.dart';
import 'app_sidebar.dart';
import 'admin_audit_service.dart';

class ManageEmployeesPage extends StatefulWidget {
  final String role;
  const ManageEmployeesPage({super.key, this.role = 'admin'});

  @override
  State<ManageEmployeesPage> createState() => _ManageEmployeesPageState();
}

class _ManageEmployeesPageState extends State<ManageEmployeesPage> {
  final firstNameController = TextEditingController();
  final middleNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  DateTime? selectedBirthday;
  String selectedSex = 'Male';
  bool isLoading = false;
  bool isMigrating = false;

  String selectedRole = 'employee';
  String? selectedBranchId;
  String _listFilter = 'All';

  // How long an invite stays valid. Must match the web (10 minutes).
  static const Duration _inviteTtl = Duration(minutes: 10);

  @override
  void dispose() {
    firstNameController.dispose();
    middleNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  /// Creates a staff account using the invite-token pattern.
  /// Mirrors createEmployeeAccount() in BloominousWeb's manage_accounts.php:
  ///   1. Pre-checks: email must not be a customer or an existing account.
  ///   2. Secondary app creates the Firebase Auth account.
  ///   3. DEFAULT app (the super-admin's own session) writes invites/{newUid}.
  ///   4. Secondary app (signed in AS the new account) writes its own
  ///      employees/{newUid} + users/{newUid}; rules approve via hasValidInvite().
  ///   5. Invite deleted, secondary app cleaned up -- ALWAYS, even on failure.
  /// If anything fails after step 2, the half-made account is rolled back.
  Future<void> _addEmployee() async {
    // Guard: UI mirror of Option B (the rules are the real lock).
    if (widget.role != 'super-admin') {
      _showSnack('Only the super-admin can create accounts.', color: Colors.red);
      return;
    }

    if (firstNameController.text.trim().isEmpty ||
        lastNameController.text.trim().isEmpty ||
        emailController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty ||
        selectedBranchId == null ||
        selectedBirthday == null) {
      _showSnack('Please fill all required fields and select a branch');
      return;
    }

    // Guard: the invite's createdBy must be the super-admin's uid.
    final currentAdmin = FirebaseAuth.instance.currentUser;
    if (currentAdmin == null) {
      _showSnack('Your session has expired. Please log in again.', color: Colors.red);
      return;
    }

    setState(() => isLoading = true);
    final normalizedEmail = emailController.text.trim().toLowerCase();
    final db = FirebaseFirestore.instance; // DEFAULT app = super-admin session

    FirebaseApp? secondaryApp;
    User? newUser;
    DocumentReference<Map<String, dynamic>>? inviteRef;
    bool completed = false;
    String step = 'checking existing records';

    try {
      // STEP 1: pre-checks (same two checks as the web).
      final customerLookup = await db
          .collection('customers')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      if (customerLookup.docs.isNotEmpty) {
        throw const _UserFacingError(
            'This email is already registered as a customer. Customer accounts cannot be converted into staff accounts here.');
      }

      final userLookup = await db
          .collection('users')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      if (userLookup.docs.isNotEmpty) {
        throw const _UserFacingError(
            'An account already exists for this email.');
      }

      // STEP 2: a uniquely named secondary app, so a leftover from a
      // previous failed attempt can never cause a duplicate-app crash.
      step = 'preparing the account creator';
      secondaryApp = await Firebase.initializeApp(
        name: 'SecondaryApp_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );

      step = 'creating the login account (Firebase Auth)';
      final cred = await FirebaseAuth.instanceFor(app: secondaryApp)
          .createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: passwordController.text.trim(),
      );
      newUser = cred.user;
      if (newUser == null) {
        throw const _UserFacingError('Firebase did not return the new account.');
      }
      final newUid = newUser.uid;

      // STEP 3: the permission slip, written by the super-admin's session.
      step = 'writing the invite (your super-admin session)';
      inviteRef = db.collection('invites').doc(newUid);
      await inviteRef.set({
        'role': selectedRole,
        'email': normalizedEmail,
        'createdBy': currentAdmin.uid,
        'expiresAt': Timestamp.fromDate(DateTime.now().add(_inviteTtl)),
      });

      // STEP 4: the new account writes its own docs via the secondary app.
      step = 'writing the employee profile (new account session)';
      await InventoryData.createNewEmployee(
        uid: newUid,
        firstName: firstNameController.text.trim(),
        middleName: middleNameController.text.trim(),
        lastName: lastNameController.text.trim(),
        birthday: selectedBirthday!.toIso8601String().split('T')[0],
        sex: selectedSex,
        email: normalizedEmail,
        role: selectedRole,
        branchId: selectedBranchId,
        firestoreInstance: FirebaseFirestore.instanceFor(app: secondaryApp),
      );
      completed = true;

      // Audit log is best-effort: a logging failure must never make a
      // successful account creation look like a failure.
      try {
        await AdminAuditService.logAction(
          action: 'create_employee_account',
          targetUid: newUid,
          targetEmail: normalizedEmail,
          details:
          'Created new $selectedRole account, assigned to branch $selectedBranchId.',
        );
      } catch (auditError) {
        debugPrint('Audit log write failed (account still created): $auditError');
      }

      if (mounted) {
        _showSnack('${selectedRole.toUpperCase()} added successfully!',
            color: const Color(0xFF10B981));
        Navigator.pop(context);
      }
    } catch (e) {
      // ROLLBACK: never leave a half-made account behind.
      if (!completed && newUser != null) {
        final orphanUid = newUser.uid;
        for (final collection in ['employees', 'users']) {
          try {
            await db.collection(collection).doc(orphanUid).delete();
          } catch (_) {
            // Doc may not exist yet -- nothing to clean.
          }
        }
        try {
          // The secondary app is still signed in as this user, so it can delete itself.
          await newUser.delete();
        } catch (cleanupError) {
          debugPrint('Rollback: could not delete Auth account: $cleanupError');
        }
      }

      String message;
      if (e is _UserFacingError) {
        message = e.message;
      } else if (e is FirebaseAuthException && e.code == 'email-already-in-use') {
        // Pre-checks passed, so this is a login with no Firestore profile
        // (usually left over from an earlier failed attempt).
        message =
        'A login already exists for this email but has no profile. Delete it in Firebase Console > Authentication, or use another email.';
      } else if (e is FirebaseAuthException && e.code == 'weak-password') {
        message = 'Password is too weak. Use at least 6 characters.';
      } else {
        message = 'Failed while $step: $e';
      }
      _showSnack(message, color: Colors.red);
    } finally {
      // CLEANUP: runs on success AND failure.
      if (inviteRef != null) {
        try {
          await inviteRef.delete();
        } catch (_) {
          // Non-fatal -- the invite expires on its own.
        }
      }
      if (secondaryApp != null) {
        try {
          await FirebaseAuth.instanceFor(app: secondaryApp).signOut();
        } catch (_) {}
        try {
          await secondaryApp.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _deleteEmployee(String uid, String targetRole, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove This Account?'),
        content: Text('This permanently removes $displayName\'s account. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('REMOVE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await InventoryData.deleteEmployeeAccount(
        uid: uid,
        targetRole: targetRole,
        callerRole: widget.role,
      );

      try {
        await AdminAuditService.logAction(
          action: 'delete_employee_account',
          targetUid: uid,
          targetEmail: displayName,
          details: 'Removed $targetRole account.',
        );
      } catch (auditError) {
        debugPrint('Audit log write failed (account still removed): $auditError');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account removed successfully!'), backgroundColor: Color(0xFF10B981)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove account: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _runLegacyMigration() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Run Legacy Data Migration?'),
        content: const Text(
          'This copies any employee/admin/delivery account created before '
              'the new Employees collection existed into it. Safe to run '
              'more than once -- accounts already migrated are skipped.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
            child: const Text('RUN', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => isMigrating = true);
    try {
      final result = await InventoryData.migrateLegacyEmployeesToEmployeesCollection();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Migration complete: ${result['migrated']} account(s) migrated, '
                    '${result['skippedAlready']} already up to date.'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Migration failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => isMigrating = false);
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'super-admin':
        return Colors.purple;
      case 'admin':
        return Colors.red;
      case 'delivery':
        return Colors.blue;
      default:
        return const Color(0xFFF59E0B);
    }
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'delivery':
        return Icons.delivery_dining_rounded;
      case 'admin':
      case 'super-admin':
        return Icons.admin_panel_settings_rounded;
      default:
        return Icons.person_rounded;
    }
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 850;
    final outerPadding = screenWidth < 380 ? 12.0 : 20.0;
    final canAddAccounts = widget.role == 'super-admin';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text('Manage Staff & Delivery',
            style: GoogleFonts.cormorantGaramond(fontWeight: FontWeight.bold, fontSize: 22)),
        backgroundColor: isDark ? Colors.black : const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      drawer: isDesktop ? null : Drawer(child: AppSidebar(role: widget.role, currentPage: 'employees')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) AppSidebar(role: widget.role, currentPage: 'employees'),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(outerPadding),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
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
                              if (isDesktop)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    'Manage Staff & Delivery',
                                    style: GoogleFonts.cormorantGaramond(fontSize: 30, fontWeight: FontWeight.bold, color: textColor),
                                  ),
                                ),
                              Text(
                                canAddAccounts
                                    ? 'Create staff, delivery, and admin accounts, and assign them to a branch.'
                                    : 'View staff and delivery assignments. Adding accounts is restricted to the super-admin.',
                                style: TextStyle(fontSize: 12, color: subTextColor),
                              ),
                            ],
                          ),
                        ),
                        if (widget.role == 'super-admin')
                          Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: OutlinedButton.icon(
                              onPressed: isMigrating ? null : _runLegacyMigration,
                              icon: isMigrating
                                  ? const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                                  : const Icon(Icons.sync_rounded, size: 16),
                              label: const Text('Migrate Legacy Data', style: TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFF59E0B),
                                side: const BorderSide(color: Color(0xFFF59E0B)),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    if (canAddAccounts)
                      Container(
                        padding: EdgeInsets.all(screenWidth < 380 ? 16 : 24),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: borderColor),
                          boxShadow: [
                            if (!isDark)
                              BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 10)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                                  child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFFF59E0B)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text('Add New Staff / Delivery',
                                      style: GoogleFonts.cormorantGaramond(fontSize: 22, fontWeight: FontWeight.bold, color: textColor),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            LayoutBuilder(builder: (context, constraints) {
                              final isNarrow = constraints.maxWidth < 700;
                              final nameFields = [
                                _field(firstNameController, 'First Name', isDark, borderColor),
                                _field(middleNameController, 'Middle Name', isDark, borderColor),
                                _field(lastNameController, 'Last Name', isDark, borderColor),
                              ];
                              return isNarrow
                                  ? Column(children: nameFields.map((f) => Padding(padding: const EdgeInsets.only(bottom: 14), child: f)).toList())
                                  : Row(children: nameFields.map((f) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: f))).toList());
                            }),
                            const SizedBox(height: 14),

                            InkWell(
                              onTap: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: selectedBirthday ?? DateTime(2000),
                                  firstDate: DateTime(1950),
                                  lastDate: DateTime.now(),
                                );
                                if (date != null) setState(() => selectedBirthday = date);
                              },
                              child: InputDecorator(
                                decoration: _decoration('Birthday', isDark, borderColor).copyWith(
                                  suffixIcon: Icon(Icons.calendar_today_rounded, size: 18, color: subTextColor),
                                ),
                                child: Text(
                                  selectedBirthday == null ? 'Select date' : selectedBirthday!.toIso8601String().split('T')[0],
                                  style: TextStyle(color: selectedBirthday == null ? subTextColor : textColor, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            DropdownButtonFormField<String>(
                              value: selectedSex,
                              decoration: _decoration('Sex', isDark, borderColor),
                              dropdownColor: cardColor,
                              isExpanded: true,
                              style: TextStyle(color: textColor, fontSize: 14),
                              items: const [
                                DropdownMenuItem(value: 'Male', child: Text('Male')),
                                DropdownMenuItem(value: 'Female', child: Text('Female')),
                              ],
                              onChanged: (val) => setState(() => selectedSex = val!),
                            ),
                            const SizedBox(height: 14),

                            _field(emailController, 'Email', isDark, borderColor, keyboardType: TextInputType.emailAddress),
                            const SizedBox(height: 14),
                            _field(passwordController, 'Temporary Password', isDark, borderColor, obscureText: true),
                            const SizedBox(height: 14),

                            StreamBuilder<List<Map<String, dynamic>>>(
                              stream: InventoryData.getBranchesStream(),
                              builder: (context, snapshot) {
                                final branches = snapshot.data ?? [];
                                final validExists = selectedBranchId != null && branches.any((b) => b['id'] == selectedBranchId);
                                return DropdownButtonFormField<String>(
                                  value: validExists ? selectedBranchId : null,
                                  decoration: _decoration('Assign to Branch', isDark, borderColor),
                                  dropdownColor: cardColor,
                                  isExpanded: true,
                                  style: TextStyle(color: textColor, fontSize: 14),
                                  items: branches
                                      .map((b) => DropdownMenuItem(value: b['id'] as String, child: Text(b['name'] as String, overflow: TextOverflow.ellipsis)))
                                      .toList(),
                                  onChanged: (val) => setState(() => selectedBranchId = val),
                                );
                              },
                            ),
                            const SizedBox(height: 14),

                            DropdownButtonFormField<String>(
                              value: selectedRole,
                              decoration: _decoration('Role', isDark, borderColor),
                              dropdownColor: cardColor,
                              isExpanded: true,
                              style: TextStyle(color: textColor, fontSize: 14),
                              items: const [
                                DropdownMenuItem(value: 'employee', child: Text('Staff/Employee')),
                                DropdownMenuItem(value: 'delivery', child: Text('Delivery Employee')),
                                DropdownMenuItem(value: 'admin', child: Text('Administrator')),
                              ],
                              onChanged: (val) => setState(() => selectedRole = val!),
                            ),
                            const SizedBox(height: 22),

                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: isLoading ? null : _addEmployee,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF59E0B),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                child: isLoading
                                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text('ADD ACCOUNT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.lock_outline_rounded, color: subTextColor, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Only a super-admin can add or change staff, delivery, and admin accounts. You can still view current accounts below.',
                                style: TextStyle(fontSize: 12.5, color: subTextColor, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 32),
                    Text('Current Accounts', style: GoogleFonts.cormorantGaramond(fontSize: 22, fontWeight: FontWeight.bold, color: textColor)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _filterChip('All', isDark, textColor),
                        _filterChip('Employee', isDark, textColor),
                        _filterChip('Delivery', isDark, textColor),
                        if (widget.role == 'super-admin') _filterChip('Admin', isDark, textColor),
                      ],
                    ),
                    const SizedBox(height: 16),

                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: InventoryData.employeesStream(
                          roles: widget.role == 'super-admin' ? ['employee', 'delivery', 'admin'] : ['employee', 'delivery']),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 30), child: CircularProgressIndicator(color: Color(0xFFF59E0B))));
                        }

                        var employees = snapshot.data!;
                        if (_listFilter != 'All') {
                          employees = employees.where((e) => (e['role'] ?? 'employee').toString().toLowerCase() == _listFilter.toLowerCase()).toList();
                        }

                        if (employees.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            width: double.infinity,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20), border: Border.all(color: borderColor)),
                            child: Text('No accounts found for this filter.', style: TextStyle(color: subTextColor, fontStyle: FontStyle.italic)),
                          );
                        }

                        return Column(
                          children: employees.map((emp) {
                            final role = (emp['role'] ?? 'employee').toString();
                            final bId = emp['branchId'] ?? 'Not Assigned';
                            final color = _roleColor(role);
                            final uid = emp['id'] as String;
                            final canRemove = InventoryData.canRemoveAccount(widget.role, role);

                            return FutureBuilder<Map<String, dynamic>?>(
                              future: bId == 'Not Assigned' ? Future.value(null) : InventoryData.getBranchDetails(bId),
                              builder: (context, branchSnap) {
                                final bName = branchSnap.data?['name'] ?? 'Not Assigned';
                                final fullName = '${emp['firstName'] ?? ''} ${emp['middleName'] ?? ''} ${emp['lastName'] ?? emp['name'] ?? ''}'.trim();
                                final displayName = fullName.isEmpty ? (emp['email'] ?? 'Unknown') : fullName;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(18), border: Border.all(color: borderColor)),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundColor: color.withValues(alpha: 0.12),
                                        child: Icon(_roleIcon(role), color: color, size: 20),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(displayName,
                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis),
                                            const SizedBox(height: 4),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 4,
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                                                  child: Text(role.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
                                                ),
                                                ConstrainedBox(
                                                  constraints: const BoxConstraints(maxWidth: 160),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.storefront_rounded, size: 11, color: subTextColor),
                                                      const SizedBox(width: 3),
                                                      Flexible(
                                                        child: Text(bName,
                                                            style: TextStyle(fontSize: 11, color: subTextColor),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (canRemove)
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                                          tooltip: 'Remove account',
                                          onPressed: () => _deleteEmployee(uid, role, displayName.toString()),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool isDark, Color textColor) {
    final selected = _listFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _listFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF59E0B) : (isDark ? Colors.grey[900] : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? const Color(0xFFF59E0B) : Colors.grey.withValues(alpha: 0.25)),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: selected ? Colors.white : textColor)),
      ),
    );
  }

  InputDecoration _decoration(String label, bool isDark, Color borderColor) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: isDark ? const Color(0xFF222222) : const Color(0xFFFAFAFA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFF59E0B))),
    );
  }

  Widget _field(TextEditingController controller, String label, bool isDark, Color borderColor,
      {TextInputType? keyboardType, bool obscureText = false}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: _decoration(label, isDark, borderColor),
    );
  }
}

/// An error whose message is already written for the user, so it's
/// shown as-is instead of being prefixed with "Failed while ...".
class _UserFacingError implements Exception {
  final String message;
  const _UserFacingError(this.message);
  @override
  String toString() => message;
}