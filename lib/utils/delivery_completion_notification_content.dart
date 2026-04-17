import '../models/delivery_completion_event.dart';
import '../models/delivery_slot.dart';

/// Returns `null` when [events] is empty.
({String title, String body})? deliveryCompletionNotificationContent(
  List<DeliveryCompletionEvent> events,
) {
  if (events.isEmpty) return null;
  if (events.length == 1) {
    final e = events.first;
    if (e.kind == 'mark_all') {
      final n = e.completedCount ?? 0;
      return (
        title: 'Route marked complete',
        body: '${e.slot.label}: $n stops · ${e.markedBy}',
      );
    }
    return (
      title: 'Delivery completed',
      body: '${e.customerName} · ${e.slot.label} · ${e.markedBy}',
    );
  }
  final title = '${events.length} delivery updates';
  final names = events
      .map((e) => e.customerName.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  var body = names.isEmpty
      ? 'Open the app to view'
      : names.take(3).join(', ');
  if (names.length > 3) body = '$body…';
  return (title: title, body: body);
}
