class OnlineSalesPlatform {
  final String? id;
  final String branchId;
  final String name;
  final DateTime? createdAt;

  OnlineSalesPlatform({
    this.id,
    required this.branchId,
    required this.name,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'branch_id': branchId,
      'name': name,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory OnlineSalesPlatform.fromJson(Map<String, dynamic> json) {
    return OnlineSalesPlatform(
      id: json['id']?.toString(),
      branchId: json['branch_id']?.toString() ?? '',
      name: json['name'] ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }
}
