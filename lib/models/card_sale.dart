class CardSale {
  final String? id;
  final DateTime date;
  final String userId;
  final String branchId;
  final String? cardMachineId; // UUID; rename-safe link to card_machines
  final String tid;
  final String machineName;
  final double amount;
  final String? notes;
  final DateTime? createdAt;

  CardSale({
    this.id,
    required this.date,
    required this.userId,
    required this.branchId,
    this.cardMachineId,
    required this.tid,
    required this.machineName,
    required this.amount,
    this.notes,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'date': date.toIso8601String().split('T')[0],
      'user_id': userId,
      'branch_id': branchId,
      if (cardMachineId != null) 'card_machine_id': cardMachineId,
      'tid': tid,
      'machine_name': machineName,
      'amount': amount,
      'notes': notes,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory CardSale.fromJson(Map<String, dynamic> json) {
    return CardSale(
      id: json['id']?.toString(),
      date: DateTime.parse(json['date']),
      userId: json['user_id']?.toString() ?? '',
      branchId: json['branch_id']?.toString() ?? '',
      cardMachineId: json['card_machine_id']?.toString(),
      tid: json['tid'] ?? '',
      machineName: json['machine_name'] ?? '',
      amount: (json['amount'] as num).toDouble(),
      notes: json['notes'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }
}

class CardMachine {
  final String? id;
  final String name;
  final String tid;
  final String? location;
  final String? branchId;
  final DateTime? createdAt;

  CardMachine({
    this.id,
    required this.name,
    required this.tid,
    this.location,
    this.branchId,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'tid': tid,
      'location': location,
      if (branchId != null) 'branch_id': branchId,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory CardMachine.fromJson(Map<String, dynamic> json) {
    return CardMachine(
      id: json['id']?.toString(),
      name: json['name'] ?? '',
      tid: json['tid'] ?? '',
      location: json['location'],
      branchId: json['branch_id']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }
}

