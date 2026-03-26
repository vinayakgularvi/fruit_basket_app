enum DeliverySlot {
  morning,
  evening,
}

extension DeliverySlotLabel on DeliverySlot {
  String get label => switch (this) {
        DeliverySlot.morning => 'Morning',
        DeliverySlot.evening => 'Evening',
      };
}
