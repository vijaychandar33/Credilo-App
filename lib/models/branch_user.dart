import 'user.dart';

class BranchUser {
  final String id;
  final String branchId;
  final String userId;
  final String? businessId;
  final UserRole role;
  final Map<String, dynamic>? permissions;
  final DateTime? createdAt;

  BranchUser({
    required this.id,
    required this.branchId,
    required this.userId,
    this.businessId,
    required this.role,
    this.permissions,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    // Convert camelCase enum to snake_case for database
    String roleToDbString(UserRole role) {
      final camelCase = role.toString().split('.').last;
      // Convert camelCase to snake_case
      return camelCase.replaceAllMapped(
        RegExp(r'([A-Z])'),
        (match) => '_${match.group(1)!.toLowerCase()}',
      );
    }
    
    return {
      'id': id,
      'branch_id': branchId,
      'user_id': userId,
      if (businessId != null) 'business_id': businessId,
      'role': roleToDbString(role),
      'permissions': permissions,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory BranchUser.fromJson(Map<String, dynamic> json) {
    // Map database role string to enum
    // Database uses snake_case (business_owner), enum uses camelCase (businessOwner)
    UserRole parseRole(String? roleStr) {
      if (roleStr == null || roleStr.isEmpty) return UserRole.staff;
      
      // Convert snake_case to camelCase for matching
      String camelCase = roleStr.split('_').map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
      }).join();
      if (camelCase.isEmpty) return UserRole.staff;
      camelCase = camelCase[0].toLowerCase() + camelCase.substring(1);
      
      // Try to find matching enum value
      try {
        return UserRole.values.firstWhere(
          (e) => e.toString().split('.').last == camelCase,
        );
      } catch (e) {
        return UserRole.staff;
      }
    }
    
    return BranchUser(
      id: json['id']?.toString() ?? '',
      branchId: json['branch_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      businessId: json['business_id']?.toString(),
      role: parseRole(json['role']?.toString()),
      permissions: json['permissions'] as Map<String, dynamic>?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }
}

