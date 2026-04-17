import 'package:cloud_firestore/cloud_firestore.dart';

import 'delivery_slot.dart';

/// Firestore `delivery_completion_events` document (today’s completions).
class DeliveryCompletionEvent {
  const DeliveryCompletionEvent({
    required this.id,
    required this.kind,
    required this.customerName,
    required this.slot,
    required this.markedBy,
    required this.markedByRole,
    this.completedCount,
  });

  final String id;
  /// `stop` or `mark_all`
  final String kind;
  final String customerName;
  final DeliverySlot slot;
  final String markedBy;
  final String markedByRole;
  final int? completedCount;

  static DeliverySlot? _slotFromName(String? raw) {
    if (raw == null) return null;
    for (final s in DeliverySlot.values) {
      if (s.name == raw) return s;
    }
    return null;
  }

  static DeliveryCompletionEvent? fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final data = d.data();
    if (data == null) return null;
    final slot = _slotFromName(data['slot'] as String?);
    if (slot == null) return null;
    return DeliveryCompletionEvent(
      id: d.id,
      kind: data['kind'] as String? ?? 'stop',
      customerName: data['customerName'] as String? ?? '',
      slot: slot,
      markedBy: data['markedBy'] as String? ?? '',
      markedByRole: data['markedByRole'] as String? ?? '',
      completedCount: data['completedCount'] as int?,
    );
  }
}
