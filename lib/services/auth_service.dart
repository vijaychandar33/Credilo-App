import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../models/user.dart';
import '../models/branch.dart';
import '../models/branch_user.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  User? _currentUser;
  Branch? _currentBranch;
  List<Branch> _userBranches = [];
  List<BranchUser> _branchUsers = [];
  bool? _isBusinessOwnerCached;

  User? get currentUser => _currentUser;
  Branch? get currentBranch => _currentBranch;
  List<Branch> get userBranches => _userBranches;
  List<BranchUser> get branchUsers => _branchUsers;
  
  UserRole? get currentRole {
    if (_currentUser == null || _currentBranch == null) return null;
    final branchUser = _branchUsers.firstWhere(
      (bu) => bu.branchId == _currentBranch!.id && bu.userId == _currentUser!.id,
      orElse: () => BranchUser(
        id: '',
        branchId: _currentBranch!.id,
        userId: _currentUser!.id,
        role: UserRole.staff,
      ),
    );
    return branchUser.role;
  }

  bool get isAuthenticated {
    return Supabase.instance.client.auth.currentUser != null && _currentUser != null;
  }

  // Set user and branches (called after login/registration)
  Future<void> setUser(User user, List<Branch> branches) async {
    _currentUser = user;
    _userBranches = branches;

    if (branches.isNotEmpty) {
      _currentBranch = branches.first;
    }

    // Load branch user roles - ensure this completes
    if (user.id.isNotEmpty && branches.isNotEmpty) {
      await _loadBranchUsers(user.id);
      debugPrint('Loaded ${_branchUsers.length} branch user records for user ${user.id}');
      if (_branchUsers.isNotEmpty) {
        debugPrint('Branch user roles: ${_branchUsers.map((bu) => '${bu.branchId}: ${bu.role}').join(", ")}');
      }
    }
    
    // Clear business owner cache so it gets refreshed
    _isBusinessOwnerCached = null;
  }

  Future<void> _loadBranchUsers(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('branch_users')
          .select()
          .eq('user_id', userId);

      _branchUsers = (response as List)
          .map((json) => BranchUser.fromJson(json))
          .toList();
      
      debugPrint('Loaded branch_users for $userId: ${_branchUsers.length} records');
      for (var bu in _branchUsers) {
        debugPrint('  - Branch: ${bu.branchId}, Role: ${bu.role}, User: ${bu.userId}');
      }
      
      // If no branch_users found, check if user owns any businesses and create default branch
      if (_branchUsers.isEmpty && _currentUser != null) {
        debugPrint('No branch_users found. Checking if user owns businesses...');
        await _checkAndCreateDefaultBranch(userId);
      }
    } catch (e) {
      debugPrint('Error loading branch users: $e');
      _branchUsers = [];
    }
  }

  Future<void> _checkAndCreateDefaultBranch(String userId) async {
    try {
      // Check if user owns any businesses (using business_owners table)
      final businessOwnersResponse = await Supabase.instance.client
          .from('business_owners')
          .select('business_id')
          .eq('user_id', userId);

      final businessIds = (businessOwnersResponse as List)
          .map((bo) => bo['business_id'] as String)
          .toList();

      if (businessIds.isEmpty) {
        debugPrint('User does not own any businesses');
        return;
      }

      // Get businesses by querying each one individually (since .in_() doesn't work well with RLS)
      final List<dynamic> businesses = [];
      for (var businessId in businessIds) {
        try {
          final businessResponse = await Supabase.instance.client
              .from('businesses')
              .select()
              .eq('id', businessId)
              .maybeSingle();
          if (businessResponse != null) {
            businesses.add(businessResponse);
          }
        } catch (e) {
          debugPrint('Error loading business $businessId: $e');
        }
      }
      
      if (businesses.isNotEmpty) {
        debugPrint('User owns ${businesses.length} business(es). Checking for branches...');
        
        for (var business in businesses) {
          final businessId = business['id'] as String;
          
          // Check if business has any branches
          final branchesResponse = await Supabase.instance.client
              .from('branches')
              .select()
              .eq('business_id', businessId);
          
          final branches = branchesResponse as List;
          
          if (branches.isEmpty) {
            debugPrint('Business ${business['name']} has no branches. Creating default branch...');
            
            // Create a default branch
            try {
              final branchResponse = await Supabase.instance.client
                  .from('branches')
                  .insert({
                    'business_id': businessId,
                    'name': '${business['name']} - Main Branch',
                    'location': 'Main Location',
                    'manager_id': userId,
                    'status': 'active',
                  })
                  .select()
                  .single();
              
              final branch = Branch.fromJson(branchResponse);
              
              // Create branch_user record
              await Supabase.instance.client
                  .from('branch_users')
                  .insert({
                    'branch_id': branch.id,
                    'user_id': userId,
                    'role': 'owner',
                  });
              
              debugPrint('Created default branch and assigned owner role');
              
              // Reload branches and branch_users
              await refreshBranches();
            } catch (e) {
              debugPrint('Error creating default branch: $e');
            }
          } else {
            // Business has branches but no branch_users - assign owner to first branch
            debugPrint('Business has branches but user not assigned. Assigning to first branch...');
            final firstBranch = branches.first;
            
            try {
              await Supabase.instance.client
                  .from('branch_users')
                  .insert({
                    'branch_id': firstBranch['id'],
                    'user_id': userId,
                    'role': 'owner',
                  });
              
              debugPrint('Assigned owner role to existing branch');
              await refreshBranches();
            } catch (e) {
              debugPrint('Error assigning branch_user: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking/creating default branch: $e');
    }
  }

  // Login with email and password (handled in LoginScreen)
  Future<bool> login(String email, String password) async {
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        await _loadUserData(response.user!.id);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Login error: $e');
      return false;
    }
  }

  Future<void> _loadUserData(String userId) async {
    try {
      // Get user from database
      final userResponse = await Supabase.instance.client
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (userResponse != null) {
        final user = User.fromJson(userResponse);
        
        // Get user's branches
        final branchesResponse = await Supabase.instance.client
            .from('branch_users')
            .select('branches(*)')
            .eq('user_id', userId);

        final branches = (branchesResponse as List)
            .where((item) => item['branches'] != null)
            .map((item) => Branch.fromJson(item['branches']))
            .toList();

        await setUser(user, branches);
        // Refresh business owner status
        await refreshBusinessOwnerStatus();
      } else {
        debugPrint('User not found in database: $userId');
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  Future<void> refreshUserData() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId != null) {
      await _loadUserData(currentUserId);
    }
  }

  void setCurrentBranch(Branch branch) {
    _currentBranch = branch;
  }

  Future<void> refreshBranches() async {
    if (_currentUser == null) return;
    
    try {
      final branchesResponse = await Supabase.instance.client
          .from('branch_users')
          .select('branches(*)')
          .eq('user_id', _currentUser!.id);

      final branches = (branchesResponse as List)
          .where((item) => item['branches'] != null)
          .map((item) => Branch.fromJson(item['branches']))
          .toList();

      _userBranches = branches;
      
      if (branches.isNotEmpty && _currentBranch == null) {
        _currentBranch = branches.first;
      } else if (_currentBranch != null) {
        // Update current branch if it still exists
        final updatedBranch = branches.firstWhere(
          (b) => b.id == _currentBranch!.id,
          orElse: () => branches.isNotEmpty ? branches.first : _currentBranch!,
        );
        _currentBranch = updatedBranch;
      }
      
      // Reload branch_users to ensure roles are up to date
      await _loadBranchUsers(_currentUser!.id);
    } catch (e) {
      debugPrint('Error refreshing branches: $e');
    }
  }

  bool canEditDate(DateTime date) {
    final role = currentRole;
    if (role == null) return false;
    
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    final yesterday = todayDateOnly.subtract(const Duration(days: 1));
    
    if (role == UserRole.owner) {
      return true; // Owner can edit any date
    } else if (role == UserRole.manager) {
      return dateOnly == todayDateOnly || dateOnly == yesterday;
    } else if (role == UserRole.staff) {
      return dateOnly == todayDateOnly; // Staff can only edit today
    }
    return false;
  }

  bool canViewDate(DateTime date) {
    final role = currentRole;
    if (role == null) return false;
    
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    final yesterday = todayDateOnly.subtract(const Duration(days: 1));
    
    if (role == UserRole.owner) {
      return true;
    } else if (role == UserRole.manager) {
      return dateOnly == todayDateOnly || dateOnly == yesterday;
    } else if (role == UserRole.staff) {
      return dateOnly == todayDateOnly || dateOnly == yesterday;
    }
    return false;
  }

  bool canDelete() {
    final role = currentRole;
    return role == UserRole.owner || role == UserRole.manager;
  }

  // Check if user is a business owner (owns any business) - cached
  bool isBusinessOwner() {
    if (_currentUser == null) return false;
    if (_isBusinessOwnerCached != null) return _isBusinessOwnerCached!;
    return false; // Will be set by refreshBusinessOwnerStatus
  }

  // Refresh business owner status (call after login/setUser)
  // A user is a business owner if:
  // 1. They are in business_owners table, OR
  // 2. They own a business directly (businesses.owner_id = user.id), OR
  // 3. They are owner of all branches of a business
  Future<void> refreshBusinessOwnerStatus() async {
    if (_currentUser == null) {
      _isBusinessOwnerCached = false;
      return;
    }
    
    try {
      // First check if user is in business_owners table
      try {
        final businessOwnersResponse = await Supabase.instance.client
            .from('business_owners')
            .select()
            .eq('user_id', _currentUser!.id)
            .limit(1);
        
        debugPrint('Business owners query result: ${businessOwnersResponse.length} records');
        
        if ((businessOwnersResponse as List).isNotEmpty) {
          _isBusinessOwnerCached = true;
          debugPrint('User is business owner (in business_owners table)');
          return;
        }
      } catch (e) {
        debugPrint('Error querying business_owners table: $e');
        // Continue to check other methods
      }
      
      // No longer checking owner_id - only using business_owners table
      
      // Check if user is owner of all branches of any business
      // Get all businesses
      final allBusinesses = await Supabase.instance.client
          .from('businesses')
          .select('id');
      
      for (var business in allBusinesses as List) {
        final businessId = business['id'] as String;
        
        // Get all branches for this business
        final branches = await Supabase.instance.client
            .from('branches')
            .select('id')
            .eq('business_id', businessId);
        
        if ((branches as List).isEmpty) continue;
        
        // Check if user is owner of all branches
        bool isOwnerOfAllBranches = true;
        for (var branch in branches) {
          final branchId = branch['id'] as String;
          final branchUser = await Supabase.instance.client
              .from('branch_users')
              .select()
              .eq('branch_id', branchId)
              .eq('user_id', _currentUser!.id)
              .eq('role', 'owner')
              .maybeSingle();
          
          if (branchUser == null) {
            isOwnerOfAllBranches = false;
            break;
          }
        }
        
        if (isOwnerOfAllBranches) {
          _isBusinessOwnerCached = true;
          return;
        }
      }
      
      _isBusinessOwnerCached = false;
    } catch (e) {
      debugPrint('Error checking business ownership: $e');
      _isBusinessOwnerCached = false;
    }
  }

  // Check if user can manage users (only business owners)
  bool canManageUsers() {
    return isBusinessOwner();
  }

  // Check if user is a branch owner (has owner role in at least one branch)
  bool isBranchOwner() {
    if (_currentUser == null) return false;
    return _branchUsers.any((bu) => bu.role == UserRole.owner);
  }

  // Get branches where user is an owner
  List<Branch> get ownerBranches {
    if (_currentUser == null) return [];
    final ownerBranchIds = _branchUsers
        .where((bu) => bu.role == UserRole.owner)
        .map((bu) => bu.branchId)
        .toList();
    return _userBranches.where((b) => ownerBranchIds.contains(b.id)).toList();
  }

  // Async version to check if user is business owner
  // Uses the same logic as refreshBusinessOwnerStatus
  Future<bool> isBusinessOwnerAsync() async {
    if (_currentUser == null) return false;
    
    // If cached, return cached value
    if (_isBusinessOwnerCached != null) return _isBusinessOwnerCached!;
    
    // Otherwise refresh and return
    await refreshBusinessOwnerStatus();
    return _isBusinessOwnerCached ?? false;
  }

  bool canViewAllBranches() {
    return currentRole == UserRole.owner;
  }

  Future<void> logout() async {
    await Supabase.instance.client.auth.signOut();
    _currentUser = null;
    _currentBranch = null;
    _userBranches = [];
    _branchUsers = [];
    _isBusinessOwnerCached = null;
  }

  // Check if user is logged in on app start
  Future<bool> checkAuth() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      await _loadUserData(session.user.id);
      return true;
    }
    return false;
  }
}
