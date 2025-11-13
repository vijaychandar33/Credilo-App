import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../models/user.dart';
import '../models/branch.dart';
import '../services/auth_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) return;

      // Get all branches for the business
      final branchesResponse = await Supabase.instance.client
          .from('branches')
          .select('*, businesses!inner(owner_id)')
          .eq('businesses.owner_id', currentUser.id);

      _allBranches = (branchesResponse as List)
          .map((json) => Branch.fromJson(json))
          .toList();

      // Get all users with their branch assignments
      if (_allBranches.isEmpty) {
        _users = [];
        return;
      }
      
      final branchIds = _allBranches.map((b) => b.id).toList();
      
      // Get users for all branches - use filter with OR
      final List<dynamic> allUsers = [];
      for (var branchId in branchIds) {
        try {
          final response = await Supabase.instance.client
              .from('branch_users')
              .select('*, users(*), branches(*)')
              .eq('branch_id', branchId);
          debugPrint('Loaded ${(response as List).length} branch_users for branch $branchId');
          allUsers.addAll(response as List);
        } catch (e) {
          debugPrint('Error loading branch_users for branch $branchId: $e');
        }
      }
      
      debugPrint('Total branch_users loaded: ${allUsers.length}');
      final usersResponse = allUsers;

      // Group users by user_id
      final Map<String, Map<String, dynamic>> userMap = {};
      
      for (var item in usersResponse) {
        try {
          final userId = item['user_id'] as String;
          if (item['users'] == null) {
            debugPrint('Warning: branch_user $userId has null users data');
            continue;
          }
          if (!userMap.containsKey(userId)) {
            userMap[userId] = {
              'user': User.fromJson(item['users']),
              'branches': <Map<String, dynamic>>[],
            };
          }
          userMap[userId]!['branches'].add({
            'branch': Branch.fromJson(item['branches']),
            'role': item['role'],
            'branch_user_id': item['id'],
          });
        } catch (e) {
          debugPrint('Error processing branch_user item: $e');
        }
      }

      _users = userMap.values.toList();
      debugPrint('Final users count: ${_users.length}');
    } catch (e) {
      debugPrint('Error loading users: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showAddUserDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    Branch? selectedBranch;
    UserRole? selectedRole;
    bool obscurePassword = true;

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
                  items: UserRole.values.map((role) {
                    return DropdownMenuItem(
                      value: role,
                      child: Text(role.toString().split('.').last.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (role) {
                    setDialogState(() {
                      selectedRole = role;
                    });
                  },
                ),
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
                    selectedBranch == null ||
                    selectedRole == null) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please fill all required fields (password must be at least 6 characters)'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                  return;
                }

                await _addUser(
                  nameController.text,
                  emailController.text,
                  passwordController.text,
                  selectedBranch!,
                  selectedRole!,
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
    UserRole role,
  ) async {
    try {
      final supabase = Supabase.instance.client;
      String userId;
      bool isNewUser = false;

      // Step 1: Try to create user in Supabase Auth
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
      } catch (signUpError) {
        // Check if user already exists in auth
        final errorString = signUpError.toString();
        if (errorString.contains('user_already_exists') || 
            errorString.contains('User already registered')) {
          
          debugPrint('User already exists in auth, checking database...');
          
          // Try to find existing user by email
          final existingUsersResponse = await supabase
              .from('users')
              .select()
              .eq('email', email)
              .maybeSingle();
          
          if (existingUsersResponse != null) {
            userId = existingUsersResponse['id'] as String;
            debugPrint('Found existing user in database: $userId');
          } else {
            // User exists in auth but not in database - this shouldn't happen normally
            // but we'll handle it by trying to sign in to get the user ID
            throw Exception('User exists in auth but not in database. Please contact support.');
          }
        } else {
          rethrow;
        }
      }

      // Step 2: Create or update user record in database
      if (isNewUser) {
        await supabase.from('users').insert({
          'id': userId,
          'name': name,
          'email': email,
          'phone': null,
        });
        debugPrint('Created user record in database');
      } else {
        // Update existing user if needed
        await supabase.from('users').upsert({
          'id': userId,
          'name': name,
          'email': email,
        });
        debugPrint('Updated existing user record');
      }

      // Step 3: Check if user is already assigned to this branch
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
              .update({'role': role.toString().split('.').last})
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
          'role': role.toString().split('.').last,
        });
        debugPrint('Assigned user to branch');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User added successfully'),
          backgroundColor: Colors.green,
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
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _removeUserFromBranch(String branchUserId) async {
    try {
      await Supabase.instance.client
          .from('branch_users')
          .delete()
          .eq('id', branchUserId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User removed from branch'),
          backgroundColor: Colors.green,
        ),
      );

      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton.icon(
                    onPressed: _showAddUserDialog,
                    icon: const Icon(Icons.person_add),
                    label: const Text('Add User to Branch'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      final userData = _users[index];
                      final user = userData['user'] as User;
                      final branches = userData['branches'] as List<Map<String, dynamic>>;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            child: Text(user.name[0].toUpperCase()),
                          ),
                      title: Text(user.name),
                      subtitle: Text(user.email ?? 'No email'),
                          children: branches.map((branchData) {
                            final branch = branchData['branch'] as Branch;
                            final role = branchData['role'] as String;
                            final branchUserId = branchData['branch_user_id'] as String;

                            return ListTile(
                              title: Text(branch.name),
                              subtitle: Text('${branch.location} • ${role.toUpperCase()}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
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
                                            _removeUserFromBranch(branchUserId);
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                          ),
                                          child: const Text('Remove'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

