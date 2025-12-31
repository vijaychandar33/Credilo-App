import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
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
  final DatabaseService _dbService = DatabaseService();
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
    var hour = await ClosingCycleService.getClosingHour();
    final minute = await ClosingCycleService.getClosingMinute();
    
    // Migrate 12:00 AM (hour 0) to 1:00 AM if custom closing is enabled
    if (useCustom && hour == 0) {
      hour = 1;
      await ClosingCycleService.setClosingTime(hour, minute);
    }
    
    setState(() {
      _useCustomClosing = useCustom;
      _closingHour = hour;
      _closingMinute = minute;
      _isLoading = false;
    });
  }

  Future<void> _showTimePicker() async {
    // Ensure initial time is valid (1:00 AM - 11:00 PM)
    final initialHour = _closingHour == 0 ? 1 : _closingHour;
    final initialTime = TimeOfDay(hour: initialHour, minute: _closingMinute);
    
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: 'Select closing time (1:00 AM - 11:00 PM)',
    );
    
    if (picked != null) {
      // Validate: Must be between 1:00 AM and 11:00 PM (hours 1-23)
      if (picked.hour == 0) {
        // 12:00 AM is not allowed
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Closing time cannot be 12:00 AM. Please select a time between 1:00 AM and 11:00 PM.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      
      // Hours 1-23 are valid (1:00 AM to 11:00 PM)
      if (picked.hour >= 1 && picked.hour <= 23) {
        setState(() {
          _closingHour = picked.hour;
          _closingMinute = picked.minute;
        });
        await ClosingCycleService.setClosingTime(_closingHour, _closingMinute);
      } else {
        // This shouldn't happen with standard time picker, but handle it anyway
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a time between 1:00 AM and 11:00 PM.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
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
                          // If enabling, allow it and reload settings to get default time
                          if (value) {
                            setState(() {
                              _useCustomClosing = value;
                            });
                            await ClosingCycleService.setCustomClosingEnabled(value);
                            // Reload settings to get the default 1:00 AM time if it was set
                            await _loadSettings();
                            return;
                          }

                          // If disabling, check for data that would be affected
                          if (!value && _useCustomClosing) {
                            // Show loading indicator
                            if (!mounted) return;
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );

                            try {
                              // Get all branch IDs the user has access to
                              final branches = authService.userBranches;
                              final branchIds = branches.map((b) => b.id).toList();

                              // Check if there's any data after midnight
                              final hasData = await _dbService.hasDataAfterMidnight(branchIds);

                              if (!mounted) return;
                              Navigator.pop(context); // Close loading dialog

                              if (hasData) {
                                // Show error dialog
                                if (!mounted) return;
                                await showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Cannot Disable Custom Closing'),
                                    content: const Text(
                                      'You cannot disable custom closing cycle because there is data recorded between 12:00 AM and your custom closing time. Disabling it would cause data inconsistencies.\n\n'
                                      'Please ensure all entries between 12:00 AM and the closing time are removed or migrated before disabling this feature.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('OK'),
                                      ),
                                    ],
                                  ),
                                );
                                // Don't change the toggle state
                                return;
                              }

                              // No data found, allow disabling
                              setState(() {
                                _useCustomClosing = value;
                              });
                              await ClosingCycleService.setCustomClosingEnabled(value);
                            } catch (e) {
                              if (!mounted) return;
                              Navigator.pop(context); // Close loading dialog
                              // Show error dialog
                              await showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Error'),
                                  content: Text('An error occurred while checking data: $e'),
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

