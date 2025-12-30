import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import '../utils/closing_cycle_service.dart';
import 'profile_screen.dart';
import 'login_screen.dart';
import 'user_management_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService authService = AuthService();
  bool _useCustomClosing = false;
  int _closingHour = 0;
  int _closingMinute = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });
    final useCustom = await ClosingCycleService.isCustomClosingEnabled();
    final hour = await ClosingCycleService.getClosingHour();
    final minute = await ClosingCycleService.getClosingMinute();
    setState(() {
      _useCustomClosing = useCustom;
      _closingHour = hour;
      _closingMinute = minute;
      _isLoading = false;
    });
  }

  Future<void> _showTimePicker() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _closingHour, minute: _closingMinute),
      helpText: 'Select closing time',
    );
    if (picked != null) {
      setState(() {
        _closingHour = picked.hour;
        _closingMinute = picked.minute;
      });
      await ClosingCycleService.setClosingTime(_closingHour, _closingMinute);
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Account Section
          _buildSectionHeader('Account'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('Profile'),
                  subtitle: const Text('View and edit your profile'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfileScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Account Information'),
                  subtitle: Text('Role: ${_getRoleText(authService)}'),
                  enabled: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Access Section
          if (authService.canManageUsers())
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader('Access'),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.people),
                    title: const Text('People & Access'),
                    subtitle: const Text('Manage users & permissions'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const UserManagementScreen(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          const SizedBox(height: 24),

          // App Section
          _buildSectionHeader('App'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info),
                  title: const Text('About'),
                  subtitle: const Text('App version and information'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _showAboutDialog(context);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Business Settings Section
          _buildSectionHeader('Business Settings'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.access_time),
                  title: const Text('Custom Closing Cycle'),
                  subtitle: const Text('Set a custom time when your business day ends'),
                  value: _useCustomClosing,
                  onChanged: _isLoading
                      ? null
                      : (value) async {
                          setState(() {
                            _useCustomClosing = value;
                          });
                          await ClosingCycleService.setCustomClosingEnabled(value);
                        },
                ),
                if (_useCustomClosing) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.schedule),
                    title: const Text('Closing Time'),
                    subtitle: Text(
                      _isLoading
                          ? 'Loading...'
                          : 'Entries until ${_formatTime(_closingHour, _closingMinute)} are recorded as previous day',
                    ),
                    trailing: TextButton(
                      onPressed: _isLoading ? null : _showTimePicker,
                      child: Text(
                        _formatTime(_closingHour, _closingMinute),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Danger Zone
          _buildSectionHeader('Danger Zone'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: AppColors.error),
              title: const Text('Logout', style: TextStyle(color: AppColors.error)),
              subtitle: const Text('Sign out of your account'),
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Logout'),
                    content: const Text('Are you sure you want to logout?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.error,
                        ),
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true && context.mounted) {
                  await authService.logout();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (context) => const LoginScreen(),
                      ),
                      (route) => false,
                    );
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String _getRoleText(AuthService authService) {
    final role = authService.currentRole;
    if (role == null) return 'No role assigned';
    switch (role) {
      case UserRole.businessOwner:
        return 'Business Owner';
      case UserRole.owner:
        return 'Owner';
      case UserRole.manager:
        return 'Manager';
      case UserRole.staff:
        return 'Staff';
    }
  }

  String _formatTime(int hour, int minute) {
    final time = TimeOfDay(hour: hour, minute: minute);
    return time.format(context);
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'credilo',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text('Version 1.0.0'),
            SizedBox(height: 16),
            Text(
              'Manage your business finances, track expenses, sales, and more.',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

