import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../models/branch.dart';
import '../services/auth_service.dart';

class AddBranchScreen extends StatefulWidget {
  const AddBranchScreen({super.key});

  @override
  State<AddBranchScreen> createState() => _AddBranchScreenState();
}

class _AddBranchScreenState extends State<AddBranchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _addBranch() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = AuthService();
      final currentUser = authService.currentUser;
      if (currentUser == null) {
        throw Exception('User not logged in');
      }

      // Get user's business from business_owners table
      final businessOwnerResponse = await Supabase.instance.client
          .from('business_owners')
          .select('business_id, businesses(*)')
          .eq('user_id', currentUser.id)
          .limit(1)
          .maybeSingle();

      if (businessOwnerResponse == null || businessOwnerResponse['businesses'] == null) {
        throw Exception('Business not found. You must be a business owner to add branches.');
      }
      
      final businessResponse = businessOwnerResponse['businesses'];

      final businessId = businessResponse['id'] as String;

      // Create branch
      final branchResponse = await Supabase.instance.client
          .from('branches')
          .insert({
            'business_id': businessId,
            'name': _nameController.text.trim(),
            'location': _locationController.text.trim(),
            'manager_id': currentUser.id,
            'status': 'active',
          })
          .select()
          .single();

      final branch = Branch.fromJson(branchResponse);

      // Assign current user as owner to the branch
      await Supabase.instance.client.from('branch_users').insert({
        'branch_id': branch.id,
        'user_id': currentUser.id,
        'role': 'owner',
      });

      // Refresh branches in auth service
      await authService.refreshBranches();
      authService.setCurrentBranch(branch);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Branch added successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, branch);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Branch'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
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
                  controller: _locationController,
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
                const SizedBox(height: 32),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _addBranch,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Add Branch'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

