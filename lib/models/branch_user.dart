import 'user.dart';

class BranchUser {
  final String id;
  final String branchId;
  final String userId;
  final UserRole role;
  final Map<String, dynamic>? permissions;
  final DateTime? createdAt;

  BranchUser({
    required this.id,
    required this.branchId,
    required this.userId,
    required this.role,
    this.permissions,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'branch_id': branchId,
      'user_id': userId,
      'role': role.toString().split('.').last,
      'permissions': permissions,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory BranchUser.fromJson(Map<String, dynamic> json) {
    return BranchUser(
      id: json['id']?.toString() ?? '',
      branchId: json['branch_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      role: UserRole.values.firstWhere(
        (e) => e.toString().split('.').last == json['role'],
        orElse: () => UserRole.staff,
      ),
      permissions: json['permissions'] as Map<String, dynamic>?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }
}

