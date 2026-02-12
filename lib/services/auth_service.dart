import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../models/user.dart';
import '../models/branch.dart';
import '../models/branch_user.dart';
import '../utils/closing_cycle_service.dart';
import 'database_service.dart';

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
      
      // Check if custom closing should be auto-enabled based on existing data
      await _checkAndAutoEnableCustomClosing(branches);
    }
    
    // Clear business owner cache so it gets refreshed
    _isBusinessOwnerCached = null;
  }

  /// For each branch with after-midnight UPI data, auto-enable that branch's custom closing cycle.
  Future<void> _checkAndAutoEnableCustomClosing(List<Branch> branches) async {
    try {
      final dbService = DatabaseService();
      for (final branch in branches) {
        final hasData = await dbService.hasDataAfterMidnight([branch.id]);
        if (!hasData) continue;
        final isEnabled = await ClosingCycleService.isCustomClosingEnabled(branch.id);
        if (!isEnabled) {
          debugPrint('Auto-enabling custom closing for branch ${branch.id} due to after-midnight data');
          await ClosingCycleService.setCustomClosingEnabled(branch.id, true);
          final hour = await ClosingCycleService.getClosingHour(branch.id);
          if (hour == 0) {
            await ClosingCycleService.setClosingTime(branch.id, 1, 0);
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking for auto-enable custom closing: $e');
    }
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
      // Check if user is a business owner (has business_owner role in any branch_users record)
      final businessOwnerRecords = await Supabase.instance.client
          .from('branch_users')
          .select('business_id')
          .eq('user_id', userId)
          .eq('role', 'business_owner');

      if ((businessOwnerRecords as List).isEmpty) {
        debugPrint('User is not a business owner');
        return;
      }

      // Get unique business IDs
      final Set<String> businessIds = (businessOwnerRecords as List)
          .map((r) => r['business_id'] as String)
          .toSet();

      // Get businesses by querying each one individually
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
        debugPrint('User is business owner of ${businesses.length} business(es). Checking for branches...');
        
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
                    'status': 'active',
                  })
                  .select()
                  .single();
              
              final branch = Branch.fromJson(branchResponse);
              
              // Create branch_user record with business_owner role
              await Supabase.instance.client
                  .from('branch_users')
                  .insert({
                    'branch_id': branch.id,
                    'user_id': userId,
                    'business_id': businessId,
                    'role': 'business_owner',
                  });
              
              debugPrint('Created default branch and assigned business_owner role');
              
              // Reload branches and branch_users
              await refreshBranches();
            } catch (e) {
              debugPrint('Error creating default branch: $e');
            }
          } else {
            // Business has branches - check if user is assigned to all of them
            // If not, assign business_owner role to missing branches
            debugPrint('Business has ${branches.length} branch(es). Checking assignments...');
            
            for (var branch in branches) {
              final branchId = branch['id'] as String;
              
              final existingAssignment = await Supabase.instance.client
                  .from('branch_users')
                  .select()
                  .eq('user_id', userId)
                  .eq('branch_id', branchId)
                  .maybeSingle();
              
              if (existingAssignment == null) {
                // User not assigned to this branch, assign business_owner role
                try {
                  await Supabase.instance.client
                      .from('branch_users')
                      .insert({
                        'branch_id': branchId,
                        'user_id': userId,
                        'business_id': businessId,
                        'role': 'business_owner',
                      });
                  
                  debugPrint('Assigned business_owner role to branch ${branch['name']}');
                } catch (e) {
                  debugPrint('Error assigning branch_user: $e');
                }
              }
            }
            
            await refreshBranches();
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
          
          // Get all branches for these businesses
          for (var bid in businessIds) {
            final allBranchesResponse = await Supabase.instance.client
                .from('branches')
                .select()
                .eq('business_id', bid);
            
            final businessBranches = (allBranchesResponse as List)
                .map((json) => Branch.fromJson(json))
                .toList();
            
            branches.addAll(businessBranches);
          }
        } else {
          // Regular user: get only assigned branches
          final branchesResponse = await Supabase.instance.client
            .from('branch_users')
            .select('branches(*)')
            .eq('user_id', userId);

          branches = (branchesResponse as List)
            .where((item) => item['branches'] != null)
            .map((item) => Branch.fromJson(item['branches']))
            .toList();
        }

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

  Future<bool> canEditDate(DateTime date) async {
    final role = currentRole;
    if (role == null) return false;
    
    // Business owner read-only and owner read-only cannot edit any date
    if (role == UserRole.businessOwnerReadOnly || role == UserRole.ownerReadOnly) {
      return false;
    }
    
    final branchId = currentBranch?.id ?? '';
    final businessDate = branchId.isEmpty
        ? DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
        : await ClosingCycleService.getBusinessDate(branchId);
    final businessDateOnly = DateTime(businessDate.year, businessDate.month, businessDate.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    final yesterday = businessDateOnly.subtract(const Duration(days: 1));
    
    if (role == UserRole.businessOwner || role == UserRole.owner) {
      return true; // Business owner & owner can edit any date
    } else if (role == UserRole.manager) {
      return dateOnly == businessDateOnly || dateOnly == yesterday;
    } else if (role == UserRole.staff) {
      return dateOnly == businessDateOnly || dateOnly == yesterday; // Staff can edit today and yesterday
    }
    return false;
  }

  Future<bool> canViewDate(DateTime date) async {
    final role = currentRole;
    if (role == null) return false;
    
    final branchId = currentBranch?.id ?? '';
    final businessDate = branchId.isEmpty
        ? DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
        : await ClosingCycleService.getBusinessDate(branchId);
    final businessDateOnly = DateTime(businessDate.year, businessDate.month, businessDate.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    final yesterday = businessDateOnly.subtract(const Duration(days: 1));
    
    if (role == UserRole.businessOwner || role == UserRole.businessOwnerReadOnly || role == UserRole.owner || role == UserRole.ownerReadOnly) {
      return true; // Business owner, business owner read-only, owner & owner read-only can view any date
    } else if (role == UserRole.manager) {
      return dateOnly == businessDateOnly || dateOnly == yesterday;
    } else if (role == UserRole.staff) {
      return dateOnly == businessDateOnly || dateOnly == yesterday;
    }
    return false;
  }

  bool canDelete() {
    final role = currentRole;
    // Business owner read-only and owner read-only cannot delete
    if (role == UserRole.businessOwnerReadOnly || role == UserRole.ownerReadOnly) {
      return false;
    }
    return role == UserRole.businessOwner || role == UserRole.owner || role == UserRole.manager;
  }

  // Check if user is a business owner (owns any business) - cached
  bool isBusinessOwner() {
    if (_currentUser == null) return false;
    if (_isBusinessOwnerCached != null) return _isBusinessOwnerCached!;
    return false; // Will be set by refreshBusinessOwnerStatus
  }

  // Refresh business owner status (call after login/setUser)
  // A user is a business owner if they have business_owner role in any branch_users record
  Future<void> refreshBusinessOwnerStatus() async {
    if (_currentUser == null) {
      _isBusinessOwnerCached = false;
      return;
    }
    
    try {
      // Check if user has business_owner role in any branch_users record
      _isBusinessOwnerCached = _branchUsers.any((bu) => bu.role == UserRole.businessOwner);
      
      if (_isBusinessOwnerCached == true) {
        debugPrint('User is business owner');
      } else {
        debugPrint('User is not a business owner');
      }
    } catch (e) {
      debugPrint('Error checking business ownership: $e');
      _isBusinessOwnerCached = false;
    }
  }

  /// Same access as Card Machine Management: business owner and owner (not read-only).
  /// Use for both Card Management and UPI Management screens.
  bool canAccessCardOrUpiManagement() {
    return canManageUsers();
  }

  /// True only for the current branch: show Card/UPI/Online Sales management icon in app bar
  /// when user is owner or business owner of this branch (not manager/staff, not read-only).
  bool get canAccessManagementInCurrentBranch {
    final role = currentRole;
    if (role == null) return false;
    return role == UserRole.owner || role == UserRole.businessOwner;
  }

  // Check if user can manage users (business owners and owners, but not read-only)
  bool canManageUsers() {
    if (_currentUser == null) return false;

    // Fast-path: current branch role already tells us
    final role = currentRole;
    // Business owner read-only and owner read-only cannot manage users
    if (role == UserRole.businessOwnerReadOnly || role == UserRole.ownerReadOnly) {
      return false;
    }
    if (role == UserRole.businessOwner || role == UserRole.owner) {
      return true;
    }

    // If branch assignments are still loading, fall back to cached ownership flag
    if (_branchUsers.isEmpty) {
      return _isBusinessOwnerCached ?? false;
    }

    // Otherwise rely on the full branch assignments list
    return _branchUsers.any(
      (bu) => bu.role == UserRole.businessOwner || bu.role == UserRole.owner || bu.role == UserRole.ownerReadOnly,
    );
  }

  // Check if user is a branch owner (has owner or business_owner role in at least one branch)
  bool isBranchOwner() {
    if (_currentUser == null) return false;
    return _branchUsers.any((bu) => 
      bu.role == UserRole.owner || 
      bu.role == UserRole.ownerReadOnly ||
      bu.role == UserRole.businessOwner || 
      bu.role == UserRole.businessOwnerReadOnly
    );
  }

  // Get branches where user is an owner or business owner (including read-only)
  List<Branch> get ownerBranches {
    if (_currentUser == null) return [];
    final ownerBranchIds = _branchUsers
        .where((bu) => 
          bu.role == UserRole.owner || 
          bu.role == UserRole.ownerReadOnly ||
          bu.role == UserRole.businessOwner || 
          bu.role == UserRole.businessOwnerReadOnly
        )
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
    return currentRole == UserRole.businessOwner || 
           currentRole == UserRole.businessOwnerReadOnly || 
           currentRole == UserRole.owner ||
           currentRole == UserRole.ownerReadOnly;
  }

  // Check if user is read-only (cannot edit or delete)
  bool isReadOnly() {
    final role = currentRole;
    return role == UserRole.businessOwnerReadOnly || role == UserRole.ownerReadOnly;
  }

  // Check if user is a business owner (including read-only) - for UI access purposes
  bool isBusinessOwnerOrReadOnly() {
    if (_currentUser == null) return false;
    return _branchUsers.any((bu) => 
      bu.role == UserRole.businessOwner || 
      bu.role == UserRole.businessOwnerReadOnly
    );
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
