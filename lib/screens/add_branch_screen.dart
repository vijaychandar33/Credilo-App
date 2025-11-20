import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
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

      // Get user's business (user must own all branches of a business)
      // Find businesses where user owns all branches
      String? businessId;
      final allBusinessesResponse = await Supabase.instance.client
          .from('businesses')
          .select('id');
      
      for (var biz in allBusinessesResponse as List) {
        final bid = biz['id'] as String;
        
        // Check if user is a business owner of this business
        final businessOwnerCheck = await Supabase.instance.client
            .from('branch_users')
            .select()
            .eq('user_id', currentUser.id)
            .eq('business_id', bid)
            .eq('role', 'business_owner')
            .limit(1)
            .maybeSingle();
        
        if (businessOwnerCheck != null) {
          businessId = bid;
          break;
        }
      }

      if (businessId == null) {
        throw Exception('Business not found. You must be a business owner to add branches.');
      }

      final supabase = Supabase.instance.client;

      // Create branch
      final branchResponse = await supabase
          .from('branches')
          .insert({
            'business_id': businessId,
            'name': _nameController.text.trim(),
            'location': _locationController.text.trim(),
            'status': 'active',
          })
          .select()
          .single();

      final branch = Branch.fromJson(branchResponse);

      // Note: Database trigger will automatically assign all business owners to the new branch
      // But we'll also do it here as a backup to ensure it works
      // Fetch all distinct business owners for this business
      final ownersResponse = await supabase
          .from('branch_users')
          .select('user_id')
          .eq('business_id', businessId)
          .eq('role', 'business_owner');

      final ownerIds = (ownersResponse as List)
          .map((record) => record['user_id'] as String?)
          .whereType<String>()
          .toSet();

      // Ensure current user is included
      ownerIds.add(currentUser.id);

      // Assign every business owner to the new branch as business_owner
      // (Database trigger should handle this, but this ensures it works)
      for (final ownerId in ownerIds) {
        try {
          await supabase.from('branch_users').upsert(
            {
              'branch_id': branch.id,
              'user_id': ownerId,
              'business_id': businessId,
              'role': 'business_owner',
            },
            onConflict: 'branch_id,user_id',
          );
        } catch (e) {
          debugPrint('Error assigning business owner $ownerId to new branch ${branch.id}: $e');
        }
      }

      // Refresh branches in auth service
      await authService.refreshBranches();
      authService.setCurrentBranch(branch);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Branch added successfully'),
            backgroundColor: AppColors.success,
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
            backgroundColor: AppColors.error,
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

