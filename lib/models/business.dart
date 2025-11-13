class Business {
  final String id;
  final String name;
  final String ownerId;
  final DateTime? createdAt;

  Business({
    required this.id,
    required this.name,
    required this.ownerId,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'owner_id': ownerId,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory Business.fromJson(Map<String, dynamic> json) {
    return Business(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      ownerId: json['owner_id']?.toString() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }
}

