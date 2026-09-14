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

  String selectedRole = 'employee';
  String? selectedBranchId;
  String _listFilter = 'All';

  Future<void> _addEmployee() async {
    if (firstNameController.text.isEmpty ||
        lastNameController.text.isEmpty ||
        emailController.text.isEmpty ||
        passwordController.text.isEmpty ||
        selectedBranchId == null ||
        selectedBirthday == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
          Text('Please fill all required fields and select a branch')));
      return;
    }

    setState(() => isLoading = true);
    final normalizedEmail = emailController.text.trim().toLowerCase();

    try {
      final secondaryApp = await Firebase.initializeApp(
        name: 'SecondaryApp',
        options: Firebase.app().options,
      );

      final cred = await FirebaseAuth.instanceFor(app: secondaryApp)
          .createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: passwordController.text.trim(),
      );

      if (cred.user != null) {
        await InventoryData.createNewEmployee(
          uid: cred.user!.uid,
          firstName: firstNameController.text.trim(),
          middleName: middleNameController.text.trim(),
          lastName: lastNameController.text.trim(),
          birthday: selectedBirthday!.toIso8601String().split('T')[0],
          sex: selectedSex,
          email: normalizedEmail,
          role: selectedRole,
          branchId: selectedBranchId,
        );

        // Account creation — a NEW privileged account existing at all is
        // worth a permanent record, same tier as restricting a customer
        // or banning a device.
        await AdminAuditService.logAction(
          action: 'create_employee_account',
          targetUid: cred.user!.uid,
          targetEmail: normalizedEmail,
          details:
          'Created new $selectedRole account, assigned to branch $selectedBranchId.',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
              Text('${selectedRole.toUpperCase()} added successfully!')));
          Navigator.pop(context);
        }
      }

      await secondaryApp.delete();
    } catch (e) {
      if (mounted) {
        String errorMessage = e.toString();
        if (errorMessage.contains('email-already-in-use')) {
          try {
            // This IS a role/branch change on an EXISTING account —
            // previously the single most dangerous unlogged action in
            // this whole system (an admin could silently promote any
            // account to 'admin' with zero trace). Reading the doc
            // FIRST, before the update, is what makes "changed from X
            // to Y" possible in the log rather than just "changed to Y".
            final existingQuery = await FirebaseFirestore.instance
                .collection('users')
                .where('email', isEqualTo: normalizedEmail)
                .limit(1)
                .get();

            String? targetUid;
            String previousRole = 'unknown';
            String? previousBranchId;

            if (existingQuery.docs.isNotEmpty) {
              final doc = existingQuery.docs.first;
              targetUid = doc.id;
              previousRole = (doc.data()['role'] ?? 'unknown').toString();
              previousBranchId = doc.data()['branchId']?.toString();
            }

            await InventoryData.updateUserRoleAndBranch(
              emailController.text.trim(),
              selectedRole,
              selectedBranchId,
            );

            // targetUid falls back to the email itself only in the rare
            // case the pre-update lookup somehow found nothing (the
            // account still visibly exists via 'email-already-in-use',
            // so this should be uncommon) — firestore.rules only
            // requires targetUid to be a string, so this still writes
            // successfully, it's just less useful for cross-referencing
            // than a real UID would be.
            await AdminAuditService.logAction(
              action: 'update_employee_role',
              targetUid: targetUid ?? normalizedEmail,
              targetEmail: normalizedEmail,
              details:
              'Role changed from "$previousRole" to "$selectedRole"'
                  '${previousBranchId != selectedBranchId ? ', branch changed from "$previousBranchId" to "$selectedBranchId"' : ''}.',
            );

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Account updated successfully!')));
              Navigator.pop(context);
            }
          } catch (updateError) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Update Error: $updateError')));
            }
          }
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
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
                    if (isDesktop)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Manage Staff & Delivery',
                          style: GoogleFonts.cormorantGaramond(fontSize: 30, fontWeight: FontWeight.bold, color: textColor),
                        ),
                      ),
                    Text(
                      'Create staff, delivery, and admin accounts, and assign them to a branch.',
                      style: TextStyle(fontSize: 12, color: subTextColor),
                    ),
                    const SizedBox(height: 20),

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
                            items: [
                              const DropdownMenuItem(value: 'employee', child: Text('Staff/Employee')),
                              const DropdownMenuItem(value: 'delivery', child: Text('Delivery Employee')),
                              if (widget.role == 'super-admin')
                                const DropdownMenuItem(value: 'admin', child: Text('Administrator')),
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