class Supplier {
  final String? id;
  final String name;
  final String? contact;
  final String? address;
  final String businessId;
  /// Branch IDs this supplier supplies to. Null or empty = supplies to all branches.
  final List<String>? supplyingBranchIds;
  final DateTime? createdAt;

  Supplier({
    this.id,
    required this.name,
    this.contact,
    this.address,
    required this.businessId,
    this.supplyingBranchIds,
    this.createdAt,
  });

  /// True if this supplier supplies to all branches (no restriction).
  bool get suppliesToAllBranches =>
      supplyingBranchIds == null || supplyingBranchIds!.isEmpty;

  /// True if this supplier supplies to [branchId].
  bool suppliesToBranch(String branchId) {
    if (suppliesToAllBranches) return true;
    return supplyingBranchIds!.contains(branchId);
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'contact': contact,
      'address': address,
      'business_id': businessId,
      if (supplyingBranchIds != null && supplyingBranchIds!.isNotEmpty)
        'supplying_branch_ids': supplyingBranchIds,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory Supplier.fromJson(Map<String, dynamic> json) {
    List<String>? branchIds;
    final raw = json['supplying_branch_ids'];
    if (raw != null && raw is List && raw.isNotEmpty) {
      branchIds = raw.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
      if (branchIds.isEmpty) branchIds = null;
    }
    return Supplier(
      id: json['id']?.toString(),
      name: json['name'] ?? '',
      contact: json['contact'],
      address: json['address'],
      businessId: json['business_id']?.toString() ?? '',
      supplyingBranchIds: branchIds,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }
}

