import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'change_password_page.dart';
import 'shop_location_page.dart';
import 'main.dart';

class SettingsPage extends StatefulWidget {
  final String role;
  const SettingsPage({super.key, this.role = 'employee'});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'SETTINGS',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
            fontSize: 18,
            color: isDarkMode ? Colors.white : const Color(0xFF121212),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: isDarkMode ? Colors.white : const Color(0xFF121212)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          // Account Section
          _buildSectionHeader('ACCOUNT'),
          _buildSettingTile(
            context,
            icon: Icons.person_outline_rounded,
            title: 'Email',
            subtitle: user?.email ?? 'Not logged in',
            onTap: null,
          ),
          if (widget.role == 'admin' || widget.role == 'super-admin') ...[
            _buildSettingTile(
              context,
              icon: Icons.lock_outline_rounded,
              title: 'Change Password',
              subtitle: 'Update your security credentials',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const ChangePasswordPage()),
                );
              },
            ),
            _buildSettingTile(
              context,
              icon: Icons.store_outlined,
              title: 'Shop Location',
              subtitle: 'Set shop coordinates for delivery fees',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) =>
                          ShopLocationPage(role: widget.role)),
                );
              },
            ),
          ],
          const SizedBox(height: 32),

          // Preferences Section
          _buildSectionHeader('PREFERENCES'),
          _buildSwitchTile(
            context,
            icon: Icons.notifications_none_rounded,
            title: 'Push Notifications',
            value: _notificationsEnabled,
            onChanged: (val) => setState(() => _notificationsEnabled = val),
          ),
          _buildSwitchTile(
            context,
            icon: Icons.dark_mode_outlined,
            title: 'Dark Mode',
            value: isDarkMode,
            onChanged: (val) {
              setState(() {
                themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
              });
            },
          ),
          const SizedBox(height: 32),

          // App Info Section
          _buildSectionHeader('APP INFO'),
          _buildSettingTile(
            context,
            icon: Icons.info_outline_rounded,
            title: 'Version',
            subtitle: '1.0.2 Build 2026',
            onTap: null,
          ),
          _buildSettingTile(
            context,
            icon: Icons.description_outlined,
            title: 'Terms of Service',
            subtitle: 'Read our policies',
            onTap: () {
              // Show a simple dialog for now
              showAboutDialog(
                context: context,
                applicationName: 'BloomyPro POS',
                applicationVersion: '1.0.2',
                applicationLegalese: '© 2026 Bloom AR Flower Shop',
              );
            },
          ),
          _buildSettingTile(
            context,
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            subtitle: 'How we handle your data',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Privacy Policy coming soon!')),
              );
            },
          ),
          _buildSettingTile(
            context,
            icon: Icons.help_outline_rounded,
            title: 'Help & Support',
            subtitle: 'Get assistance with the app',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Support feature coming soon!')),
              );
            },
          ),
          const SizedBox(height: 40),

          // Logout Button
          ElevatedButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isDarkMode
                  ? Colors.red[900]!.withValues(alpha: 0.2)
                  : Colors.red[50],
              foregroundColor: isDarkMode ? Colors.red[300] : Colors.red[700],
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout_rounded),
                SizedBox(width: 12),
                Text('Logout Account',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.grey[400],
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF4B400).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon,
              color: isDark ? Colors.white : const Color(0xFF121212), size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: isDark ? Colors.white : Colors.black),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600]),
        ),
        trailing: onTap != null
            ? Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: Colors.grey[300])
            : null,
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF4B400).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon,
              color: isDark ? Colors.white : const Color(0xFF121212), size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: isDark ? Colors.white : Colors.black),
        ),
        activeColor: const Color(0xFFF4B400),
      ),
    );
  }
}
