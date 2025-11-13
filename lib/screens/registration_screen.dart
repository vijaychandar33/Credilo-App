import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../services/auth_service.dart';
import '../models/user.dart' as models;
import '../models/business.dart';
import '../models/branch.dart';
import 'dashboard_home_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _branchNameController = TextEditingController();
  final _branchLocationController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  int _currentStep = 0;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _businessNameController.dispose();
    _branchNameController.dispose();
    _branchLocationController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final supabase = Supabase.instance.client;
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      String userId;
      bool isExistingAuthUser = false;

      // Step 1: Try to sign up user with email and password
      try {
        final authResponse = await supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'name': _nameController.text.trim(),
          },
        );

        if (authResponse.user == null) {
          throw Exception('Registration failed: Could not create user account');
        }

        userId = authResponse.user!.id;

        // Ensure session is active (required for RLS policies)
        // Supabase may require email confirmation, so we sign in to establish session
        if (authResponse.session == null) {
          debugPrint('No session after signup, signing in to establish session...');
          // Small delay to ensure user is fully created
          await Future.delayed(const Duration(milliseconds: 500));
          
          final signInResponse = await supabase.auth.signInWithPassword(
            email: email,
            password: password,
          );

          if (signInResponse.user == null || signInResponse.session == null) {
            throw Exception('Unable to establish session after registration. Please try signing in manually.');
          }
          
          debugPrint('Session established after sign in');
        } else {
          debugPrint('Session established from signup');
        }
        
        // Verify session is active
        final currentSession = supabase.auth.currentSession;
        if (currentSession == null) {
          throw Exception('Session not active. Please try again.');
        }
        
        debugPrint('Current session user ID: ${currentSession.user.id}');
      } catch (signUpError) {
        // If user already exists in auth, try to sign in and complete registration
        final errorString = signUpError.toString();
        if (errorString.contains('user_already_exists') || 
            errorString.contains('User already registered')) {
          
          debugPrint('User exists in auth, attempting to sign in and complete registration...');
          
          // Sign in to get the user
          final signInResponse = await supabase.auth.signInWithPassword(
            email: email,
            password: password,
          );

          if (signInResponse.user == null) {
            throw Exception('User exists but could not sign in. Please use the correct password.');
          }

          userId = signInResponse.user!.id;
          isExistingAuthUser = true;

          // Check if user already exists in database
          final existingUser = await supabase
              .from('users')
              .select()
              .eq('id', userId)
              .maybeSingle();

          if (existingUser != null) {
            // User exists in both auth and database - redirect to login
            throw Exception('User already registered');
          }

          // User exists in auth but not in database - complete the registration
          debugPrint('User exists in auth but not in database. Completing registration...');
        } else {
          rethrow;
        }
      }

      // Step 2: Create user record in database (if doesn't exist)
      if (!isExistingAuthUser) {
        await supabase.from('users').insert({
          'id': userId, // Use auth user ID
          'name': _nameController.text.trim(),
          'email': email,
          'phone': null, // Phone is optional now
        });
      } else {
        // Update existing user or create if missing
        await supabase.from('users').upsert({
          'id': userId,
          'name': _nameController.text.trim(),
          'email': email,
          'phone': null,
        });
      }

      // Step 3: Create business (check if user already has a business)
      Business business;
      final existingBusinessesResponse = await supabase
          .from('businesses')
          .select()
          .eq('owner_id', userId)
          .limit(1);

      final existingBusinesses = existingBusinessesResponse as List;
      if (existingBusinesses.isNotEmpty) {
        // User already has a business, use the first one
        business = Business.fromJson(existingBusinesses.first);
        debugPrint('Using existing business: ${business.name}');
      } else {
        // Create new business
        final businessResponse = await supabase
            .from('businesses')
            .insert({
              'name': _businessNameController.text.trim(),
              'owner_id': userId,
            })
            .select()
            .single();

        business = Business.fromJson(businessResponse);
      }
      
      // Ensure business is committed and session is active before branch creation
      // Verify session is active
      final sessionBeforeBranch = supabase.auth.currentSession;
      if (sessionBeforeBranch == null) {
        throw Exception('Session expired. Please try again.');
      }
      
      debugPrint('Session verified before branch creation: ${sessionBeforeBranch.user.id}');
      
      // Small delay to ensure business is committed before branch creation
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Verify business exists and user is owner (for debugging)
      final verifyBusiness = await supabase
          .from('businesses')
          .select()
          .eq('id', business.id)
          .eq('owner_id', userId)
          .maybeSingle();
      
      if (verifyBusiness == null) {
        debugPrint('ERROR: Business not found or user is not owner');
        debugPrint('Business ID: ${business.id}, User ID: $userId');
        throw Exception('Business verification failed. Please try again.');
      }
      
      debugPrint('Business verified: ${business.name}, Owner: $userId');

      // Step 4: Create first branch (check if business already has branches)
      Branch branch;
      final existingBranchesResponse = await supabase
          .from('branches')
          .select()
          .eq('business_id', business.id)
          .limit(1);

      final existingBranches = existingBranchesResponse as List;
      if (existingBranches.isNotEmpty) {
        // Business already has a branch, use the first one
        branch = Branch.fromJson(existingBranches.first);
        debugPrint('Using existing branch: ${branch.name}');
      } else {
        // Create new branch
        // Double-check session before insert
        final currentSession = supabase.auth.currentSession;
        if (currentSession == null) {
          throw Exception('Session expired. Please sign in and try again.');
        }
        
        debugPrint('Creating branch with business_id: ${business.id}, user_id: $userId');
        debugPrint('Current session user: ${currentSession.user.id}');
        
        try {
          debugPrint('Attempting to create branch...');
          debugPrint('Business ID: ${business.id}');
          debugPrint('User ID: $userId');
          debugPrint('Session user: ${currentSession.user.id}');
          
          // Verify we can see the business (RLS check)
          final canSeeBusiness = await supabase
              .from('businesses')
              .select('id, owner_id')
              .eq('id', business.id)
              .maybeSingle();
          
          if (canSeeBusiness == null) {
            throw Exception('Cannot access business. RLS policy may be blocking access.');
          }
          
          debugPrint('Can see business: ${canSeeBusiness['id']}, owner: ${canSeeBusiness['owner_id']}');
          
          final branchResponse = await supabase
              .from('branches')
              .insert({
                'business_id': business.id,
                'name': _branchNameController.text.trim(),
                'location': _branchLocationController.text.trim(),
                'manager_id': userId,
                'status': 'active',
              })
              .select()
              .single();

          branch = Branch.fromJson(branchResponse);
          debugPrint('Branch created successfully: ${branch.name}');
        } catch (branchError) {
          debugPrint('Branch creation error: $branchError');
          debugPrint('Business ID: ${business.id}, User ID: $userId');
          debugPrint('Error type: ${branchError.runtimeType}');
          debugPrint('Error details: ${branchError.toString()}');
          rethrow;
        }
      }

      // Step 5: Assign user as owner to branch (check if already assigned)
      final existingBranchUser = await supabase
          .from('branch_users')
          .select()
          .eq('branch_id', branch.id)
          .eq('user_id', userId)
          .maybeSingle();

      if (existingBranchUser == null) {
        // User not assigned to branch, assign as owner
        debugPrint('Assigning user to branch as owner...');
        try {
          await supabase.from('branch_users').insert({
            'branch_id': branch.id,
            'user_id': userId,
            'role': 'owner',
          });
          debugPrint('User assigned to branch successfully');
        } catch (branchUserError) {
          debugPrint('Error assigning user to branch: $branchUserError');
          // This is not critical - user can still access branch as business owner
          // But log the error for debugging
        }
      } else {
        debugPrint('User already assigned to branch with role: ${existingBranchUser['role']}');
      }

      // Step 6: Load user data and navigate
      final authService = AuthService();
      final user = models.User(
        id: userId,
        name: _nameController.text.trim(),
        phone: null,
        email: email,
        role: models.UserRole.owner,
      );

      // Set user and ensure branch_users are loaded
      await authService.setUser(user, [branch]);
      
      // Double-check: reload branch users to ensure they're loaded
      await authService.refreshBranches();
      
      // Verify role is set
      debugPrint('Registration complete - Current role: ${authService.currentRole}');
      debugPrint('Can manage users: ${authService.canManageUsers()}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration successful!'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const DashboardHomeScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        String errorMessage = 'Registration failed';
        bool showLoginDialog = false;
        
        // Handle specific error types
        final errorString = e.toString();
        if (errorString.contains('user_already_exists') || 
            errorString.contains('User already registered')) {
          errorMessage = 'This email is already registered.';
          showLoginDialog = true;
        } else if (errorString.contains('PostgrestException')) {
          // Extract the actual error message from PostgrestException
          final match = RegExp(r'message: ([^,]+)').firstMatch(errorString);
          if (match != null) {
            errorMessage = 'Database error: ${match.group(1)}';
          } else {
            errorMessage = 'Database error occurred';
          }
        } else if (errorString.contains('Invalid login credentials') ||
                   errorString.contains('Invalid credentials')) {
          errorMessage = 'Invalid email or password';
        } else {
          errorMessage = 'Registration failed: ${errorString.split(':').last.trim()}';
        }
        
        if (showLoginDialog) {
          // Show dialog to redirect to login
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Account Already Exists'),
              content: const Text(
                'This email is already registered. Would you like to sign in instead?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context); // Close dialog
                    Navigator.pop(context); // Go back to login screen
                  },
                  child: const Text('Sign In'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Stepper(
            currentStep: _currentStep,
            onStepContinue: () {
              if (_currentStep < 2) {
                if (_validateStep(_currentStep)) {
                  setState(() {
                    _currentStep++;
                  });
                }
              } else {
                _register();
              }
            },
            onStepCancel: () {
              if (_currentStep > 0) {
                setState(() {
                  _currentStep--;
                });
              } else {
                Navigator.pop(context);
              }
            },
            steps: [
              Step(
                title: const Text('Account Information'),
                content: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
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
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email *',
                        hintText: 'user@example.com',
                        prefixIcon: Icon(Icons.email),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Email is required';
                        }
                        if (!value.contains('@')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password *',
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      obscureText: _obscurePassword,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Password is required';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPasswordController,
                      decoration: InputDecoration(
                        labelText: 'Confirm Password *',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword = !_obscureConfirmPassword;
                            });
                          },
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      obscureText: _obscureConfirmPassword,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please confirm password';
                        }
                        if (value != _passwordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              Step(
                title: const Text('Business Details'),
                content: Column(
                  children: [
                    TextFormField(
                      controller: _businessNameController,
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
                  ],
                ),
              ),
              Step(
                title: const Text('Branch Details'),
                content: Column(
                  children: [
                    TextFormField(
                      controller: _branchNameController,
                      decoration: const InputDecoration(
                        labelText: 'Branch Name *',
                        hintText: 'Main Branch / Pelican741 Adyar',
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
                    const SizedBox(height: 16),
                    Card(
                      color: Colors.blue.withValues(alpha: 0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.blue),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'You will be set as the Owner of this business and branch. You can add more branches and users later.',
                                style: TextStyle(
                                  color: Colors.blue[100],
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            controlsBuilder: (context, details) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    if (_currentStep > 0)
                      OutlinedButton(
                        onPressed: details.onStepCancel,
                        child: const Text('Back'),
                      ),
                    if (_currentStep > 0) const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : details.onStepContinue,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_currentStep == 2 ? 'Create Account' : 'Next'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  bool _validateStep(int step) {
    switch (step) {
      case 0:
        return _nameController.text.isNotEmpty &&
            _emailController.text.isNotEmpty &&
            _emailController.text.contains('@') &&
            _passwordController.text.isNotEmpty &&
            _passwordController.text.length >= 6 &&
            _confirmPasswordController.text == _passwordController.text;
      case 1:
        return _businessNameController.text.isNotEmpty;
      case 2:
        return _branchNameController.text.isNotEmpty &&
            _branchLocationController.text.isNotEmpty;
      default:
        return false;
    }
  }
}
