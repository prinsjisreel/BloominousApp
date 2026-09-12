import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'inventory_data.dart';
import 'app_sidebar.dart';
import 'notification_bell.dart';

class ProfilePage extends StatefulWidget {
  final String role;
  const ProfilePage({super.key, this.role = 'employee'});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _passwordController = TextEditingController();
  bool _isUpdating = false;
  bool _isUploadingPhoto = false;

  Future<void> _pickAndUploadPhoto(String uid) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 80);
    if (picked == null) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final ref = FirebaseStorage.instance.ref().child('profile_photos').child('$uid.jpg');
      await ref.putFile(File(picked.path));
      final url = await ref.getDownloadURL();

      await InventoryData.updateOwnProfile(uid, {'photoUrl': url});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Photo upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Password'),
        content: TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New Password',
            hintText: 'Enter at least 6 characters',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              if (_passwordController.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password must be at least 6 characters')),
                );
                return;
              }
              Navigator.pop(context);
              setState(() => _isUpdating = true);
              try {
                await InventoryData.changePassword(_passwordController.text.trim());
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password updated successfully!')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              } finally {
                if (mounted) setState(() => _isUpdating = false);
                _passwordController.clear();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.white),
            child: const Text('UPDATE'),
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog(Map<String, dynamic>? userData, String uid) {
    final firstNameCtrl = TextEditingController(text: userData?['firstName'] ?? '');
    final middleNameCtrl = TextEditingController(text: userData?['middleName'] ?? '');
    final lastNameCtrl = TextEditingController(text: userData?['lastName'] ?? '');
    String selectedSex = (userData?['sex'] == 'Female') ? 'Female' : 'Male';
    DateTime? selectedBirthday = userData?['birthday'] != null
        ? DateTime.tryParse(userData!['birthday'].toString())
        : null;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Edit Profile', style: GoogleFonts.cormorantGaramond(fontWeight: FontWeight.bold, fontSize: 22)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: firstNameCtrl, decoration: const InputDecoration(labelText: 'First Name')),
                  const SizedBox(height: 12),
                  TextField(controller: middleNameCtrl, decoration: const InputDecoration(labelText: 'Middle Name')),
                  const SizedBox(height: 12),
                  TextField(controller: lastNameCtrl, decoration: const InputDecoration(labelText: 'Last Name')),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedBirthday ?? DateTime(2000),
                        firstDate: DateTime(1950),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setDialogState(() => selectedBirthday = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Birthday'),
                      child: Text(
                        selectedBirthday == null ? 'Select date' : DateFormat('MMM d, yyyy').format(selectedBirthday!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedSex,
                    decoration: const InputDecoration(labelText: 'Sex'),
                    items: const [
                      DropdownMenuItem(value: 'Male', child: Text('Male')),
                      DropdownMenuItem(value: 'Female', child: Text('Female')),
                    ],
                    onChanged: (val) => setDialogState(() => selectedSex = val ?? 'Male'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                  setDialogState(() => isSaving = true);
                  try {
                    await InventoryData.updateOwnProfile(uid, {
                      'firstName': firstNameCtrl.text.trim(),
                      'middleName': middleNameCtrl.text.trim(),
                      'lastName': lastNameCtrl.text.trim(),
                      'sex': selectedSex,
                      if (selectedBirthday != null)
                        'birthday': selectedBirthday!.toIso8601String().split('T')[0],
                    });
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Profile updated!'), backgroundColor: Colors.green),
                      );
                    }
                  } catch (e) {
                    setDialogState(() => isSaving = false);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.white),
                child: isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('SAVE'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
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
      appBar: AppBar(
        title: Text('My Profile', style: GoogleFonts.cormorantGaramond(fontWeight: FontWeight.bold, fontSize: 22)),
        backgroundColor: isDark ? Colors.black : const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      drawer: isDesktop ? null : Drawer(child: AppSidebar(role: widget.role, currentPage: 'profile')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) AppSidebar(role: widget.role, currentPage: 'profile'),
          Expanded(
            child: Stack(
              children: [
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').doc(user?.uid ?? '').snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)));
                    }

                    final userData = snapshot.data?.data() as Map<String, dynamic>?;
                    final email = userData?['email'] ?? user?.email ?? 'No Email';
                    final firstName = (userData?['firstName'] ?? '').toString();
                    final lastName = (userData?['lastName'] ?? '').toString();
                    final middleName = (userData?['middleName'] ?? '').toString();
                    final name = (firstName.isNotEmpty || lastName.isNotEmpty)
                        ? '$firstName $middleName $lastName'.replaceAll(RegExp(r'\s+'), ' ').trim()
                        : (userData?['name'] ?? user?.displayName ?? 'User').toString();
                    final role = (userData?['role'] ?? widget.role).toString();
                    final isAdmin = role == 'admin' || role == 'super-admin';
                    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
                    final photoUrl = (userData?['photoUrl'] ?? '').toString();
                    final uid = user?.uid ?? '';

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(color: borderColor),
                                boxShadow: [
                                  if (!isDark)
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 10)),
                                ],
                              ),
                              child: Column(
                                children: [
                                  GestureDetector(
                                    onTap: _isUploadingPhoto ? null : () => _pickAndUploadPhoto(uid),
                                    child: Stack(
                                      children: [
                                        CircleAvatar(
                                          radius: 46,
                                          backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                          backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                                          child: photoUrl.isEmpty
                                              ? Text(initial, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)))
                                              : null,
                                        ),
                                        if (_isUploadingPhoto)
                                          Positioned.fill(
                                            child: CircleAvatar(
                                              radius: 46,
                                              backgroundColor: Colors.black45,
                                              child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                            ),
                                          )
                                        else
                                          Positioned(
                                            bottom: 0,
                                            right: 0,
                                            child: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF59E0B),
                                                shape: BoxShape.circle,
                                                border: Border.all(color: cardColor, width: 2),
                                              ),
                                              child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(name,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.cormorantGaramond(fontSize: 26, fontWeight: FontWeight.bold, color: textColor)),
                                  const SizedBox(height: 4),
                                  Text(email, style: TextStyle(fontSize: 13, color: subTextColor)),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      role == 'super-admin'
                                          ? 'SUPER ADMINISTRATOR'
                                          : (role == 'admin' ? 'ADMINISTRATOR' : 'STAFF / EMPLOYEE'),
                                      style: const TextStyle(
                                          fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Color(0xFFF59E0B)),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _showEditProfileDialog(userData, uid),
                                      icon: const Icon(Icons.edit_outlined, size: 16),
                                      label: const Text('EDIT PROFILE'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFFF59E0B),
                                        side: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                    ),
                                  ),
                                  if (userData == null) ...[
                                    const SizedBox(height: 16),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.redAccent),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text('No Firestore profile found for $email',
                                                style: const TextStyle(fontSize: 11, color: Colors.redAccent)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (isAdmin)
                              _buildActionCard(
                                cardColor: cardColor,
                                borderColor: borderColor,
                                textColor: textColor,
                                subTextColor: subTextColor,
                                icon: Icons.lock_outline,
                                title: 'Change Password',
                                subtitle: 'Update your login security',
                                onTap: _showChangePasswordDialog,
                              ),
                            // FIXED: was a placeholder snackbar ("coming
                            // soon") — now opens the exact same live
                            // notification panel as the top-bar bell icon,
                            // via the shared openNotificationsSheet()
                            // function.
                            _buildActionCard(
                              cardColor: cardColor,
                              borderColor: borderColor,
                              textColor: textColor,
                              subTextColor: subTextColor,
                              icon: Icons.notifications_none_outlined,
                              title: 'Notifications',
                              subtitle: 'View recent business updates',
                              onTap: () => openNotificationsSheet(context),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  await FirebaseAuth.instance.signOut();
                                  if (context.mounted) {
                                    Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.withValues(alpha: 0.08),
                                  foregroundColor: Colors.redAccent,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                ),
                                child: const Text('Log Out', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                if (_isUpdating)
                  Container(
                    color: Colors.black26,
                    child: const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B))),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required Color cardColor,
    required Color borderColor,
    required Color textColor,
    required Color subTextColor,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFFF59E0B)),
        ),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: subTextColor)),
        trailing: Icon(Icons.chevron_right, color: subTextColor),
      ),
    );
  }
}