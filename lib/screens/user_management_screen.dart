import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../models/user.dart';
import '../models/branch.dart';
import '../services/auth_service.dart';
import '../utils/app_colors.dart';
import '../utils/error_message_helper.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _users = [];
  List<Branch> _allBranches = [];
  bool _isLoading = true;
  bool _isBusinessOwner = false;
  bool _isOwnerOnly = false;

  @override
  void initState() {
    super.initState();
    _checkAccessAndLoad();
  }

  Future<void> _checkAccessAndLoad() async {
    // Check if user can manage users (business owner or owner)
    final canManage = _authService.canManageUsers();
    if (!canManage) {
      // User cannot manage users, show error and go back
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Access denied. Only business owners and owners can manage users.'),
            backgroundColor: AppColors.error,
          ),
        );
        Navigator.pop(context);
      }
      return;
    }
    
    // Check if user is business owner or owner only
    _isBusinessOwner = await _authService.isBusinessOwnerAsync();
    _isOwnerOnly = !_isBusinessOwner && _authService.isBranchOwner();
    
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        setState(() {
          _isLoading = false;
          _users = [];
          _allBranches = [];
        });
        return;
      }

      // Get branches based on user role
      List<dynamic> branchesResponse = [];
      
      try {
        if (_isBusinessOwner) {
          // Business owner (including read-only): get all branches for their businesses
          Set<String> businessIds = {};
          final ownerAssignments = await Supabase.instance.client
              .from('branch_users')
              .select('business_id')
              .eq('user_id', currentUser.id)
              .or('role.eq.business_owner,role.eq.business_owner_read_only');
          
          businessIds = (ownerAssignments as List)
              .map((record) => record['business_id'] as String?)
              .whereType<String>()
              .toSet();
          
          if (businessIds.isNotEmpty) {
            for (var businessId in businessIds) {
              final allBusinessBranches = await Supabase.instance.client
                  .from('branches')
                  .select('*, businesses!inner(id)')
                  .eq('business_id', businessId);
              branchesResponse.addAll(allBusinessBranches as List);
            }
          }
        } else if (_isOwnerOnly) {
          // Owner only: get only branches where they are owner
          final ownerBranchAssignments = await Supabase.instance.client
              .from('branch_users')
              .select('branch_id, branches(*), business_id')
              .eq('user_id', currentUser.id)
              .eq('role', 'owner');
          
          for (var assignment in ownerBranchAssignments as List) {
            final branchData = assignment['branches'];
            if (branchData != null) {
              branchesResponse.add(branchData);
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading branches: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _users = [];
            _allBranches = [];
          });
        }
        return;
      }

      // Remove duplicates based on branch ID
      final Map<String, dynamic> uniqueBranches = {};
      for (var branch in branchesResponse) {
        final branchId = branch['id'] as String;
        if (!uniqueBranches.containsKey(branchId)) {
          uniqueBranches[branchId] = branch;
        }
      }

      _allBranches = uniqueBranches.values
          .map((json) => Branch.fromJson(json))
          .toList();

      // Business owners should always have branches
      if (_allBranches.isEmpty) {
        debugPrint('Warning: Business owner has no branches');
      }

      // Get all users with their branch assignments
      if (_allBranches.isEmpty) {
        setState(() {
        _users = [];
          _isLoading = false;
        });
        return;
      }
      
      final branchIds = _allBranches.map((b) => b.id).toList();
      
      // Get users for all branches
      // First, get all branch_users, then fetch user details separately to avoid RLS issues with joins
      final List<dynamic> allBranchUsers = [];
      for (var branchId in branchIds) {
        try {
          final response = await Supabase.instance.client
              .from('branch_users')
              .select('*, branches(*)')
              .eq('branch_id', branchId);
          debugPrint('Loaded ${(response as List).length} branch_users for branch $branchId');
          allBranchUsers.addAll(response as List);
        } catch (e) {
          debugPrint('Error loading branch_users for branch $branchId: $e');
        }
      }
      
      debugPrint('Total branch_users loaded: ${allBranchUsers.length}');
      
      // Now fetch user details separately for each unique user_id
      final Set<String> userIds = {};
      for (var bu in allBranchUsers) {
        final userId = bu['user_id'] as String?;
        if (userId != null) {
          userIds.add(userId);
        }
      }
      
      debugPrint('Found ${userIds.length} unique user IDs');
      
      // Fetch all users at once
      final Map<String, dynamic> usersMap = {};
      if (userIds.isNotEmpty) {
        try {
          final usersList = userIds.toList();
          // Query users - build filter with OR conditions
          var query = Supabase.instance.client.from('users').select();
          
          // Query users individually to avoid RLS issues with batch queries
          if (usersList.length == 1) {
            query = query.eq('id', usersList[0]);
          } else {
            // For multiple IDs, query individually
            for (var userId in usersList) {
              try {
                final userResponse = await Supabase.instance.client
                    .from('users')
                    .select()
                    .eq('id', userId)
                    .maybeSingle();
                if (userResponse != null) {
                  usersMap[userId] = userResponse;
                }
              } catch (e) {
                debugPrint('Error loading user $userId: $e');
                // Log more details about the error
                if (e.toString().contains('row-level security') || e.toString().contains('42501')) {
                  debugPrint('  RLS policy is blocking access to user $userId');
                  debugPrint('  Current user: ${currentUser.id}');
                }
              }
            }
            debugPrint('Loaded ${usersMap.length} user records');
          }
          
          // If single user, execute the query
          if (usersList.length == 1) {
            final userResponse = await query.maybeSingle();
            if (userResponse != null) {
              usersMap[usersList[0]] = userResponse;
            }
            debugPrint('Loaded ${usersMap.length} user records');
          }
        } catch (e) {
          debugPrint('Error loading users: $e');
        }
      }

      // Group users by user_id
      final Map<String, Map<String, dynamic>> userMap = {};
      
      for (var item in allBranchUsers) {
        try {
          final userId = item['user_id'] as String?;
          if (userId == null) {
            debugPrint('Warning: branch_user has null user_id');
            continue;
          }
          
          final userData = usersMap[userId];
          if (userData == null) {
            debugPrint('Warning: user $userId not found in users map (RLS might be blocking access)');
            debugPrint('  Current user: ${currentUser.id}');
            debugPrint('  Branch IDs user has access to: ${branchIds.join(", ")}');
            debugPrint('  User IDs found in branch_users: ${userIds.join(", ")}');
            debugPrint('  Users successfully loaded: ${usersMap.keys.join(", ")}');
            continue;
          }
          
          if (!userMap.containsKey(userId)) {
            userMap[userId] = {
              'user': User.fromJson(userData),
              'branches': <Map<String, dynamic>>[],
            };
          }
          
          final branchData = item['branches'];
          if (branchData != null) {
          userMap[userId]!['branches'].add({
              'branch': Branch.fromJson(branchData),
            'role': item['role'],
            'branch_user_id': item['id'],
          });
          }
        } catch (e) {
          debugPrint('Error processing branch_user item: $e');
        }
      }

      // Filter users to only show branches the current user can manage
      final List<Map<String, dynamic>> filteredUsers = [];
      final managedBranchIds = _allBranches.map((b) => b.id).toSet();
      
      for (var userEntry in userMap.values) {
        final userBranches = userEntry['branches'] as List<Map<String, dynamic>>;
        // Filter branches to only show those the current user can manage
        final filteredBranches = userBranches.where((branchData) {
          final branch = branchData['branch'] as Branch;
          return managedBranchIds.contains(branch.id);
        }).toList();
        
        // Only include user if they have at least one branch in managed branches
        if (filteredBranches.isNotEmpty) {
          filteredUsers.add({
            'user': userEntry['user'],
            'branches': filteredBranches,
          });
        }
      }
      
      _users = filteredUsers;
      debugPrint('Final users count: ${_users.length}');
    } catch (e) {
      debugPrint('Error loading users: $e');
      // Ensure we still set loading to false and show empty list on error
      setState(() {
        _users = _users; // Keep existing users if any
        _isLoading = false;
      });
    } finally {
      if (mounted) {
      setState(() {
        _isLoading = false;
      });
      }
    }
  }

  void _showAddUserDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    Branch? selectedBranch;
    UserRole? selectedRole;
    bool makeBusinessOwner = false;
    bool makeBusinessOwnerReadOnly = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add User'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email *',
                        hintText: 'user@example.com',
                        prefixIcon: Icon(Icons.email),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    Card(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'A verification code will be sent to the user\'s email at the time of login.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                if (_isBusinessOwner) ...[
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: const Text('Make Business Owner'),
                    subtitle: const Text('User will have full access to all branches and can manage users'),
                    value: makeBusinessOwner,
                    onChanged: (value) {
                      setDialogState(() {
                        makeBusinessOwner = value ?? false;
                        // If making business owner, disable read-only and set role to owner
                        if (makeBusinessOwner) {
                          makeBusinessOwnerReadOnly = false;
                          if (_allBranches.isNotEmpty) {
                          selectedBranch = _allBranches.first;
                          selectedRole = UserRole.owner;
                          }
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    title: const Text('Make Business Owner (Read-Only)'),
                    subtitle: const Text('User will have read-only access to all branches but cannot manage users'),
                    value: makeBusinessOwnerReadOnly,
                    onChanged: (value) {
                      setDialogState(() {
                        makeBusinessOwnerReadOnly = value ?? false;
                        // If making read-only business owner, disable full business owner
                        if (makeBusinessOwnerReadOnly) {
                          makeBusinessOwner = false;
                          if (_allBranches.isNotEmpty) {
                            selectedBranch = _allBranches.first;
                            selectedRole = UserRole.owner;
                          }
                        }
                      });
                    },
                  ),
                ],
                if (!makeBusinessOwner && !makeBusinessOwnerReadOnly) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<Branch>(
                  initialValue: selectedBranch,
                  decoration: const InputDecoration(
                    labelText: 'Branch *',
                    border: OutlineInputBorder(),
                  ),
                  items: _allBranches.map((branch) {
                    return DropdownMenuItem(
                      value: branch,
                      child: Text(branch.name),
                    );
                  }).toList(),
                  onChanged: (branch) {
                    setDialogState(() {
                      selectedBranch = branch;
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Role *',
                    border: OutlineInputBorder(),
                  ),
                  items: (_isBusinessOwner 
                    ? [UserRole.owner, UserRole.manager, UserRole.staff]
                    : [UserRole.manager, UserRole.staff]
                  ).map((role) {
                    String roleName = _formatRoleName(role);
                    return DropdownMenuItem(
                      value: role,
                      child: Text(roleName),
                    );
                  }).toList(),
                  onChanged: (role) {
                    setDialogState(() {
                      selectedRole = role;
                    });
                  },
                ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty ||
                    emailController.text.isEmpty ||
                    !emailController.text.contains('@') ||
                    (!makeBusinessOwner && !makeBusinessOwnerReadOnly && (selectedBranch == null || selectedRole == null))) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please fill all required fields'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                  return;
                }

                await _addUser(
                  nameController.text,
                  emailController.text,
                  (makeBusinessOwner || makeBusinessOwnerReadOnly) ? _allBranches.first : selectedBranch!,
                  (makeBusinessOwner || makeBusinessOwnerReadOnly) ? UserRole.owner : selectedRole!,
                  makeBusinessOwner: makeBusinessOwner,
                  makeBusinessOwnerReadOnly: makeBusinessOwnerReadOnly,
                );
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addUser(
    String name,
    String email,
    Branch branch,
    UserRole role, {
    bool makeBusinessOwner = false,
    bool makeBusinessOwnerReadOnly = false,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      String userId;

      // Step 1: Check if user already exists in database
      final existingUserResponse = await supabase
              .from('users')
              .select()
              .eq('email', email)
              .maybeSingle();
          
      if (existingUserResponse != null) {
        // User already exists in database
        userId = existingUserResponse['id'] as String;
        debugPrint('User already exists in database: $userId');
          } else {
        // Step 2: User doesn't exist - store pending user info
        // Get current user ID for created_by field
        final currentUser = supabase.auth.currentUser;
        if (currentUser == null) {
          throw Exception('Admin must be logged in to add users');
        }

        // Get business ID from branch
        final branchData = await supabase
            .from('branches')
            .select('business_id')
            .eq('id', branch.id)
            .single();
        
        final businessId = branchData['business_id'] as String;
        final roleToStore = makeBusinessOwner 
            ? 'business_owner' 
            : (makeBusinessOwnerReadOnly 
                ? 'business_owner_read_only' 
                : role.toString().split('.').last);

        // Store pending user info
        await supabase.from('pending_users').insert({
          'email': email,
          'name': name,
          'phone': null,
          'role': roleToStore,
          'branch_id': branch.id,
          'business_id': businessId,
          'created_by': currentUser.id,
        });

        debugPrint('Stored pending user info for: $email');

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User added successfully. They will receive an OTP when they first log in with their email.'),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 5),
          ),
        );

        // Reload data after a short delay
        await Future.delayed(const Duration(milliseconds: 300));
        await _loadData();
        return; // Exit early - user will be created when they log in
      }

      // Step 3: If making business owner (full or read-only), assign role to all branches of the business
      if (makeBusinessOwner || makeBusinessOwnerReadOnly) {
        try {
          // Get business ID from the branch
          final branchData = await supabase
              .from('branches')
              .select('business_id')
              .eq('id', branch.id)
              .single();
          
          final businessId = branchData['business_id'] as String;
          final roleToAssign = makeBusinessOwner ? 'business_owner' : 'business_owner_read_only';
          
          // Get all branches for this business
          final allBranches = await supabase
              .from('branches')
              .select('id')
              .eq('business_id', businessId);
          
          // Assign role to user for all branches of this business
          for (var branchItem in allBranches as List) {
            final branchId = branchItem['id'] as String;
            
            // Check if user is already assigned to this branch
            final existingBranchUser = await supabase
                .from('branch_users')
                .select()
                .eq('user_id', userId)
                .eq('branch_id', branchId)
                .maybeSingle();
            
            if (existingBranchUser != null) {
              // Update existing record to the selected role
              await supabase
                  .from('branch_users')
                  .update({
                    'role': roleToAssign,
                    'business_id': businessId,
                  })
                  .eq('id', existingBranchUser['id']);
            } else {
              // Insert new record with the selected role
              await supabase.from('branch_users').insert({
                'user_id': userId,
                'branch_id': branchId,
                'business_id': businessId,
                'role': roleToAssign,
              });
            }
          }
          
          final roleName = makeBusinessOwner ? 'business owner' : 'business owner (read-only)';
          debugPrint('Made user $userId a $roleName of business $businessId (assigned to ${(allBranches as List).length} branches)');
        } catch (e) {
          debugPrint('Error making user business owner: $e');
          // Continue - user was still created and assigned to branch
        }
      } else {
        // Step 4: Check if user is already assigned to this branch
        // Get business_id from branch
        final branchData = await supabase
            .from('branches')
            .select('business_id')
            .eq('id', branch.id)
            .single();
        
        final businessId = branchData['business_id'] as String;
        
        final existingBranchUser = await supabase
            .from('branch_users')
            .select()
            .eq('user_id', userId)
            .eq('branch_id', branch.id)
            .maybeSingle();

        if (existingBranchUser != null) {
          // User already assigned to this branch, just update role if different
          if (existingBranchUser['role'] != role.toString().split('.').last) {
            await supabase
                .from('branch_users')
                .update({
                  'role': role.toString().split('.').last,
                  'business_id': businessId,
                })
                .eq('id', existingBranchUser['id']);
            debugPrint('Updated user role in branch');
          } else {
            debugPrint('User already assigned to branch with same role');
          }
        } else {
          // Assign user to branch
          await supabase.from('branch_users').insert({
            'user_id': userId,
            'branch_id': branch.id,
            'business_id': businessId,
            'role': role.toString().split('.').last,
          });
          debugPrint('Assigned user to branch');
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User added successfully'),
          backgroundColor: AppColors.success,
        ),
      );

      // Reload data after a short delay to ensure database is updated
      await Future.delayed(const Duration(milliseconds: 300));
      await _loadData();
    } catch (e) {
      debugPrint('Error adding user: $e');
      if (!mounted) return;
      
      final errorMessage = ErrorMessageHelper.getUserFriendlyError(e);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
                        backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // Check if a user is a business owner (has business_owner role in any branch)
  bool _isUserBusinessOwner(List<Map<String, dynamic>> userBranches) {
    // Check if user has business_owner role in any branch
    return userBranches.any((branchData) {
      final role = (branchData['role'] as String).toLowerCase();
      return role == 'business_owner';
    });
  }

  // Check if a user is a business owner read-only (has business_owner_read_only role in any branch)
  bool _isUserBusinessOwnerReadOnly(List<Map<String, dynamic>> userBranches) {
    // Check if user has business_owner_read_only role in any branch
    return userBranches.any((branchData) {
      final role = (branchData['role'] as String).toLowerCase();
      return role == 'business_owner_read_only';
    });
  }

  String _formatRoleName(UserRole role) {
    String roleName = role.toString().split('.').last;
    // Convert camelCase to Title Case with spaces
    roleName = roleName.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)}',
    ).trim();
    // Capitalize first letter
    if (roleName.isNotEmpty) {
      roleName = roleName[0].toUpperCase() + roleName.substring(1);
    }
    // Handle special case for businessOwnerReadOnly
    if (role == UserRole.businessOwnerReadOnly) {
      return 'Business Owner (Read-Only)';
    }
    return roleName;
  }

  // Remove user from all branches
  Future<void> _removeUserFromAllBranches(User user, List<Map<String, dynamic>> branches) async {
    try {
      final supabase = Supabase.instance.client;
      final currentUser = _authService.currentUser;

      // Prevent self-deletion
      if (currentUser != null && currentUser.id == user.id) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You cannot remove yourself.'),
            backgroundColor: AppColors.error,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Check if user is a business owner (owns all branches)
      final isBusinessOwner = _isUserBusinessOwner(branches);
      
      if (isBusinessOwner) {
        // For business owners, check if there are other business owners
        // We need to ensure at least one business owner remains
        int otherBusinessOwners = 0;
        for (var otherUserData in _users) {
          final otherUser = otherUserData['user'] as User;
          if (otherUser.id != user.id) {
            final otherBranches = otherUserData['branches'] as List<Map<String, dynamic>>;
            if (_isUserBusinessOwner(otherBranches)) {
              otherBusinessOwners++;
            }
          }
        }
        
        if (otherBusinessOwners == 0) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot delete the last business owner. At least one business owner must remain.'),
              backgroundColor: AppColors.error,
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }
      }

      // Remove user from all branches
      for (var branchData in branches) {
        final branch = branchData['branch'] as Branch;
        final role = branchData['role'] as String;
        final branchUserId = branchData['branch_user_id'] as String;

        // Only guard against removing the last business owner
        if (role.toLowerCase() == 'business_owner') {
          final ownersResponse = await supabase
              .from('branch_users')
              .select()
              .eq('branch_id', branch.id)
              .eq('role', 'business_owner');

          final ownersCount = (ownersResponse as List).length;

          if (ownersCount <= 1) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Cannot remove ${branch.name}. A branch must have at least one business owner.'),
                backgroundColor: AppColors.error,
                duration: const Duration(seconds: 3),
              ),
            );
            continue;
          }
        }

        await supabase
          .from('branch_users')
          .delete()
          .eq('id', branchUserId);
      }


      // Delete user from users table (this will prevent them from logging in)
      // Check if user has any other branch assignments first
      final remainingBranchUsers = await supabase
          .from('branch_users')
          .select()
          .eq('user_id', user.id)
          .limit(1);
      
      // Only delete from users table if they have no remaining branch assignments
      // This ensures we don't delete users who might have access elsewhere
      if ((remainingBranchUsers as List).isEmpty) {
        try {
          await supabase
              .from('users')
              .delete()
              .eq('id', user.id);
          debugPrint('Deleted user from users table');
        } catch (e) {
          debugPrint('Error deleting user from users table: $e');
          // User might be referenced elsewhere, but we've removed all access
        }
      } else {
        debugPrint('User still has branch assignments, keeping user record');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User removed from all branches and business owners'),
          backgroundColor: AppColors.success,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 300));
      await _loadData();
    } catch (e) {
      debugPrint('Error removing user from all branches: $e');
      if (!mounted) return;
      final errorMessage = ErrorMessageHelper.getUserFriendlyError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
                        backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _removeUserFromBranch(
    String branchUserId,
    String branchId,
    String role,
    String userId,
  ) async {
    try {
      final supabase = Supabase.instance.client;
      final currentUser = _authService.currentUser;

      // Prevent self-deletion
      if (currentUser != null && currentUser.id == userId) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You cannot remove yourself from a branch.'),
            backgroundColor: AppColors.error,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Only guard against removing the last business owner
      if (role.toLowerCase() == 'business_owner') {
        final ownersResponse = await supabase
            .from('branch_users')
            .select()
            .eq('branch_id', branchId)
            .eq('role', 'business_owner');

        final ownersCount = (ownersResponse as List).length;

        if (ownersCount <= 1) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot delete the last business owner. A branch must have at least one business owner.'),
              backgroundColor: AppColors.error,
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }
      }

      // Delete the user from branch
      final response = await supabase
          .from('branch_users')
          .delete()
          .eq('id', branchUserId)
          .select();

      debugPrint('Delete response: $response');

      if (!mounted) return;
      
      // Check if deletion was successful
      if (response.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete. You may not have permission or the record does not exist.'),
            backgroundColor: AppColors.error,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User removed from branch'),
          backgroundColor: AppColors.success,
        ),
      );

      // Reload data after a short delay
      await Future.delayed(const Duration(milliseconds: 300));
      await _loadData();
    } catch (e) {
      debugPrint('Error removing user from branch: $e');
      if (!mounted) return;
      
      final errorMessage = ErrorMessageHelper.getUserFriendlyError(e);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
                        backgroundColor: AppColors.error,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _editUserBranches(
    User user,
    List<Map<String, dynamic>> currentBranches,
  ) async {
    // Check if user is a business owner (has business_owner role in any branch)
    bool isBusinessOwner = _isUserBusinessOwner(currentBranches);
    
    // Map of branch_id -> {branch, role, branch_user_id}
    final Map<String, Map<String, dynamic>> branchAssignments = {};
    for (var branchData in currentBranches) {
      final branch = branchData['branch'] as Branch;
      branchAssignments[branch.id] = {
        'branch': branch,
        'role': branchData['role'] as String,
        'branch_user_id': branchData['branch_user_id'] as String,
      };
    }

    bool makeBusinessOwner = isBusinessOwner;
    // Check if user is business owner read-only
    bool isBusinessOwnerReadOnly = currentBranches.any((branchData) {
      final role = (branchData['role'] as String).toLowerCase();
      return role == 'business_owner_read_only';
    });
    bool makeBusinessOwnerReadOnly = isBusinessOwnerReadOnly;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Branch and Role'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    enabled: false,
                    decoration: InputDecoration(
                      labelText: 'User',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.person),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    ),
                    controller: TextEditingController(text: '${user.name} (${user.email})'),
                  ),
                  if (_isBusinessOwner) ...[
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      title: const Text('Make Business Owner'),
                      subtitle: const Text('User will have full access to all branches and can manage users'),
                      value: makeBusinessOwner,
                      onChanged: (value) {
                        setDialogState(() {
                          makeBusinessOwner = value ?? false;
                          if (makeBusinessOwner) {
                            makeBusinessOwnerReadOnly = false;
                            // Assign business_owner role to all branches
                            for (var branch in _allBranches) {
                              branchAssignments[branch.id] = {
                                'branch': branch,
                                'role': 'business_owner',
                                'branch_user_id': branchAssignments[branch.id]?['branch_user_id'],
                              };
                            }
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      title: const Text('Make Business Owner (Read-Only)'),
                      subtitle: const Text('User will have read-only access to all branches but cannot manage users'),
                      value: makeBusinessOwnerReadOnly,
                      onChanged: (value) {
                        setDialogState(() {
                          makeBusinessOwnerReadOnly = value ?? false;
                          if (makeBusinessOwnerReadOnly) {
                            makeBusinessOwner = false;
                            // Assign business_owner_read_only role to all branches
                            for (var branch in _allBranches) {
                              branchAssignments[branch.id] = {
                                'branch': branch,
                                'role': 'business_owner_read_only',
                                'branch_user_id': branchAssignments[branch.id]?['branch_user_id'],
                              };
                            }
                          }
                        });
                      },
                    ),
                  ],
                  if (!makeBusinessOwner && !makeBusinessOwnerReadOnly) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Branch Assignments:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    ..._allBranches.map((branch) {
                      final existingAssignment = branchAssignments[branch.id];
                      final isAssigned = existingAssignment != null;
                      UserRole currentRole = isAssigned
                          ? UserRole.values.firstWhere(
                              (r) => r.toString().split('.').last == (existingAssignment['role'] as String).toLowerCase(),
                              orElse: () => UserRole.staff,
                            )
                          : UserRole.staff;

                      return StatefulBuilder(
                        builder: (context, setItemState) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Checkbox(
                                      value: isAssigned,
                                      onChanged: (value) {
                                        setItemState(() {
                                          if (value == true) {
                                            // Add assignment - default to staff for owners, owner for business owners
                                            branchAssignments[branch.id] = {
                                              'branch': branch,
                                              'role': _isBusinessOwner 
                                                ? UserRole.owner.toString().split('.').last
                                                : UserRole.staff.toString().split('.').last,
                                              'branch_user_id': null, // New assignment
                                            };
                                          } else {
                                            // Remove assignment
                                            branchAssignments.remove(branch.id);
                                          }
                                        });
                                        setDialogState(() {});
                                      },
                                    ),
                                    Expanded(
                                      child: Text(
                                        branch.name,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                                if (isAssigned) ...[
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<UserRole>(
                                    initialValue: currentRole,
                                    decoration: const InputDecoration(
                                      labelText: 'Role',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                    isExpanded: true,
                                    items: (_isBusinessOwner 
                                      ? [
                                          UserRole.owner,
                                          UserRole.businessOwnerReadOnly, // Show right after Owner
                                          UserRole.manager,
                                          UserRole.staff
                                        ].where((role) => role != UserRole.businessOwner)
                                      : [UserRole.manager, UserRole.staff]
                                    ).map((role) {
                                      String roleName = _formatRoleName(role);
                                      return DropdownMenuItem(
                                        value: role,
                                        child: Text(roleName),
                                      );
                                    }).toList(),
                                    onChanged: (role) {
                                      setItemState(() {
                                        if (role != null) {
                                          branchAssignments[branch.id]!['role'] = role.toString().split('.').last;
                                          currentRole = role;
                                        }
                                      });
                                      setDialogState(() {});
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (makeBusinessOwner || makeBusinessOwnerReadOnly) {
                  // Get business ID from first branch
                  if (_allBranches.isNotEmpty) {
                    try {
                      final branchData = await Supabase.instance.client
                          .from('branches')
                          .select('business_id')
                          .eq('id', _allBranches.first.id)
                          .single();
                      
                      final businessId = branchData['business_id'] as String;
                      final roleToAssign = makeBusinessOwner ? 'business_owner' : 'business_owner_read_only';
                      
                      // Get all branches for this business
                      final allBranches = await Supabase.instance.client
                          .from('branches')
                          .select('id')
                          .eq('business_id', businessId);
                      
                      // Assign role to user for all branches of this business
                      for (var branchItem in allBranches as List) {
                        final branchId = branchItem['id'] as String;
                        
                        // Check if user is already assigned to this branch
                        final existingBranchUser = await Supabase.instance.client
                            .from('branch_users')
                            .select()
                            .eq('user_id', user.id)
                            .eq('branch_id', branchId)
                            .maybeSingle();
                        
                        if (existingBranchUser != null) {
                          // Update existing record to the selected role
                          await Supabase.instance.client
                              .from('branch_users')
                              .update({
                                'role': roleToAssign,
                                'business_id': businessId,
                              })
                              .eq('id', existingBranchUser['id']);
                        } else {
                          // Insert new record with the selected role
                          await Supabase.instance.client.from('branch_users').insert({
                            'user_id': user.id,
                            'branch_id': branchId,
                            'business_id': businessId,
                            'role': roleToAssign,
                          });
                        }
                      }
                      
                      if (context.mounted) {
                        final roleName = makeBusinessOwner ? 'business owner' : 'business owner (read-only)';
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('User is now a $roleName'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                        Navigator.pop(context);
                        await _loadData();
                      }
                    } catch (e) {
                      debugPrint('Error making user business owner: $e');
                      if (context.mounted) {
                        final errorMessage = ErrorMessageHelper.getUserFriendlyError(e);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(errorMessage),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    }
                  }
                } else {
                  await _updateUserBranches(user.id, branchAssignments, currentBranches);
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateUserBranches(
    String userId,
    Map<String, Map<String, dynamic>> newAssignments,
    List<Map<String, dynamic>> oldAssignments,
  ) async {
    try {
      final supabase = Supabase.instance.client;

      // Check if any assignment is business_owner_read_only - if so, assign to all branches
      bool hasReadOnlyBusinessOwner = false;
      String? businessIdForReadOnly;
      
      for (var entry in newAssignments.entries) {
        final assignment = entry.value;
        final role = assignment['role'] as String;
        if (role == 'business_owner_read_only') {
          hasReadOnlyBusinessOwner = true;
          final branchId = entry.key;
          final branchData = await supabase
              .from('branches')
              .select('business_id')
              .eq('id', branchId)
              .single();
          businessIdForReadOnly = branchData['business_id'] as String;
          break; // We only need the business ID once
        }
      }
      
      // If business_owner_read_only is assigned, assign to all branches of the business
      if (hasReadOnlyBusinessOwner && businessIdForReadOnly != null) {
        // Get all branches for this business
        final allBranches = await supabase
            .from('branches')
            .select('id')
            .eq('business_id', businessIdForReadOnly);
        
        // Assign business_owner_read_only role to user for all branches
        for (var branchItem in allBranches as List) {
          final branchId = branchItem['id'] as String;
          
          // Check if user is already assigned to this branch
          final existingBranchUser = await supabase
              .from('branch_users')
              .select()
              .eq('user_id', userId)
              .eq('branch_id', branchId)
              .maybeSingle();
          
          if (existingBranchUser != null) {
            // Update existing record to business_owner_read_only role
            await supabase
                .from('branch_users')
                .update({
                  'role': 'business_owner_read_only',
                  'business_id': businessIdForReadOnly,
                })
                .eq('id', existingBranchUser['id']);
          } else {
            // Insert new record with business_owner_read_only role
            await supabase.from('branch_users').insert({
              'user_id': userId,
              'branch_id': branchId,
              'business_id': businessIdForReadOnly,
              'role': 'business_owner_read_only',
            });
          }
        }
        
        debugPrint('Updated user $userId to business owner (read-only) for all branches in business $businessIdForReadOnly');
        return; // Exit early since we've handled all branches
      }

      // Create a map of old assignments by branch_id
      final Map<String, Map<String, dynamic>> oldAssignmentsMap = {};
      for (var old in oldAssignments) {
        final branch = old['branch'] as Branch;
        oldAssignmentsMap[branch.id] = old;
      }

      // Process each branch (for non-business_owner_read_only roles)
      for (var entry in newAssignments.entries) {
        final branchId = entry.key;
        final assignment = entry.value;
        final role = assignment['role'] as String;
        
        // Skip if this is business_owner_read_only (already handled above)
        if (role == 'business_owner_read_only') continue;

        // Get business_id from branch
        final branchData = await supabase
            .from('branches')
            .select('business_id')
            .eq('id', branchId)
            .single();
        
        final businessId = branchData['business_id'] as String;

        final oldAssignment = oldAssignmentsMap[branchId];

        if (oldAssignment == null) {
          // New assignment - check if user already exists in this branch
          final existing = await supabase
              .from('branch_users')
              .select()
              .eq('user_id', userId)
              .eq('branch_id', branchId)
              .maybeSingle();

          if (existing == null) {
            // Create new assignment
            await supabase.from('branch_users').insert({
              'user_id': userId,
              'branch_id': branchId,
              'business_id': businessId,
              'role': role,
            });
          } else {
            // Update existing assignment
            await supabase
                .from('branch_users')
                .update({
                  'role': role,
                  'business_id': businessId,
                })
                .eq('id', existing['id']);
          }
        } else {
          // Existing assignment - check if role changed
          final oldRole = oldAssignment['role'] as String;
          if (oldRole.toLowerCase() != role.toLowerCase()) {
            try {
              await supabase
                  .from('branch_users')
                  .update({
                    'role': role,
                    'business_id': businessId,
                  })
                  .eq('id', oldAssignment['branch_user_id'] as String);
            } catch (e) {
              if (!mounted) rethrow;
              final errorMessage = ErrorMessageHelper.getUserFriendlyError(e);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(errorMessage),
                  backgroundColor: AppColors.error,
                  duration: const Duration(seconds: 3),
                ),
              );
              return;
            }
          }
        }
      }

      // Remove assignments that are no longer in the new list
      for (var old in oldAssignments) {
        final branch = old['branch'] as Branch;
        if (!newAssignments.containsKey(branch.id)) {
          final branchUserId = old['branch_user_id'] as String;

          try {
            await supabase
                .from('branch_users')
                .delete()
                .eq('id', branchUserId);
          } catch (e) {
            if (!mounted) rethrow;
            final errorMessage = ErrorMessageHelper.getUserFriendlyError(e);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Unable to remove ${branch.name}. $errorMessage'),
                backgroundColor: AppColors.error,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User branches updated successfully'),
          backgroundColor: AppColors.success,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 300));
      await _loadData();
    } catch (e) {
      debugPrint('Error updating user branches: $e');
      if (!mounted) return;
      final errorMessage = ErrorMessageHelper.getUserFriendlyError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
                        backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: _showAddUserDialog,
            tooltip: 'Add User to Branch',
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
              children: [
                        Icon(
                          Icons.people_outline,
                          size: 64,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No users found',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap the + icon to add a user',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      final userData = _users[index];
                      final user = userData['user'] as User;
                      final branches = userData['branches'] as List<Map<String, dynamic>>;
                      
                      // Check if user is a business owner or owner
                      final isUserBusinessOwner = _isUserBusinessOwner(branches);
                      final isUserBusinessOwnerReadOnly = _isUserBusinessOwnerReadOnly(branches);
                      final isUserOwner = branches.any((b) => 
                        (b['role'] as String).toLowerCase() == 'owner' && 
                        (b['role'] as String).toLowerCase() != 'business_owner'
                      );
                      
                      // Hide delete button for current user's own account
                      final currentUser = _authService.currentUser;
                      final isCurrentUser = currentUser != null && currentUser.id == user.id;
                      
                      // For owner-only users, hide edit/delete for business_owner and owner roles
                      final canEditUser = _isBusinessOwner || (!isUserBusinessOwner && !isUserOwner);
                      // Show delete button for business owners (full) and business owner read-only (not self, only if current user is business owner)
                      final canDeleteUser = _isBusinessOwner && (isUserBusinessOwner || isUserBusinessOwnerReadOnly) && !isCurrentUser;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            child: Text(user.name[0].toUpperCase()),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(user.name),
                                    Text(
                                      user.email ?? 'No email',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              if (!isCurrentUser && canEditUser)
                                IconButton(
                                  icon: const Icon(Icons.edit, color: AppColors.primary),
                                  onPressed: () {
                                    _editUserBranches(user, branches);
                                  },
                                  tooltip: 'Edit Branch and Role',
                                ),
                              // Show user-level delete button for business owners (full and read-only) (not self, only if current user is business owner)
                              if (canDeleteUser)
                                IconButton(
                                  icon: const Icon(Icons.delete, color: AppColors.error),
                                  onPressed: () {
                                    final roleType = isUserBusinessOwnerReadOnly 
                                        ? 'Business Owner (Read-Only)' 
                                        : 'Business Owner';
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: Text('Delete $roleType'),
                                        content: Text(
                                          'Remove ${user.name} from all branches? This will remove their $roleType status.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () {
                                              Navigator.pop(context);
                                              _removeUserFromAllBranches(user, branches);
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.error,
                                            ),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  tooltip: 'Delete User',
                                ),
                            ],
                          ),
                          children: branches.map((branchData) {
                            final branch = branchData['branch'] as Branch;
                            final role = branchData['role'] as String;
                            final branchUserId = branchData['branch_user_id'] as String;

                            final branchRole = role.toLowerCase();
                            final isBranchBusinessOwner = branchRole == 'business_owner';
                            final isBranchBusinessOwnerReadOnly = branchRole == 'business_owner_read_only';
                            final isBranchOwner = branchRole == 'owner';
                            // Hide branch delete buttons for business owners (full and read-only) (they have complete delete button)
                            // Also hide for owners and current user
                            final canDeleteBranch = !isCurrentUser && 
                              !isUserBusinessOwner && // Don't show branch delete for business owners (full)
                              !isUserBusinessOwnerReadOnly && // Don't show branch delete for business owners (read-only)
                              (_isBusinessOwner || (!isBranchBusinessOwner && !isBranchBusinessOwnerReadOnly && !isBranchOwner));
                            
                            return ListTile(
                              title: Text(branch.name),
                              subtitle: Text('${branch.location} • ${role.toUpperCase()}'),
                              // Hide branch delete buttons for business owners, owners, and current user
                              trailing: canDeleteBranch
                                  ? IconButton(
                                      icon: const Icon(Icons.delete, color: AppColors.error),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('Remove User'),
                                            content: Text(
                                              'Remove ${user.name} from ${branch.name}?',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context),
                                                child: const Text('Cancel'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () {
                                                  Navigator.pop(context);
                                                  _removeUserFromBranch(
                                                    branchUserId,
                                                    branch.id,
                                                    role,
                                                    user.id,
                                                  );
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppColors.error,
                                                ),
                                                child: const Text('Remove'),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                      tooltip: 'Delete',
                                    )
                                  : null,
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
            ),
    );
  }
}

