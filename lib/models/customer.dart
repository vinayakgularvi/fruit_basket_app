import 'delivery_slot.dart';

class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.preferredSlot,
    this.active = true,
    this.notes = '',
  });

  final String id;
  final String name;
  final String phone;
  final String address;
  final DeliverySlot preferredSlot;
  final bool active;
  final String notes;

  Customer copyWith({
    String? id,
    String? name,
    String? phone,
    String? address,
    DeliverySlot? preferredSlot,
    bool? active,
    String? notes,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      preferredSlot: preferredSlot ?? this.preferredSlot,
      active: active ?? this.active,
      notes: notes ?? this.notes,
    );
  }
}
