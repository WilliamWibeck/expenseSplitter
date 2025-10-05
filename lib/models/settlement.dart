import 'package:flutter/foundation.dart';

@immutable
class GroupSettlement {
  const GroupSettlement({
    required this.id,
    required this.groupId,
    required this.initiatedBy,
    required this.createdAt,
    required this.payments,
    this.completedAt,
  });

  final String id;
  final String groupId;
  final String initiatedBy; // User ID who started the settlement
  final DateTime createdAt;
  final List<SettlementPayment> payments;
  final DateTime? completedAt;

  bool get isComplete => payments.every((p) => p.isCompleted);
  int get completedCount => payments.where((p) => p.isCompleted).length;
  int get totalCount => payments.length;
  
  Map<String, Object?> toJson() => {
    'groupId': groupId,
    'initiatedBy': initiatedBy,
    'createdAtMs': createdAt.millisecondsSinceEpoch,
    'payments': payments.map((p) => p.toJson()).toList(),
    'completedAtMs': completedAt?.millisecondsSinceEpoch,
  };

  static GroupSettlement fromDoc(String id, Map<String, Object?> data) {
    final paymentsData = data['payments'] as List<dynamic>? ?? [];
    final payments = paymentsData
        .map((p) => SettlementPayment.fromJson(p as Map<String, dynamic>))
        .toList();
    
    return GroupSettlement(
      id: id,
      groupId: data['groupId'] as String? ?? '',
      initiatedBy: data['initiatedBy'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (data['createdAtMs'] as num?)?.toInt() ?? 0,
      ),
      payments: payments,
      completedAt: data['completedAtMs'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (data['completedAtMs'] as num).toInt(),
            )
          : null,
    );
  }
}

@immutable
class SettlementPayment {
  const SettlementPayment({
    required this.debtorId,
    required this.creditorId,
    required this.amountCents,
    this.isCompleted = false,
    this.completedAt,
    this.completedBy,
    this.paymentMethod,
    this.notes,
  });

  final String debtorId;
  final String creditorId;
  final int amountCents;
  final bool isCompleted;
  final DateTime? completedAt;
  final String? completedBy; // Who marked it as complete (debtor, creditor, or system)
  final String? paymentMethod; // 'swish', 'manual', 'game', etc.
  final String? notes;

  SettlementPayment copyWith({
    bool? isCompleted,
    DateTime? completedAt,
    String? completedBy,
    String? paymentMethod,
    String? notes,
  }) {
    return SettlementPayment(
      debtorId: debtorId,
      creditorId: creditorId,
      amountCents: amountCents,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      completedBy: completedBy ?? this.completedBy,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
    );
  }

  Map<String, Object?> toJson() => {
    'debtorId': debtorId,
    'creditorId': creditorId,
    'amountCents': amountCents,
    'isCompleted': isCompleted,
    'completedAtMs': completedAt?.millisecondsSinceEpoch,
    'completedBy': completedBy,
    'paymentMethod': paymentMethod,
    'notes': notes,
  };

  static SettlementPayment fromJson(Map<String, dynamic> data) {
    return SettlementPayment(
      debtorId: data['debtorId'] as String? ?? '',
      creditorId: data['creditorId'] as String? ?? '',
      amountCents: (data['amountCents'] as num?)?.toInt() ?? 0,
      isCompleted: data['isCompleted'] as bool? ?? false,
      completedAt: data['completedAtMs'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (data['completedAtMs'] as num).toInt(),
            )
          : null,
      completedBy: data['completedBy'] as String?,
      paymentMethod: data['paymentMethod'] as String?,
      notes: data['notes'] as String?,
    );
  }
}