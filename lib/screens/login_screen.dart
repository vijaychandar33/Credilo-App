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
        // User exists - check if they have pending invitation(s) (might be new role/branch assignments)
        debugPrint('Auth: User exists, checking for pending invitation with email: $userEmail');
        List<Map<String, dynamic>> pendingList = [];
        try {
          final pendingResponse = await supabase
              .from('pending_users')
              .select()
              .eq('email', userEmail);
          final rawList = pendingResponse as List;
          for (var r in rawList) {
            pendingList.add(r as Map<String, dynamic>);
          }
        } catch (e) {
          debugPrint('Auth: Error querying pending_users: $e');
        }

        if (pendingList.isNotEmpty) {
          debugPrint('Auth: Found ${pendingList.length} pending invitation(s) for existing user');
          await _assignRoleFromPending(userId, pendingList);
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
        
        List<Map<String, dynamic>> pendingUserList = [];
        try {
          // First try exact email match (can return multiple rows per email)
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
              if (pendingEmail == userEmailLower) {
                pendingUserList.add(pending as Map<String, dynamic>);
              }
            }
            if (pendingUserList.isNotEmpty) {
              debugPrint('Auth: ✓ Found ${pendingUserList.length} pending row(s) via case-insensitive match');
            }
          } else {
            for (var r in responseList) {
              pendingUserList.add(r as Map<String, dynamic>);
            }
            debugPrint('Auth: ✓ Found ${pendingUserList.length} pending row(s) for: ${pendingUserList[0]['name']}');
          }
          
          if (pendingUserList.isEmpty) {
            debugPrint('Auth: ✗ No pending user found for email: $userEmail');
          }
        } catch (e) {
          debugPrint('Auth: ✗ Error querying pending_users: $e');
          debugPrint('Auth: Error type: ${e.runtimeType}');
          debugPrint('Auth: Error details: ${e.toString()}');
          // Don't return null yet - let the code continue to show registration form
        }

        if (pendingUserList.isNotEmpty) {
          // User has pending invitation(s) - create user record and assign all branches/roles
          final first = pendingUserList.first;
          debugPrint('Auth: ✓✓✓ FOUND PENDING INVITATION(S) ✓✓✓');
          debugPrint('Auth: Pending user name: ${first['name']}, ${pendingUserList.length} branch assignment(s)');
          debugPrint('Auth: Creating user from pending invitation...');
          
          try {
            await _createUserFromPending(userId, pendingUserList);
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

  Future<void> _createUserFromPending(String userId, List<Map<String, dynamic>> pendingRows) async {
    if (pendingRows.isEmpty) return;
    try {
      final supabase = Supabase.instance.client;
      final first = pendingRows.first;

      // Create user record once
      await supabase.from('users').insert({
        'id': userId,
        'name': first['name'],
        'email': first['email'],
        'phone': first['phone'],
      });

      await supabase.auth.updateUser(
        UserAttributes(
          data: {
            'full_name': first['name'],
            'display_name': first['name'],
          },
        ),
      );

      debugPrint('Created user record from pending: ${first['name']} (ID: $userId), ${pendingRows.length} branch assignment(s)');

      int branchesAssigned = 0;
      final assignedBusinessIds = <String>{};

      for (var pendingUser in pendingRows) {
        final role = pendingUser['role'] as String;
        final branchId = pendingUser['branch_id'] as String?;
        final businessId = pendingUser['business_id'] as String?;

        if (businessId == null || businessId.isEmpty) {
          debugPrint('Skipping pending row with missing business_id');
          continue;
        }

        if (role == 'business_owner' || role == 'business_owner_read_only') {
          if (assignedBusinessIds.contains(businessId)) continue;
          assignedBusinessIds.add(businessId);

          final allBranchesResponse = await supabase
              .from('branches')
              .select('id')
              .eq('business_id', businessId);
          final allBranches = allBranchesResponse as List;

          for (var branchItem in allBranches) {
            final bid = branchItem['id'] as String?;
            if (bid == null || bid.isEmpty) continue;
            try {
              await supabase.from('branch_users').insert({
                'user_id': userId,
                'branch_id': bid,
                'business_id': businessId,
                'role': role,
              });
              branchesAssigned++;
            } catch (e) {
              debugPrint('Error assigning $role to branch $bid: $e');
            }
          }
        } else {
          if (branchId == null || branchId.isEmpty) continue;
          try {
            await supabase.from('branch_users').insert({
              'user_id': userId,
              'branch_id': branchId,
              'business_id': businessId,
              'role': role,
            });
            branchesAssigned++;
          } catch (e) {
            debugPrint('Error assigning $role to branch $branchId: $e');
          }
        }
      }

      if (branchesAssigned == 0) {
        throw Exception('User created but no branch assignments were created.');
      }

      debugPrint('Verification: $branchesAssigned branch_users entries for user $userId');

      await supabase.from('pending_users').delete().eq('email', first['email'] as String);
      debugPrint('Deleted all pending_users rows for ${first['email']}');
    } catch (e) {
      debugPrint('Error creating user from pending invitation: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  // Assign roles and branches to existing user from pending invitation(s)
  Future<void> _assignRoleFromPending(String userId, List<Map<String, dynamic>> pendingRows) async {
    if (pendingRows.isEmpty) return;
    try {
      final supabase = Supabase.instance.client;
      final first = pendingRows.first;

      final currentUser = await supabase
          .from('users')
          .select('name')
          .eq('id', userId)
          .single();

      if (currentUser['name'] != first['name']) {
        await supabase
            .from('users')
            .update({'name': first['name']})
            .eq('id', userId);
      }

      await supabase.auth.updateUser(
        UserAttributes(
          data: {
            'full_name': first['name'],
            'display_name': first['name'],
          },
        ),
      );

      int branchesAssigned = 0;
      final assignedBusinessIds = <String>{};

      for (var pendingUser in pendingRows) {
        final role = pendingUser['role'] as String;
        final branchId = pendingUser['branch_id'] as String?;
        final businessId = pendingUser['business_id'] as String?;

        if (businessId == null || businessId.isEmpty) continue;

        if (role == 'business_owner' || role == 'business_owner_read_only') {
          if (assignedBusinessIds.contains(businessId)) continue;
          assignedBusinessIds.add(businessId);

          final allBranchesResponse = await supabase
              .from('branches')
              .select('id')
              .eq('business_id', businessId);
          final allBranches = allBranchesResponse as List;

          for (var branchItem in allBranches) {
            final bid = branchItem['id'] as String?;
            if (bid == null || bid.isEmpty) continue;
            try {
              await supabase.from('branch_users').upsert({
                'user_id': userId,
                'branch_id': bid,
                'business_id': businessId,
                'role': role,
              }, onConflict: 'branch_id,user_id');
              branchesAssigned++;
            } catch (e) {
              debugPrint('Error assigning $role to branch $bid: $e');
            }
          }
        } else {
          if (branchId == null || branchId.isEmpty) continue;
          try {
            await supabase.from('branch_users').upsert({
              'user_id': userId,
              'branch_id': branchId,
              'business_id': businessId,
              'role': role,
            }, onConflict: 'branch_id,user_id');
            branchesAssigned++;
          } catch (e) {
            debugPrint('Error assigning $role to branch $branchId: $e');
          }
        }
      }

      if (branchesAssigned == 0) {
        throw Exception('No branch assignments were created.');
      }

      await supabase.from('pending_users').delete().eq('email', first['email'] as String);
      debugPrint('Assigned $branchesAssigned branch(es) and deleted pending rows for ${first['email']}');
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