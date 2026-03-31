import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../models/customer.dart';
import '../models/delivery_slot.dart';
import '../utils/delivery_route_optimizer.dart';
import '../utils/delivery_route_sort.dart';
import '../utils/maps_links.dart';
import '../utils/phone_launch.dart';

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  DeliverySlot _slot = DeliverySlot.morning;
  DeliveryListSort _sort = DeliveryListSort.byRequestedTime;

  /// Depot / vehicle start (WGS84). Used for distance sort and leg distances.
  double _routeStartLat = 13.36139;
  double _routeStartLng = 77.11169;

  String _addressWithoutUrls(String raw) {
    final noUrls = raw.replaceAll(RegExp(r'https?://[^\s]+'), '').trim();
    return noUrls.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  Future<void> _editRouteStart(BuildContext context) async {
    final latCtrl =
        TextEditingController(text: _routeStartLat.toStringAsFixed(5));
    final lngCtrl =
        TextEditingController(text: _routeStartLng.toStringAsFixed(5));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Route start (depot)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: latCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Latitude',
                hintText: 'e.g. 12.9716',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lngCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Longitude',
                hintText: 'e.g. 77.5946',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final la = double.tryParse(latCtrl.text.trim());
    final lo = double.tryParse(lngCtrl.text.trim());
    latCtrl.dispose();
    lngCtrl.dispose();
    if (ok == true &&
        mounted &&
        la != null &&
        lo != null &&
        la >= -90 &&
        la <= 90 &&
        lo >= -180 &&
        lo <= 180) {
      setState(() {
        _routeStartLat = la;
        _routeStartLng = lo;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final base = repo.customersInDeliverySlot(_slot);
    final start = LatLng(_routeStartLat, _routeStartLng);
    final OptimizedRouteResult opt = _sort == DeliveryListSort.byOptimizedRoute
        ? optimizeDeliveryRoute(base, start)
        : optimizeDeliveryRouteByRequestedTime(base, start);
    final list = opt.customers;
    final routeKm = opt.kmFromPrevious;
    final done = repo.completedCountForSlot(_slot);
    final cs = Theme.of(context).colorScheme;
    final routeTotalKm =
        routeKm.whereType<double>().fold(0.0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today’s route'),
        actions: [
          IconButton(
            tooltip: 'Set route start (depot)',
            icon: const Icon(Icons.edit_location_alt_outlined),
            onPressed: list.isEmpty ? null : () => _editRouteStart(context),
          ),
          TextButton(
            onPressed: list.isEmpty
                ? null
                : () {
                    repo.markAllDeliveriesDone(_slot, true);
                  },
            child: const Text('Mark all'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              'Check off each stop as you complete it. Tap Open GMaps when a link is saved in the address.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: SegmentedButton<DeliverySlot>(
              segments: const [
                ButtonSegment(
                  value: DeliverySlot.morning,
                  label: Text('Morning'),
                  icon: Icon(Icons.wb_sunny_outlined),
                ),
                ButtonSegment(
                  value: DeliverySlot.evening,
                  label: Text('Evening'),
                  icon: Icon(Icons.nights_stay_outlined),
                ),
              ],
              selected: {_slot},
              onSelectionChanged: (s) {
                setState(() => _slot = s.first);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: SegmentedButton<DeliveryListSort>(
              segments: const [
                ButtonSegment(
                  value: DeliveryListSort.byOptimizedRoute,
                  label: Text('Shortest'),
                  icon: Icon(Icons.route_outlined),
                ),
                ButtonSegment(
                  value: DeliveryListSort.byRequestedTime,
                  label: Text('By time'),
                  icon: Icon(Icons.schedule_outlined),
                ),
              ],
              selected: {_sort},
              onSelectionChanged: (s) {
                setState(() => _sort = s.first);
              },
            ),
          ),
          if (list.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Material(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => _editRouteStart(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Row(
                      children: [
                        Icon(Icons.place_outlined, color: cs.primary, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Start ${_routeStartLat.toStringAsFixed(4)}, ${_routeStartLng.toStringAsFixed(4)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _sort == DeliveryListSort.byOptimizedRoute
                                    ? 'Minimize driving: nearest-neighbor from depot, then 2-opt. Straight-line km; add Maps pin links in addresses.'
                                    : 'Respect requested time (earlier windows first); shortest path within each time window. Same km rules.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: LinearProgressIndicator(
              value: list.isEmpty ? 0 : done / list.length,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              routeTotalKm == 0
                  ? '$done / ${list.length} completed · ${_slot.label}'
                  : '$done / ${list.length} completed · ${_slot.label} · '
                      '${routeTotalKm.toStringAsFixed(1)} km (mapped legs)',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Expanded(
            child: repo.customersLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => repo.refreshCustomers(),
                    child: list.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.sizeOf(context).height * 0.35,
                                child: Center(
                                  child: Text(
                                    'No ${_slot.label.toLowerCase()} deliveries today.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final Customer c = list[i];
                      final checked = repo.isDeliveryChecked(c.id);
                      final hasMapsLink = mapsUriFromAddress(c.address) != null;
                      final legKm = i < routeKm.length ? routeKm[i] : null;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Checkbox(
                                  value: checked,
                                  onChanged: (_) =>
                                      repo.toggleDeliveryDone(c.id),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      legKm != null
                                          ? 'Stop ${i + 1} · ${legKm.toStringAsFixed(1)} km ${i == 0 ? 'from depot' : 'from previous stop'}'
                                          : 'Stop ${i + 1} · no map pin in address (straight-line distance N/A)',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: cs.tertiary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      c.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            decoration: checked
                                                ? TextDecoration.lineThrough
                                                : null,
                                            color: checked
                                                ? cs.onSurfaceVariant
                                                : null,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            c.phone,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Call',
                                          icon: const Icon(
                                            Icons.phone_outlined,
                                            size: 22,
                                          ),
                                          visualDensity:
                                              VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 40,
                                            minHeight: 40,
                                          ),
                                          onPressed: () =>
                                              openCustomerPhoneDialer(
                                            context,
                                            c.phone,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _addressWithoutUrls(c.address),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                    if (c.requestedDeliveryTime.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Time: ${c.requestedDeliveryTime}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: cs.tertiary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                    if (hasMapsLink) ...[
                                      const SizedBox(height: 10),
                                      SizedBox(
                                        width: double.infinity,
                                        child: FilledButton.tonalIcon(
                                          onPressed: () =>
                                              openAddressInGoogleMaps(
                                            context,
                                            c.address,
                                          ),
                                          icon: const Icon(
                                            Icons.map_outlined,
                                            size: 20,
                                          ),
                                          label: const Text('Open GMaps'),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  ),
          ),
        ],
      ),
    );
  }
}
