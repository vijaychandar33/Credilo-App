enum UserRole { owner, manager, staff }

class User {
  final String id;
  final String name;
  final String? phone;
  final String? email;
  final UserRole? role;
  final DateTime? createdAt;

  User({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.role,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'role': role?.toString().split('.').last,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      phone: json['phone'],
      email: json['email'],
      role: json['role'] != null
          ? UserRole.values.firstWhere(
              (e) => e.toString().split('.').last == json['role'],
              orElse: () => UserRole.staff,
            )
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }
}

