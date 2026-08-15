import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'inventory_data.dart';

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
          // If already exists, just update the Firestore record
          try {
            await InventoryData.updateUserRoleAndBranch(
              emailController.text.trim(),
              selectedRole,
              selectedBranchId,
            );
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Account updated successfully!')));
            Navigator.pop(context);
          } catch (updateError) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Update Error: $updateError')));
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Manage Staff & Delivery',
            style: GoogleFonts.cormorantGaramond(
                fontWeight: FontWeight.bold, fontSize: 22)),
        backgroundColor: isDark ? Colors.black : const Color(0xFFF59E0B),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text('Add New Staff/Delivery',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      TextField(
                          controller: firstNameController,
                          decoration:
                              const InputDecoration(labelText: 'First Name')),
                      TextField(
                          controller: middleNameController,
                          decoration:
                              const InputDecoration(labelText: 'Middle Name')),
                      TextField(
                          controller: lastNameController,
                          decoration:
                              const InputDecoration(labelText: 'Last Name')),
                      ListTile(
                        title: Text(selectedBirthday == null
                            ? 'Select Birthday'
                            : 'Birthday: ${selectedBirthday!.toIso8601String().split('T')[0]}'),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime(2000),
                            firstDate: DateTime(1950),
                            lastDate: DateTime.now(),
                          );
                          if (date != null)
                            setState(() => selectedBirthday = date);
                        },
                      ),
                      DropdownButtonFormField<String>(
                        value: selectedSex,
                        decoration: const InputDecoration(labelText: 'Sex'),
                        items: const [
                          DropdownMenuItem(value: 'Male', child: Text('Male')),
                          DropdownMenuItem(
                              value: 'Female', child: Text('Female')),
                        ],
                        onChanged: (val) => setState(() => selectedSex = val!),
                      ),
                      TextField(
                          controller: emailController,
                          decoration:
                              const InputDecoration(labelText: 'Email')),
                      TextField(
                          controller: passwordController,
                          decoration: const InputDecoration(
                              labelText: 'Temporary Password'),
                          obscureText: true),
                      const SizedBox(height: 16),
                      StreamBuilder<List<Map<String, dynamic>>>(
                          stream: InventoryData.getBranchesStream(),
                          builder: (context, snapshot) {
                            final branches = snapshot.data ?? [];
                            return DropdownButtonFormField<String>(
                              value: selectedBranchId,
                              decoration: const InputDecoration(
                                  labelText: 'Assign to Branch'),
                              items: branches
                                  .map((b) => DropdownMenuItem(
                                        value: b['id'] as String,
                                        child: Text(b['name'] as String),
                                      ))
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => selectedBranchId = val),
                            );
                          }),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedRole,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: [
                          const DropdownMenuItem(
                              value: 'employee', child: Text('Staff/Employee')),
                          const DropdownMenuItem(
                              value: 'delivery',
                              child: Text('Delivery Employee')),
                          if (widget.role == 'super-admin')
                            const DropdownMenuItem(
                                value: 'admin', child: Text('Administrator')),
                        ],
                        onChanged: (val) => setState(() => selectedRole = val!),
                      ),
                      const SizedBox(height: 20),
                      if (isLoading)
                        const CircularProgressIndicator()
                      else
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _addEmployee,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF59E0B),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('ADD ACCOUNT',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.1)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Current Accounts',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: InventoryData.employeesStream(
                  roles: widget.role == 'super-admin'
                      ? ['employee', 'delivery', 'admin']
                      : ['employee', 'delivery']),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                final employees = snapshot.data!;
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: employees.length,
                  itemBuilder: (context, index) {
                    final emp = employees[index];
                    final role = emp['role'] ?? 'employee';
                    final bId = emp['branchId'] ?? 'Not Assigned';

                    return FutureBuilder<Map<String, dynamic>?>(
                        future: InventoryData.getBranchDetails(bId),
                        builder: (context, branchSnap) {
                          final bName =
                              branchSnap.data?['name'] ?? 'Not Assigned';
                          final fullName =
                              '${emp['firstName'] ?? ''} ${emp['middleName'] ?? ''} ${emp['lastName'] ?? emp['name'] ?? ''}'
                                  .trim();
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: role == 'super-admin'
                                  ? Colors.purple
                                  : (role == 'admin'
                                      ? Colors.red
                                      : (role == 'delivery'
                                          ? Colors.blue
                                          : Colors.orange)),
                              child: Icon(
                                  role == 'delivery'
                                      ? Icons.delivery_dining
                                      : (role == 'admin' ||
                                              role == 'super-admin'
                                          ? Icons.admin_panel_settings
                                          : Icons.person),
                                  color: Colors.white),
                            ),
                            title: Text(
                                fullName.isEmpty ? emp['email'] : fullName),
                            subtitle: Text(
                                'Role: ${role.toUpperCase()} | Branch: $bName'),
                          );
                        });
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
