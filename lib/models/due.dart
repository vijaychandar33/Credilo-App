enum DueType { receivable, payable }
enum DueStatus { open, partiallyPaid, paid }

class Due {
  final String? id;
  final DateTime date;
  final String userId;
  final String branchId;
  final String party;
  final double amount;
  final DueType type;
  final String? remarks;
  final DateTime? createdAt;

  Due({
    this.id,
    required this.date,
    required this.userId,
    required this.branchId,
    required this.party,
    required this.amount,
    required this.type,
    this.remarks,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'date': date.toIso8601String().split('T')[0],
      'user_id': userId,
      'branch_id': branchId,
      'party': party,
      'amount': amount,
      'type': type == DueType.receivable ? 'receivable' : 'payable',
      'remarks': remarks,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory Due.fromJson(Map<String, dynamic> json) {
    return Due(
      id: json['id']?.toString(),
      date: DateTime.parse(json['date']),
      userId: json['user_id']?.toString() ?? '',
      branchId: json['branch_id']?.toString() ?? '',
      party: json['party'] ?? '',
      amount: (json['amount'] as num).toDouble(),
      type: json['type'] == 'receivable'
          ? DueType.receivable
          : DueType.payable,
      remarks: json['remarks'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }
}

