class NeededFruit {
  const NeededFruit({
    required this.id,
    required this.fruitName,
    required this.quantityNotes,
    this.notes = '',
    this.purchased = false,
    this.purchasedAt,
    this.pricePerKgRupees,
    this.totalWeightKg,
    this.totalCostRupees,
  });

  final String id;
  final String fruitName;
  /// Free text, e.g. "8 kg", "2 crates".
  final String quantityNotes;
  final String notes;
  final bool purchased;
  final DateTime? purchasedAt;
  final double? pricePerKgRupees;
  final double? totalWeightKg;
  final double? totalCostRupees;

  NeededFruit copyWith({
    String? id,
    String? fruitName,
    String? quantityNotes,
    String? notes,
    bool? purchased,
    DateTime? purchasedAt,
    double? pricePerKgRupees,
    double? totalWeightKg,
    double? totalCostRupees,
  }) {
    return NeededFruit(
      id: id ?? this.id,
      fruitName: fruitName ?? this.fruitName,
      quantityNotes: quantityNotes ?? this.quantityNotes,
      notes: notes ?? this.notes,
      purchased: purchased ?? this.purchased,
      purchasedAt: purchasedAt ?? this.purchasedAt,
      pricePerKgRupees: pricePerKgRupees ?? this.pricePerKgRupees,
      totalWeightKg: totalWeightKg ?? this.totalWeightKg,
      totalCostRupees: totalCostRupees ?? this.totalCostRupees,
    );
  }
}
