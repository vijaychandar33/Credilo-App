enum DueType { receivable, payable }
enum DueStatus { open, partiallyPaid, paid }

class Due {
  final String? id;
  final DateTime date;
  final String userId;
  final String branchId;
  final String party;
  final double amount;
  final DateTime dueDate;
  final DueType type;
  final DueStatus status;
  final String? remarks;
  final DateTime? createdAt;

  Due({
    this.id,
    required this.date,
    required this.userId,
    required this.branchId,
    required this.party,
    required this.amount,
    required this.dueDate,
    required this.type,
    required this.status,
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
      'due_date': dueDate.toIso8601String().split('T')[0],
      'type': type == DueType.receivable ? 'receivable' : 'payable',
      'status': status == DueStatus.open
          ? 'open'
          : status == DueStatus.partiallyPaid
              ? 'partially_paid'
              : 'paid',
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
      dueDate: DateTime.parse(json['due_date']),
      type: json['type'] == 'receivable'
          ? DueType.receivable
          : DueType.payable,
      status: json['status'] == 'open'
          ? DueStatus.open
          : json['status'] == 'partially_paid'
              ? DueStatus.partiallyPaid
              : DueStatus.paid,
      remarks: json['remarks'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }
}

