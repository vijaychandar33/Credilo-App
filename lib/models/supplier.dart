class Supplier {
  final String? id;
  final String name;
  final String? contact;
  final String? address;
  final String businessId;
  final DateTime? createdAt;

  Supplier({
    this.id,
    required this.name,
    this.contact,
    this.address,
    required this.businessId,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'contact': contact,
      'address': address,
      'business_id': businessId,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: json['id']?.toString(),
      name: json['name'] ?? '',
      contact: json['contact'],
      address: json['address'],
      businessId: json['business_id']?.toString() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }
}

