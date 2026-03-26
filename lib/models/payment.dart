enum PaymentStatus { pending, paid }

/// Scheduled collection type (weekly full / monthly advance / monthly balance).
enum PaymentCollectionKind {
  weeklyFull,
  monthlyAdvance,
  monthlyBalance,
}

class Payment {
  const Payment({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.amount,
    required this.dueLabel,
    this.kind,
    this.status = PaymentStatus.pending,
  });

  final String id;
  final String customerId;
  final String customerName;
  final double amount;
  final String dueLabel;
  /// Set when derived from [paymentDueForCustomer].
  final PaymentCollectionKind? kind;
  final PaymentStatus status;
}
