import '../models/customer.dart';

enum DeliveryListSort { byRequestedTime, byOptimizedRoute }

void sortDeliveryCustomers(List<Customer> list, DeliveryListSort sort) {
  switch (sort) {
    case DeliveryListSort.byRequestedTime:
      list.sort(compareCustomersByRequestedTime);
    case DeliveryListSort.byOptimizedRoute:
      // Real order comes from [optimizeDeliveryRoute] on the delivery screen.
      list.sort((a, b) => a.name.compareTo(b.name));
  }
}

/// Parses [requestedDeliveryTime] (e.g. "8–10 AM", "9:30 PM") for route order.
/// Uses the **earliest** time token in the string (all preset windows use the
/// start of the first range). Unparseable or empty sorts after known times.
int requestedDeliveryTimeSortKey(String requestedDeliveryTime) {
  var s = requestedDeliveryTime.trim().toLowerCase();
  if (s.isEmpty) return 1 << 20;

  // UI presets use Unicode en-dash (–) between times.
  s = s.replaceAll(RegExp(r'[–—]'), '-');

  final rx = RegExp(r'(\d{1,2})\s*(?::(\d{2}))?');
  var best = 24 * 60;
  var found = false;
  for (final m in rx.allMatches(s)) {
    found = true;
    var hour = int.tryParse(m.group(1) ?? '') ?? 12;
    var minute = int.tryParse(m.group(2) ?? '') ?? 0;
    hour = hour.clamp(0, 23);
    minute = minute.clamp(0, 59);

    final after = m.end < s.length ? s.substring(m.end) : '';
    final chunk = after.length > 14 ? after.substring(0, 14) : after;
    final isPm = chunk.contains('pm');
    final isAm = chunk.contains('am');
    if (isPm && hour < 12) hour += 12;
    if (isAm && hour == 12) hour = 0;

    if (!isPm && !isAm) {
      if (hour >= 1 && hour <= 11) {
        if (s.contains('evening') || s.contains('night')) hour += 12;
      }
    }

    final mins = hour * 60 + minute;
    if (mins < best) best = mins;
  }

  if (!found) return (1 << 20) - 1;
  return best;
}

int compareCustomersByRequestedTime(Customer a, Customer b) {
  final ka = requestedDeliveryTimeSortKey(a.requestedDeliveryTime);
  final kb = requestedDeliveryTimeSortKey(b.requestedDeliveryTime);
  final c = ka.compareTo(kb);
  if (c != 0) return c;
  return a.name.compareTo(b.name);
}
