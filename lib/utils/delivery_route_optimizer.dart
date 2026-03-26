import 'dart:math' as math;

import '../models/customer.dart';
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

/// Nearest-neighbor order from [start] for stops that have map coordinates;
/// remaining stops (no pin in address) are appended alphabetically.
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

  final ordered = <Customer>[];
  final legs = <double?>[];
  var current = start;
  final remaining = List<({Customer c, LatLng p})>.from(withCoords);

  while (remaining.isNotEmpty) {
    var bestI = 0;
    var bestD = double.infinity;
    for (var i = 0; i < remaining.length; i++) {
      final d = haversineKm(current, remaining[i].p);
      if (d < bestD) {
        bestD = d;
        bestI = i;
      }
    }
    final pick = remaining.removeAt(bestI);
    legs.add(bestD);
    ordered.add(pick.c);
    current = pick.p;
  }

  for (final c in without) {
    legs.add(null);
    ordered.add(c);
  }

  return OptimizedRouteResult(customers: ordered, kmFromPrevious: legs);
}
