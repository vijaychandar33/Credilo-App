class OnlineSale {
  final String? id;
  final DateTime date;
  final String userId;
  final String branchId;
  final String? platformId; // UUID; rename-safe link to online_sales_platforms
  final String platform;
  final double gross;
  final double? commission;
  final double net;
  final String? notes;
  final DateTime? createdAt;

  OnlineSale({
    this.id,
    required this.date,
    required this.userId,
    required this.branchId,
    this.platformId,
    required this.platform,
    required this.gross,
    this.commission,
    required this.net,
    this.notes,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'date': date.toIso8601String().split('T')[0],
      'user_id': userId,
      'branch_id': branchId,
      if (platformId != null) 'platform_id': platformId,
      'platform': platform,
      'gross': gross,
      'commission': commission,
      'net': net,
      'notes': notes,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory OnlineSale.fromJson(Map<String, dynamic> json) {
    return OnlineSale(
      id: json['id']?.toString(),
      date: DateTime.parse(json['date']),
      userId: json['user_id']?.toString() ?? '',
      branchId: json['branch_id']?.toString() ?? '',
      platformId: json['platform_id']?.toString(),
      platform: json['platform'] ?? '',
      gross: (json['gross'] as num).toDouble(),
      commission: json['commission'] != null
          ? (json['commission'] as num).toDouble()
          : null,
      net: (json['net'] as num).toDouble(),
      notes: json['notes'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }
}

