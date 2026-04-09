import 'dart:math' as math;

import '../models/customer.dart';
import 'delivery_route_sort.dart';
import 'maps_links.dart';

/// Geographic point in WGS84 (degrees).
class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;
}

/// Great-circle distance in kilometers.
double haversineKm(LatLng a, LatLng b) {
  const earthKm = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final la1 = rad(a.lat);
  final la2 = rad(b.lat);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(la1) * math.cos(la2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  final c = 2 * math.asin(math.min(1.0, math.sqrt(h)));
  return earthKm * c;
}

bool _looksLikeLatLngPair(String s) {
  return RegExp(r'^-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?$').hasMatch(s.trim());
}

LatLng? latLngFromGoogleMapsUri(Uri uri) {
  final s = uri.toString();

  final d3 = RegExp(r'!3d(-?\d+(?:\.\d+)?)').firstMatch(s);
  final d4 = RegExp(r'!4d(-?\d+(?:\.\d+)?)').firstMatch(s);
  if (d3 != null && d4 != null) {
    return LatLng(
      double.parse(d3.group(1)!),
      double.parse(d4.group(1)!),
    );
  }

  final at = RegExp(r'@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)').firstMatch(s);
  if (at != null) {
    return LatLng(
      double.parse(at.group(1)!),
      double.parse(at.group(2)!),
    );
  }

  final q = uri.queryParameters['q']?.trim() ?? '';
  if (_looksLikeLatLngPair(q)) {
    final parts = q.split(',');
    return LatLng(
      double.parse(parts[0].trim()),
      double.parse(parts[1].trim()),
    );
  }

  final ll = uri.queryParameters['ll']?.trim() ?? '';
  if (_looksLikeLatLngPair(ll)) {
    final parts = ll.split(',');
    return LatLng(
      double.parse(parts[0].trim()),
      double.parse(parts[1].trim()),
    );
  }

  return null;
}

/// Reads coordinates from the first Google Maps URL in [addressText], or an
/// embedded `@lat,lng` fragment.
LatLng? latLngFromCustomerAddress(String addressText) {
  final uri = mapsUriFromAddress(addressText);
  if (uri != null) {
    final fromUri = latLngFromGoogleMapsUri(uri);
    if (fromUri != null) return fromUri;
  }
  final at =
      RegExp(r'@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)').firstMatch(addressText);
  if (at != null) {
    return LatLng(
      double.parse(at.group(1)!),
      double.parse(at.group(2)!),
    );
  }
  return null;
}

class OptimizedRouteResult {
  const OptimizedRouteResult({
    required this.customers,
    required this.kmFromPrevious,
  });

  final List<Customer> customers;
  /// For each stop: km from depot (first) or previous stop with coords; null if
  /// this stop has no mappable coordinates.
  final List<double?> kmFromPrevious;
}

double _openPathLength(LatLng start, List<LatLng> pts) {
  if (pts.isEmpty) return 0;
  var t = haversineKm(start, pts.first);
  for (var i = 0; i < pts.length - 1; i++) {
    t += haversineKm(pts[i], pts[i + 1]);
  }
  return t;
}

void _reverseRange<T>(List<T> list, int i, int j) {
  while (i < j) {
    final x = list[i];
    list[i] = list[j];
    list[j] = x;
    i++;
    j--;
  }
}

/// Reduces total straight-line distance along the open path [start]→[pts][0]→…
/// by 2-opt reversals (good enough for small ~dozens of stops).
void _twoOptOpenPath(LatLng start, List<Customer> customers, List<LatLng> pts) {
  final n = pts.length;
  if (n < 3) return;
  assert(customers.length == n);
  var improved = true;
  while (improved) {
    improved = false;
    outer:
    for (var i = 0; i < n; i++) {
      for (var j = i + 2; j < n; j++) {
        final trialC = List<Customer>.from(customers);
        final trialP = List<LatLng>.from(pts);
        _reverseRange(trialC, i, j);
        _reverseRange(trialP, i, j);
        if (_openPathLength(start, trialP) <
            _openPathLength(start, pts) - 1e-9) {
          customers.setAll(0, trialC);
          pts.setAll(0, trialP);
          improved = true;
          break outer;
        }
      }
    }
  }
}

int _nearestNeighborPickIndex(
  LatLng current,
  List<({Customer c, LatLng p})> remaining,
) {
  var bestI = 0;
  var bestD = double.infinity;
  for (var i = 0; i < remaining.length; i++) {
    final d = haversineKm(current, remaining[i].p);
    final tie = (d - bestD).abs() < 1e-9;
    final better =
        d < bestD - 1e-9 || (tie && remaining[i].c.name.compareTo(remaining[bestI].c.name) < 0);
    if (better) {
      bestD = d;
      bestI = i;
    }
  }
  return bestI;
}

List<double?> _legsFromPath(LatLng start, List<LatLng> pts) {
  if (pts.isEmpty) return [];
  final legs = <double?>[];
  var cur = start;
  for (final p in pts) {
    legs.add(haversineKm(cur, p));
    cur = p;
  }
  return legs;
}

/// Shortest travel: nearest-neighbor from depot, then 2-opt. Stops without
/// coordinates go last (by name).
OptimizedRouteResult optimizeDeliveryRoute(
  List<Customer> stops,
  LatLng start,
) {
  if (stops.isEmpty) {
    return const OptimizedRouteResult(customers: [], kmFromPrevious: []);
  }

  final withCoords = <({Customer c, LatLng p})>[];
  final without = <Customer>[];
  for (final c in stops) {
    final p = latLngFromCustomerAddress(c.address);
    if (p != null) {
      withCoords.add((c: c, p: p));
    } else {
      without.add(c);
    }
  }
  without.sort((a, b) => a.name.compareTo(b.name));

  final remaining = List<({Customer c, LatLng p})>.from(withCoords);
  final ordered = <Customer>[];
  final orderedPts = <LatLng>[];
  var current = start;

  while (remaining.isNotEmpty) {
    final bestI = _nearestNeighborPickIndex(current, remaining);
    final pick = remaining.removeAt(bestI);
    ordered.add(pick.c);
    orderedPts.add(pick.p);
    current = pick.p;
  }

  _twoOptOpenPath(start, ordered, orderedPts);

  final legs = _legsFromPath(start, orderedPts);
  for (final c in without) {
    legs.add(null);
    ordered.add(c);
  }

  return OptimizedRouteResult(customers: ordered, kmFromPrevious: legs);
}

/// Respects **requested time order** (earlier windows first). Inside each
/// identical time-sort bucket, uses nearest-neighbor from the last stop to
/// shorten backtracking. Stops without coordinates follow, sorted by time
/// then name.
OptimizedRouteResult optimizeDeliveryRouteByRequestedTime(
  List<Customer> stops,
  LatLng start,
) {
  if (stops.isEmpty) {
    return const OptimizedRouteResult(customers: [], kmFromPrevious: []);
  }

  final withCoords = <({Customer c, LatLng p})>[];
  final without = <Customer>[];
  for (final c in stops) {
    final p = latLngFromCustomerAddress(c.address);
    if (p != null) {
      withCoords.add((c: c, p: p));
    } else {
      without.add(c);
    }
  }

  withCoords.sort((a, b) {
    final t = compareCustomersByRequestedTime(a.c, b.c);
    if (t != 0) return t;
    return a.c.name.compareTo(b.c.name);
  });

  final ordered = <Customer>[];
  final orderedPts = <LatLng>[];
  var current = start;
  final bucket = <({Customer c, LatLng p})>[];

  void flushBucket() {
    if (bucket.isEmpty) return;
    final rem = List<({Customer c, LatLng p})>.from(bucket);
    bucket.clear();
    while (rem.isNotEmpty) {
      final bestI = _nearestNeighborPickIndex(current, rem);
      final pick = rem.removeAt(bestI);
      ordered.add(pick.c);
      orderedPts.add(pick.p);
      current = pick.p;
    }
  }

  int? lastKey;
  for (final pair in withCoords) {
    final k = requestedDeliveryTimeSortKey(pair.c.requestedDeliveryTime);
    if (lastKey != null && k != lastKey) {
      flushBucket();
    }
    lastKey = k;
    bucket.add(pair);
  }
  flushBucket();

  without.sort(compareCustomersByRequestedTime);
  final legs = _legsFromPath(start, orderedPts);
  for (final c in without) {
    legs.add(null);
    ordered.add(c);
  }

  return OptimizedRouteResult(customers: ordered, kmFromPrevious: legs);
}

/// Straight-line km per stop for an explicit [ordered] sequence (admin custom order).
OptimizedRouteResult routeMetricsForCustomerOrder(
  List<Customer> ordered,
  LatLng start,
) {
  if (ordered.isEmpty) {
    return const OptimizedRouteResult(customers: [], kmFromPrevious: []);
  }
  final legs = <double?>[];
  var cur = start;
  for (final c in ordered) {
    final p = latLngFromCustomerAddress(c.address);
    if (p != null) {
      legs.add(haversineKm(cur, p));
      cur = p;
    } else {
      legs.add(null);
    }
  }
  return OptimizedRouteResult(
    customers: List<Customer>.from(ordered),
    kmFromPrevious: legs,
  );
}
