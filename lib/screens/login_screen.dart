import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../services/auth_service.dart';
import '../models/user.dart' as models;
import '../models/business.dart';
import '../models/branch.dart';
import 'dashboard_home_screen.dart';
import '../utils/app_colors.dart';
import '../utils/error_message_helper.dart';
import '../widgets/otp_verification_widget.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _branchNameController = TextEditingController();
  final _branchLocationController = TextEditingController();
  
  bool _isLoading = false;
  bool _otpSent = false;
  bool _otpVerified = false;
  bool _showRegistrationForm = false;

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _businessNameController.dispose();
    _branchNameController.dispose();
    _branchLocationController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final email = _emailController.text.trim();
      debugPrint('Auth: Sending OTP to email: $email');

      // Send OTP to email
      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
      );

      setState(() {
        _otpSent = true;
        _isLoading = false;
      });
        
        if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification code sent! Please check your email.'),
            backgroundColor: AppColors.success,
          ),
          );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      debugPrint('Auth: Error sending OTP: $e');
      debugPrint('Auth: Error type: ${e.runtimeType}');
      if (e is Exception) {
        debugPrint('Auth: Exception message: ${e.toString()}');
      }

      if (mounted) {
        // Always show user-friendly messages (technical details are logged via debugPrint)
        final friendlyMessage = ErrorMessageHelper.getUserFriendlyError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyMessage),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _onOtpVerified() async {
    try {
      final supabase = Supabase.instance.client;
      
      // Wait a bit to ensure session is fully established
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Refresh session to ensure it's available
      try {
        await supabase.auth.refreshSession();
      } catch (e) {
        debugPrint('Auth: Warning - could not refresh session: $e');
        // Continue anyway, session might already be valid
      }
      
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('Auth: ERROR - currentUser is null after OTP verification');
        throw Exception('User not found after OTP verification. Please try again.');
      }

      debugPrint('Auth: OTP verified, user ID: $userId');
      debugPrint('Auth: Session exists: ${supabase.auth.currentSession != null}');

      final userEmail = supabase.auth.currentUser?.email ?? '';
      debugPrint('Auth: User email: $userEmail');
      
      if (userEmail.isEmpty) {
        debugPrint('Auth: WARNING - user email is empty');
      }

      // Check if user exists in database
      debugPrint('Auth: Querying users table for ID: $userId');
      final userResponse = await supabase
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();
      debugPrint('Auth: User query result: ${userResponse != null ? "found" : "not found"}');

      if (userResponse != null) {
        // User exists - check if they have pending invitation (might be new role assignment)
        debugPrint('Auth: User exists, checking for pending invitation with email: $userEmail');
        final pendingUserResponse = await supabase
            .from('pending_users')
            .select()
            .eq('email', userEmail)
            .maybeSingle()
            .catchError((e) {
              debugPrint('Auth: Error querying pending_users: $e');
              return null;
            });

        if (pendingUserResponse != null) {
          // User exists but has pending invitation - assign role/branch without creating user
          debugPrint('Auth: Found pending invitation for existing user, assigning role/branch...');
          await _assignRoleFromPending(userId, pendingUserResponse);
          setState(() {
            _otpVerified = true;
          });
          await _loadUserData(userId);
        } else {
          // User exists and no pending invitation - normal login flow
          debugPrint('Auth: User exists, proceeding with login...');
          setState(() {
            _otpVerified = true;
          });
          await _loadUserData(userId);
        }
      } else {
        // User doesn't exist - check if they have pending invitation
        debugPrint('Auth: User does not exist in users table, checking for pending invitation');
        debugPrint('Auth: User email from auth: "$userEmail"');
        
        Map<String, dynamic>? pendingUserResponse;
        try {
          // First try exact email match
          debugPrint('Auth: Querying pending_users with exact email: $userEmail');
          var response = await supabase
              .from('pending_users')
              .select()
              .eq('email', userEmail);
          
          var responseList = response as List;
          debugPrint('Auth: Exact email query returned: ${responseList.length} results');
          
          if (responseList.isEmpty) {
            // Try trimmed email
            debugPrint('Auth: Trying with trimmed email: "${userEmail.trim()}"');
            response = await supabase
                .from('pending_users')
                .select()
                .eq('email', userEmail.trim());
            responseList = response as List;
            debugPrint('Auth: Trimmed email query returned: ${responseList.length} results');
          }
          
          if (responseList.isEmpty) {
            // Try case-insensitive by fetching all and matching
            debugPrint('Auth: Trying case-insensitive match by fetching all pending users');
            final allPending = await supabase
                .from('pending_users')
                .select();
            final allPendingList = allPending as List;
            debugPrint('Auth: Total pending users in DB: ${allPendingList.length}');
            
            final userEmailLower = userEmail.trim().toLowerCase();
            for (var pending in allPendingList) {
              final pendingEmail = (pending['email'] as String? ?? '').trim().toLowerCase();
              debugPrint('Auth: Comparing "$userEmailLower" with "$pendingEmail"');
              if (pendingEmail == userEmailLower) {
                pendingUserResponse = pending as Map<String, dynamic>;
                debugPrint('Auth: ✓ Found pending user via case-insensitive match: ${pendingUserResponse['name']}');
                break;
              }
            }
          } else {
            pendingUserResponse = responseList[0] as Map<String, dynamic>;
            debugPrint('Auth: ✓ Found pending user: ${pendingUserResponse['name']} with role: ${pendingUserResponse['role']}');
          }
          
          if (pendingUserResponse == null) {
            debugPrint('Auth: ✗ No pending user found for email: $userEmail');
          }
        } catch (e) {
          debugPrint('Auth: ✗ Error querying pending_users: $e');
          debugPrint('Auth: Error type: ${e.runtimeType}');
          debugPrint('Auth: Error details: ${e.toString()}');
          // Don't return null yet - let the code continue to show registration form
        }

        if (pendingUserResponse != null) {
          // User has pending invitation - create user record and assign role/branch
          debugPrint('Auth: ✓✓✓ FOUND PENDING INVITATION ✓✓✓');
          debugPrint('Auth: Pending user name: ${pendingUserResponse['name']}');
          debugPrint('Auth: Pending user role: ${pendingUserResponse['role']}');
          debugPrint('Auth: Pending user branch_id: ${pendingUserResponse['branch_id']}');
          debugPrint('Auth: Pending user business_id: ${pendingUserResponse['business_id']}');
          debugPrint('Auth: Creating user from pending invitation...');
          
          try {
            await _createUserFromPending(userId, pendingUserResponse);
            debugPrint('Auth: ✓ Successfully created user from pending invitation');
            setState(() {
              _otpVerified = true;
            });
            await _loadUserData(userId);
            debugPrint('Auth: ✓ User data loaded, login complete');
          } catch (e) {
            debugPrint('Auth: ✗✗✗ ERROR creating user from pending ✗✗✗');
            debugPrint('Auth: Error: $e');
            debugPrint('Auth: Error type: ${e.runtimeType}');
            debugPrint('Auth: Error stack: ${StackTrace.current}');
            // Show error to user
            if (mounted) {
              final friendlyMessage = ErrorMessageHelper.getUserFriendlyError(e);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error creating account: $friendlyMessage'),
                  backgroundColor: AppColors.error,
                  duration: const Duration(seconds: 5),
                ),
              );
            }
            // Don't rethrow - let user see the error and try again
          }
        } else {
          // No pending invitation - registration flow
          debugPrint('Auth: ✗✗✗ NO PENDING INVITATION FOUND ✗✗✗');
          debugPrint('Auth: Email searched: $userEmail');
          debugPrint('Auth: Showing registration form...');
          setState(() {
            _otpVerified = true;
            _showRegistrationForm = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Auth: Error in OTP verification flow: $e');
      if (mounted) {
        final friendlyMessage = ErrorMessageHelper.getUserFriendlyError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _createUserFromPending(String userId, Map<String, dynamic> pendingUser) async {
    try {
      final supabase = Supabase.instance.client;
      
      // Create user record in database
      await supabase.from('users').insert({
        'id': userId,
        'name': pendingUser['name'],
        'email': pendingUser['email'],
        'phone': pendingUser['phone'],
      });

      // Update user metadata in Supabase Auth to set display name
      await supabase.auth.updateUser(
        UserAttributes(
          data: {
            'full_name': pendingUser['name'],
            'display_name': pendingUser['name'],
          },
        ),
      );

      debugPrint('Created user record from pending invitation: ${pendingUser['name']} (ID: $userId)');

      // Assign role and branch
      final role = pendingUser['role'] as String;
      final branchId = pendingUser['branch_id'] as String?;
      final businessId = pendingUser['business_id'] as String?;

      if (businessId == null || businessId.isEmpty) {
        throw Exception('Business ID is missing from pending user record');
      }

      debugPrint('Pending user details - Role: $role, Branch ID: $branchId, Business ID: $businessId');

      int branchesAssigned = 0;

      // If business owner or business owner read-only, assign to all branches
      if (role == 'business_owner' || role == 'business_owner_read_only') {
        final allBranchesResponse = await supabase
            .from('branches')
            .select('id')
            .eq('business_id', businessId);

        final allBranches = allBranchesResponse as List;
        debugPrint('Found ${allBranches.length} branches for business $businessId');

        if (allBranches.isEmpty) {
          throw Exception('No branches found for business $businessId. Cannot assign business owner role.');
        }

        for (var branchItem in allBranches) {
          try {
            final bid = branchItem['id'] as String?;
            if (bid == null || bid.isEmpty) {
              debugPrint('Warning: Skipping branch with null or empty ID');
              continue;
            }

            await supabase.from('branch_users').insert({
              'user_id': userId,
              'branch_id': bid,
              'business_id': businessId,
              'role': role,
            });
            branchesAssigned++;
            debugPrint('Successfully assigned $role role to branch $bid');
          } catch (e) {
            debugPrint('Error assigning role to branch ${branchItem['id']}: $e');
            // Continue with other branches even if one fails
          }
        }
        
        if (branchesAssigned == 0) {
          throw Exception('Failed to assign user to any branches. User record created but role assignment failed.');
        }
        
        debugPrint('Successfully assigned $role role to $branchesAssigned branches for business $businessId');
      } else {
        // Assign to specific branch (for owner, owner_read_only, manager, staff roles)
        if (branchId == null || branchId.isEmpty) {
          throw Exception('Branch ID is required for non-business-owner roles');
        }
        
        try {
          debugPrint('Assigning $role role to branch $branchId for user $userId');
          await supabase.from('branch_users').insert({
            'user_id': userId,
            'branch_id': branchId,
            'business_id': businessId,
            'role': role,
          });
          branchesAssigned = 1;
          debugPrint('Successfully assigned $role role to branch $branchId');
        } catch (e) {
          debugPrint('Error assigning role to branch $branchId: $e');
          debugPrint('Error details: ${e.toString()}');
          // Re-throw with more context
          throw Exception('Failed to assign $role role to branch $branchId: $e');
        }
      }

      // Verify that branch_users entries were created
      final verifyResponse = await supabase
          .from('branch_users')
          .select('id')
          .eq('user_id', userId);
      
      final verifyCount = (verifyResponse as List).length;
      debugPrint('Verification: Found $verifyCount branch_users entries for user $userId');
      
      if (verifyCount == 0) {
        throw Exception('User created but no branch assignments were created. Verification failed.');
      }

      // Delete pending user record only after successful assignment
      await supabase
          .from('pending_users')
          .delete()
          .eq('email', pendingUser['email']);

      debugPrint('Deleted pending user record for ${pendingUser['email']}');
    } catch (e) {
      debugPrint('Error creating user from pending invitation: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  // Assign role and branch to existing user from pending invitation
  Future<void> _assignRoleFromPending(String userId, Map<String, dynamic> pendingUser) async {
    try {
      final supabase = Supabase.instance.client;

      // Update user name if different
      final currentUser = await supabase
          .from('users')
          .select('name')
          .eq('id', userId)
          .single();
      
      if (currentUser['name'] != pendingUser['name']) {
        await supabase
            .from('users')
            .update({'name': pendingUser['name']})
            .eq('id', userId);
        debugPrint('Updated user name from ${currentUser['name']} to ${pendingUser['name']}');
      }

      // Update user metadata in Supabase Auth to set display name
      await supabase.auth.updateUser(
        UserAttributes(
          data: {
            'full_name': pendingUser['name'],
            'display_name': pendingUser['name'],
          },
        ),
      );
      debugPrint('Updated auth.users metadata for display name.');

      // Assign role and branch
      final role = pendingUser['role'] as String;
      final branchId = pendingUser['branch_id'] as String?;
      final businessId = pendingUser['business_id'] as String?;

      if (businessId == null || businessId.isEmpty) {
        throw Exception('Business ID is missing from pending user record');
      }

      debugPrint('Pending user details - Role: $role, Branch ID: $branchId, Business ID: $businessId');

      int branchesAssigned = 0;

      // If business owner or business owner read-only, assign to all branches
      if (role == 'business_owner' || role == 'business_owner_read_only') {
        final allBranchesResponse = await supabase
            .from('branches')
            .select('id')
            .eq('business_id', businessId);

        final allBranches = allBranchesResponse as List;
        debugPrint('Found ${allBranches.length} branches for business $businessId');

        if (allBranches.isEmpty) {
          throw Exception('No branches found for business $businessId. Cannot assign business owner role.');
        }

        for (var branchItem in allBranches) {
          try {
            final bid = branchItem['id'] as String?;
            if (bid == null || bid.isEmpty) {
              debugPrint('Warning: Skipping branch with null or empty ID');
              continue;
            }

            // Use upsert to handle existing assignments
            await supabase.from('branch_users').upsert({
              'user_id': userId,
              'branch_id': bid,
              'business_id': businessId,
              'role': role,
            }, onConflict: 'branch_id,user_id');
            branchesAssigned++;
            debugPrint('Successfully assigned $role role to branch $bid');
          } catch (e) {
            debugPrint('Error assigning role to branch ${branchItem['id']}: $e');
            // Continue with other branches even if one fails
          }
        }

        if (branchesAssigned == 0) {
          throw Exception('Failed to assign user to any branches. Role assignment failed.');
        }

        debugPrint('Successfully assigned $role role to $branchesAssigned branches for business $businessId');
      } else {
        // Assign to specific branch
        if (branchId == null || branchId.isEmpty) {
          throw Exception('Branch ID is required for non-business-owner roles');
        }

        try {
          // Use upsert to handle existing assignments
          await supabase.from('branch_users').upsert({
            'user_id': userId,
            'branch_id': branchId,
            'business_id': businessId,
            'role': role,
          }, onConflict: 'branch_id,user_id');
          branchesAssigned = 1;
          debugPrint('Successfully assigned $role role to branch $branchId');
        } catch (e) {
          debugPrint('Error assigning role to branch $branchId: $e');
          throw Exception('Failed to assign role to branch: $e');
        }
      }

      // Verify that branch_users entries were created
      final verifyResponse = await supabase
          .from('branch_users')
          .select('id')
          .eq('user_id', userId);

      final verifyCount = (verifyResponse as List).length;
      debugPrint('Verification: Found $verifyCount branch_users entries for user $userId');

      if (verifyCount == 0) {
        throw Exception('No branch assignments were created. Verification failed.');
      }

      // Delete pending user record only after successful assignment
      await supabase
          .from('pending_users')
          .delete()
          .eq('email', pendingUser['email']);

      debugPrint('Deleted pending user record for ${pendingUser['email']}');
    } catch (e) {
      debugPrint('Error assigning role from pending invitation: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  Future<void> _loadUserData(String userId) async {
    try {
      final authService = AuthService();
      
      // Get user from database
      final userResponse = await Supabase.instance.client
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (userResponse != null) {
        final user = models.User.fromJson(userResponse);
        
        // Check if user is a business owner (including read-only) to load all branches
        final businessOwnerCheck = await Supabase.instance.client
            .from('branch_users')
            .select('business_id, role')
            .eq('user_id', userId)
            .or('role.eq.business_owner,role.eq.business_owner_read_only')
            .limit(1)
            .maybeSingle();
        
        List<Branch> branches = [];
        
        if (businessOwnerCheck != null) {
          // Business owner or read-only: get all branches for their businesses
          debugPrint('Loading branches for business owner: $userId');
          
          // Get all businesses where user is business owner (including read-only)
          final businessAssignments = await Supabase.instance.client
              .from('branch_users')
              .select('business_id, role')
              .eq('user_id', userId)
              .or('role.eq.business_owner,role.eq.business_owner_read_only');
          
          final Set<String> businessIds = (businessAssignments as List)
              .map((record) => record['business_id'] as String?)
              .whereType<String>()
              .toSet();
          
          debugPrint('Business owner has access to businesses: ${businessIds.join(", ")}');
          
          // Get all branches for these businesses
          for (var bid in businessIds) {
            final allBranchesResponse = await Supabase.instance.client
                .from('branches')
                .select()
                .eq('business_id', bid);
            
            final businessBranches = (allBranchesResponse as List)
                .map((json) => Branch.fromJson(json))
                .toList();
            
            debugPrint('Loaded ${businessBranches.length} branches for business $bid');
            branches.addAll(businessBranches);
          }
        } else {
          // Regular user: get only assigned branches
          debugPrint('Loading branches for regular user: $userId');
        final branchesResponse = await Supabase.instance.client
            .from('branch_users')
            .select('branches(*)')
            .eq('user_id', userId);

          branches = (branchesResponse as List)
            .where((item) => item['branches'] != null)
            .map((item) => Branch.fromJson(item['branches']))
            .toList();

          debugPrint('Loaded ${branches.length} branches for regular user');
        }

        debugPrint('Total branches loaded for user: ${branches.length}');
        
        await authService.setUser(user, branches);
        await authService.refreshBranches();
        await authService.refreshBusinessOwnerStatus();

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const DashboardHomeScreen()),
          );
        }
      } else {
        throw Exception('User not found in database');
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      if (mounted) {
        final friendlyMessage = ErrorMessageHelper.getUserFriendlyError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final supabase = Supabase.instance.client;
      final email = _emailController.text.trim();
      
      // User should already be authenticated via OTP
      final currentSession = supabase.auth.currentSession;
      if (currentSession == null) {
        throw Exception('Session expired. Please verify your email again.');
      }

      final userId = currentSession.user.id;
      debugPrint('Registration: Creating user record for ID: $userId');

      // Create user record in database
      final userName = _nameController.text.trim();
      await supabase.from('users').insert({
        'id': userId,
        'name': userName,
        'email': email,
        'phone': null,
      });

      // Update user metadata in Supabase Auth to set display name
      await supabase.auth.updateUser(
        UserAttributes(
          data: {
            'full_name': userName,
            'display_name': userName,
          },
        ),
      );

      // Create business
      Business business;
      final businessResponse = await supabase
          .from('businesses')
          .insert({
            'name': _businessNameController.text.trim(),
          })
          .select()
          .single();

      business = Business.fromJson(businessResponse);
      debugPrint('Created new business: ${business.name}');
      
      // Verify session is active before branch creation
      final sessionBeforeBranch = supabase.auth.currentSession;
      if (sessionBeforeBranch == null) {
        throw Exception('Session expired. Please try again.');
      }
      
      // Small delay to ensure business is committed
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Create first branch
      List<Branch> businessBranches = [];
      final branchResponse = await supabase
          .from('branches')
          .insert({
            'business_id': business.id,
            'name': _branchNameController.text.trim(),
            'location': _branchLocationController.text.trim(),
            'status': 'active',
          })
          .select()
          .single();

      businessBranches = [Branch.fromJson(branchResponse)];
      debugPrint('Branch created successfully: ${businessBranches.first.name}');

      await _ensureBranchUserAssignments(
        userId: userId,
        businessId: business.id,
        branches: businessBranches,
        role: 'business_owner',
      );
      debugPrint('Assigned user $userId as business_owner to new branch.');

      final authService = AuthService();
      final user = models.User(
        id: userId,
        name: _nameController.text.trim(),
        phone: null,
        email: email,
        role: models.UserRole.businessOwner,
      );

      await authService.setUser(user, businessBranches);
      await authService.refreshBranches();
      await authService.refreshBusinessOwnerStatus();

      debugPrint('Registration complete - Current role: ${authService.currentRole}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration successful!'),
            backgroundColor: AppColors.success,
          ),
        );

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const DashboardHomeScreen()),
        );
      }
    } catch (e) {
      debugPrint('Error during registration: $e');
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
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
  }

  Future<void> _ensureBranchUserAssignments({
    required String userId,
    required String businessId,
    required List<Branch> branches,
    required String role,
  }) async {
    final supabase = Supabase.instance.client;
    for (var branch in branches) {
      if (branch.id.isEmpty) {
        debugPrint('Skipping branch assignment with empty ID for business $businessId');
        continue;
      }
      try {
        await supabase.from('branch_users').upsert(
          {
            'user_id': userId,
            'branch_id': branch.id,
            'business_id': businessId,
            'role': role,
          },
          onConflict: 'user_id,branch_id',
        );
        debugPrint('Ensured $role assignment for branch ${branch.name} (${branch.id})');
      } catch (e) {
        debugPrint('Error ensuring $role assignment for branch ${branch.id}: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: SizedBox(
                        width: 100,
                        height: 100,
                        child: Image.asset(
                          'assets/Credilo.app Logo 500.png',
                          fit: BoxFit.cover,
                          width: 100,
                          height: 100,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'credilo',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_showRegistrationForm) ...[
                  const SizedBox(height: 8),
                  Text(
                      'Complete your registration',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  ],
                  const SizedBox(height: 48),
                  if (!_otpSent && !_showRegistrationForm) ...[
                    // Step 1: Email input and Send OTP
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      hintText: 'user@example.com',
                      prefixIcon: const Icon(Icons.email),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter email';
                      }
                      if (!value.contains('@')) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                    const SizedBox(height: 32),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _sendOtp,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text(
                                'Send Verification Code',
                                style: TextStyle(fontSize: 16),
                              ),
                      ),
                    ),
                  ] else if (_otpSent && !_otpVerified) ...[
                    // Step 2: OTP verification
                    OtpVerificationWidget(
                      email: _emailController.text.trim(),
                      onVerified: _onOtpVerified,
                      title: 'Enter Verification Code',
                      subtitle: 'We sent a verification code to your email',
                        ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                        onPressed: () {
                          setState(() {
                          _otpSent = false;
                          _otpVerified = false;
                          });
                        },
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Change Email'),
                    ),
                  ] else if (_showRegistrationForm) ...[
                    // Step 3: Registration form (if user doesn't exist)
                    TextFormField(
                      controller: _nameController,
                      enabled: !_isLoading,
                      decoration: const InputDecoration(
                        labelText: 'Full Name *',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _businessNameController,
                      enabled: !_isLoading,
                      decoration: const InputDecoration(
                        labelText: 'Business Name *',
                        hintText: 'My Business',
                        prefixIcon: Icon(Icons.business),
                        border: OutlineInputBorder(),
                    ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Business name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _branchNameController,
                      enabled: !_isLoading,
                      decoration: const InputDecoration(
                        labelText: 'Branch Name *',
                        hintText: 'Main Branch',
                        prefixIcon: Icon(Icons.store),
                        border: OutlineInputBorder(),
                      ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                          return 'Branch name is required';
                      }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _branchLocationController,
                      enabled: !_isLoading,
                      decoration: const InputDecoration(
                        labelText: 'Branch Location *',
                        hintText: 'Adyar, Chennai',
                        prefixIcon: Icon(Icons.location_on),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Location is required';
                      }
                      return null;
                    },
                  ),
                    const SizedBox(height: 24),
                    Card(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: AppColors.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'You will be set as the Owner of this business and branch. You can add more branches and users later.',
                                style: TextStyle(
                                  color: AppColors.primaryLight,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                        onPressed: _isLoading ? null : _register,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                                'Create Account',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}