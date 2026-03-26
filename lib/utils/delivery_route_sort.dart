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
/// Unparseable or empty sorts after known times; tie-break by name.
int requestedDeliveryTimeSortKey(String requestedDeliveryTime) {
  final s = requestedDeliveryTime.trim().toLowerCase();
  if (s.isEmpty) return 1 << 20;

  final m = RegExp(r'(\d{1,2})\s*(?::(\d{2}))?').firstMatch(s);
  if (m == null) return (1 << 20) - 1;

  var hour = int.tryParse(m.group(1) ?? '') ?? 12;
  var minute = int.tryParse(m.group(2) ?? '') ?? 0;
  hour = hour.clamp(0, 23);
  minute = minute.clamp(0, 59);

  final isPm = s.contains('pm');
  final isAm = s.contains('am');
  if (isPm && hour < 12) hour += 12;
  if (isAm && hour == 12) hour = 0;

  if (!isPm && !isAm) {
    if (hour >= 1 && hour <= 11) {
      if (s.contains('evening') || s.contains('night')) hour += 12;
    }
  }

  return hour * 60 + minute;
}

int compareCustomersByRequestedTime(Customer a, Customer b) {
  final ka = requestedDeliveryTimeSortKey(a.requestedDeliveryTime);
  final kb = requestedDeliveryTimeSortKey(b.requestedDeliveryTime);
  final c = ka.compareTo(kb);
  if (c != 0) return c;
  return a.name.compareTo(b.name);
}
