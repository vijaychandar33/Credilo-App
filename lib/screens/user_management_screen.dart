import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../models/user.dart';
import '../models/branch.dart';
import '../services/auth_service.dart';
import '../utils/app_colors.dart';

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
          // Business owner: get all branches for their businesses
          Set<String> businessIds = {};
          final ownerAssignments = await Supabase.instance.client
              .from('branch_users')
              .select('business_id')
              .eq('user_id', currentUser.id)
              .eq('role', 'business_owner');
          
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
    final passwordController = TextEditingController();
    Branch? selectedBranch;
    UserRole? selectedRole;
    bool obscurePassword = true;
    bool makeBusinessOwner = false;

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
                    StatefulBuilder(
                      builder: (context, setDialogState) => TextField(
                        controller: passwordController,
                        decoration: InputDecoration(
                          labelText: 'Password *',
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscurePassword ? Icons.visibility : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setDialogState(() {
                                obscurePassword = !obscurePassword;
                              });
                            },
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        obscureText: obscurePassword,
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
                        // If making business owner, set role to owner and select first branch
                        if (makeBusinessOwner && _allBranches.isNotEmpty) {
                          selectedBranch = _allBranches.first;
                          selectedRole = UserRole.owner;
                        }
                      });
                    },
                  ),
                ],
                if (!makeBusinessOwner) ...[
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
                    ? UserRole.values.where((role) => role != UserRole.businessOwner)
                    : [UserRole.manager, UserRole.staff]
                  ).map((role) {
                    String roleName = role.toString().split('.').last;
                    // Capitalize first letter
                    roleName = roleName[0].toUpperCase() + roleName.substring(1);
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
                    passwordController.text.isEmpty ||
                    passwordController.text.length < 6 ||
                    (!makeBusinessOwner && (selectedBranch == null || selectedRole == null))) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please fill all required fields (password must be at least 6 characters)'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                  return;
                }

                await _addUser(
                  nameController.text,
                  emailController.text,
                  passwordController.text,
                  makeBusinessOwner ? _allBranches.first : selectedBranch!,
                  makeBusinessOwner ? UserRole.owner : selectedRole!,
                  makeBusinessOwner: makeBusinessOwner,
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
    String password,
    Branch branch,
    UserRole role, {
    bool makeBusinessOwner = false,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      String userId;
      bool isNewUser = false;

      // Step 1: Try to create user in Supabase Auth
      // Save current session to restore after user creation
      final currentOwnerSession = supabase.auth.currentSession;
      
      if (currentOwnerSession == null) {
        throw Exception('Owner session not found. Please sign in again.');
      }
      
      try {
        final authResponse = await supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'name': name,
          },
        );

        if (authResponse.user == null) {
          throw Exception('Failed to create user account');
        }

        userId = authResponse.user!.id;
        isNewUser = true;
        debugPrint('Created new auth user: $userId');
        
        // If signUp created a session (auto sign-in), restore owner session
        if (authResponse.session != null) {
          debugPrint('SignUp created session, restoring owner session...');
          try {
            // Sign out the new user session first
            await supabase.auth.signOut();
            // Restore owner session using the saved session object
            await supabase.auth.setSession(currentOwnerSession.accessToken);
            // Refresh the session to ensure it's valid
            await supabase.auth.refreshSession();
            debugPrint('Restored owner session after signUp');
            
            // Verify we're back to owner session
            final restoredSession = supabase.auth.currentSession;
            if (restoredSession?.user.id != currentOwnerSession.user.id) {
              throw Exception('Session restoration failed - wrong user');
            }
          } catch (e) {
            debugPrint('Failed to restore session after signUp: $e');
            // If session restoration fails, throw error to prevent proceeding with wrong session
            throw Exception('Failed to restore owner session. Please try again.');
          }
        }
      } catch (signUpError) {
        // Check if user already exists in auth
        final errorString = signUpError.toString();
        if (errorString.contains('user_already_exists') || 
            errorString.contains('User already registered') ||
            errorString.contains('already registered')) {
          
          debugPrint('User already exists in auth, checking database...');
          
          // Try to find existing user by email in database
          final existingUsersResponse = await supabase
              .from('users')
              .select()
              .eq('email', email)
              .maybeSingle();
          
          if (existingUsersResponse != null) {
            // User exists in both auth and database
            userId = existingUsersResponse['id'] as String;
            debugPrint('Found existing user in database: $userId');
          } else {
            // User exists in auth but not in database
            // This can happen if a user was deleted from database but auth account remains
            // Use the RPC function to get user ID by email and create the database record
            debugPrint('User exists in auth but not in database. Looking up user ID by email...');
            try {
              final userIdResponse = await supabase.rpc('insert_user_for_owner_by_email', params: {
                'p_email': email,
                'p_name': name,
                'p_phone': null,
              });
              
              if (userIdResponse != null) {
                userId = userIdResponse as String;
                debugPrint('Found and created user record for existing auth user: $userId');
                isNewUser = false; // User already exists in auth, just created DB record
              } else {
                throw Exception('Failed to retrieve user ID for existing email');
              }
            } catch (rpcError) {
              debugPrint('Error looking up user by email: $rpcError');
              // If the function fails, it means user doesn't exist in auth either
              // or there's a permission issue
              final errorString = rpcError.toString();
              if (errorString.contains('does not exist in authentication system')) {
                // This shouldn't happen since we know user exists in auth
                // But handle it gracefully
                throw Exception('Unable to recover user account. Please contact support.');
              } else {
                rethrow;
              }
            }
          }
        } else {
          rethrow;
        }
      }

      // Step 2: Create or update user record in database
      // Note: If user existed in auth but not DB, the RPC function already created the record
      // So we only need to create/update if it's a new user or if user exists in DB
      if (isNewUser) {
        // Use the database function to insert user (bypasses RLS issues)
        try {
          await supabase.rpc('insert_user_for_owner', params: {
            'p_user_id': userId,
            'p_name': name,
            'p_email': email,
            'p_phone': null,
          });
          debugPrint('Created user record in database using function');
        } catch (rpcError) {
          // Fallback to direct insert if function fails
          debugPrint('Function insert failed, trying direct insert: $rpcError');
          try {
        await supabase.from('users').insert({
          'id': userId,
          'name': name,
          'email': email,
          'phone': null,
        });
            debugPrint('Created user record in database using direct insert');
          } catch (e) {
            debugPrint('Direct insert also failed: $e');
            // Continue - maybe the record already exists
          }
        }
      } else {
        // Check if user record exists in database
        final existingUserCheck = await supabase
            .from('users')
            .select()
            .eq('id', userId)
            .maybeSingle();
        
        if (existingUserCheck != null) {
          // User exists in DB, try to update if needed
          try {
            await supabase.from('users').update({
          'name': name,
          'email': email,
            }).eq('id', userId);
        debugPrint('Updated existing user record');
          } catch (e) {
            debugPrint('Error updating user record: $e');
            // Continue anyway - the user record might already be correct
          }
        } else {
          // User doesn't exist in DB but exists in auth
          // This shouldn't happen if RPC function worked, but handle it
          debugPrint('User not found in database, creating record...');
          try {
            await supabase.rpc('insert_user_for_owner', params: {
              'p_user_id': userId,
              'p_name': name,
              'p_email': email,
              'p_phone': null,
            });
            debugPrint('Created user record in database using function');
          } catch (e) {
            debugPrint('Error creating user record: $e');
            // Continue - the RPC function should have created it
          }
        }
      }

      // Step 3: If making business owner, assign business_owner role to all branches of the business
      if (makeBusinessOwner) {
        try {
          // Get business ID from the branch
          final branchData = await supabase
              .from('branches')
              .select('business_id')
              .eq('id', branch.id)
              .single();
          
          final businessId = branchData['business_id'] as String;
          
          // Get all branches for this business
          final allBranches = await supabase
              .from('branches')
              .select('id')
              .eq('business_id', businessId);
          
          // Assign business_owner role to user for all branches of this business
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
              // Update existing record to business_owner role
              await supabase
                  .from('branch_users')
                  .update({
                    'role': 'business_owner',
                    'business_id': businessId,
                  })
                  .eq('id', existingBranchUser['id']);
            } else {
              // Insert new record with business_owner role
              await supabase.from('branch_users').insert({
                'user_id': userId,
                'branch_id': branchId,
                'business_id': businessId,
                'role': 'business_owner',
              });
            }
          }
          
          debugPrint('Made user $userId a business owner of business $businessId (assigned to ${(allBranches as List).length} branches)');
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
      
      String errorMessage = 'Error adding user';
      final errorString = e.toString();
      if (errorString.contains('user_already_exists')) {
        errorMessage = 'User with this email already exists. Please use a different email.';
      } else if (errorString.contains('PostgrestException')) {
        final match = RegExp(r'message: ([^,]+)').firstMatch(errorString);
        if (match != null) {
          errorMessage = 'Database error: ${match.group(1)}';
        }
      } else {
        errorMessage = errorString.split(':').last.trim();
      }
      
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
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
      
      String errorMessage = 'Error removing user from branch';
      final errorString = e.toString();
      
      if (errorString.contains('permission') || errorString.contains('policy')) {
        errorMessage = 'Permission denied. You may not have access to delete this user.';
      } else if (errorString.contains('Cannot delete the last business owner')) {
        errorMessage = 'Cannot delete the last business owner. A branch must have at least one business owner.';
      } else {
        errorMessage = 'Error: ${errorString.split(':').last.trim()}';
      }
      
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
                  ],
                  if (!makeBusinessOwner) ...[
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
                                      ? UserRole.values.where((role) => role != UserRole.businessOwner)
                                      : [UserRole.manager, UserRole.staff]
                                    ).map((role) {
                                      String roleName = role.toString().split('.').last;
                                      roleName = roleName[0].toUpperCase() + roleName.substring(1);
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
                if (makeBusinessOwner) {
                  // Get business ID from first branch
                  if (_allBranches.isNotEmpty) {
                    try {
                      final branchData = await Supabase.instance.client
                          .from('branches')
                          .select('business_id')
                          .eq('id', _allBranches.first.id)
                          .single();
                      
                      final businessId = branchData['business_id'] as String;
                      
                      // Get all branches for this business
                      final allBranches = await Supabase.instance.client
                          .from('branches')
                          .select('id')
                          .eq('business_id', businessId);
                      
                      // Assign business_owner role to user for all branches of this business
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
                          // Update existing record to business_owner role
                          await Supabase.instance.client
                              .from('branch_users')
                              .update({
                                'role': 'business_owner',
                                'business_id': businessId,
                              })
                              .eq('id', existingBranchUser['id']);
                        } else {
                          // Insert new record with business_owner role
                          await Supabase.instance.client.from('branch_users').insert({
                            'user_id': user.id,
                            'branch_id': branchId,
                            'business_id': businessId,
                            'role': 'business_owner',
                          });
                        }
                      }
                      
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('User is now a business owner'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                        Navigator.pop(context);
                        await _loadData();
                      }
                    } catch (e) {
                      debugPrint('Error making user business owner: $e');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: ${e.toString()}'),
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

      // Create a map of old assignments by branch_id
      final Map<String, Map<String, dynamic>> oldAssignmentsMap = {};
      for (var old in oldAssignments) {
        final branch = old['branch'] as Branch;
        oldAssignmentsMap[branch.id] = old;
      }

      // Process each branch
      for (var entry in newAssignments.entries) {
        final branchId = entry.key;
        final assignment = entry.value;
        final role = assignment['role'] as String;

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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error updating role: ${e.toString()}'),
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error removing ${branch.name}: ${e.toString()}'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
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
      body: _isLoading
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
                      final isUserOwner = branches.any((b) => 
                        (b['role'] as String).toLowerCase() == 'owner' && 
                        (b['role'] as String).toLowerCase() != 'business_owner'
                      );
                      
                      // Hide delete button for current user's own account
                      final currentUser = _authService.currentUser;
                      final isCurrentUser = currentUser != null && currentUser.id == user.id;
                      
                      // For owner-only users, hide edit/delete for business_owner and owner roles
                      final canEditUser = _isBusinessOwner || (!isUserBusinessOwner && !isUserOwner);
                      final canDeleteUser = _isBusinessOwner && isUserBusinessOwner && !isCurrentUser;

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
                              // Show user-level delete button for business owners (not self, only if current user is business owner)
                              if (canDeleteUser)
                                IconButton(
                                  icon: const Icon(Icons.delete, color: AppColors.error),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Delete Business Owner'),
                                        content: Text(
                                          'Remove ${user.name} from all branches? This will remove their business owner status.',
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
                            final isBranchOwner = branchRole == 'owner';
                            // Hide branch delete buttons for business owners (they have complete delete button)
                            // Also hide for owners and current user
                            final canDeleteBranch = !isCurrentUser && 
                              !isUserBusinessOwner && // Don't show branch delete for business owners
                              (_isBusinessOwner || (!isBranchBusinessOwner && !isBranchOwner));
                            
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
    );
  }
}

