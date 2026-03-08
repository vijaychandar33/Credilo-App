class UpiProvider {
  final String? id;
  final String branchId;
  final String name;
  final String? location;
  final DateTime? createdAt;

  UpiProvider({
    this.id,
    required this.branchId,
    required this.name,
    this.location,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'branch_id': branchId,
      'name': name,
      'location': location,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory UpiProvider.fromJson(Map<String, dynamic> json) {
    return UpiProvider(
      id: json['id']?.toString(),
      branchId: json['branch_id']?.toString() ?? '',
      name: json['name'] ?? '',
      location: json['location']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }
}
