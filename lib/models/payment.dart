enum PaymentStatus { pending, paid }

class Payment {
  const Payment({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.amount,
    required this.dueLabel,
    this.status = PaymentStatus.pending,
  });

  final String id;
  final String customerId;
  final String customerName;
  final double amount;
  final String dueLabel;
  final PaymentStatus status;
}
