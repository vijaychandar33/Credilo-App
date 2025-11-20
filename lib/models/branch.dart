enum BranchStatus { active, inactive }

class Branch {
  final String id;
  final String businessId;
  final String name;
  final String location;
  final BranchStatus status;
  final DateTime? createdAt;

  Branch({
    required this.id,
    required this.businessId,
    required this.name,
    required this.location,
    required this.status,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_id': businessId,
      'name': name,
      'location': location,
      'status': status == BranchStatus.active ? 'active' : 'inactive',
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory Branch.fromJson(Map<String, dynamic> json) {
    return Branch(
      id: json['id']?.toString() ?? '',
      businessId: json['business_id']?.toString() ?? '',
      name: json['name'] ?? '',
      location: json['location'] ?? '',
      status: json['status'] == 'active'
          ? BranchStatus.active
          : BranchStatus.inactive,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }
}

