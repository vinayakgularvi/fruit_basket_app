import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../models/customer.dart';
import '../models/delivery_slot.dart';
import '../utils/delivery_plan_dates.dart';
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
  final _search = TextEditingController();

  /// Depot / vehicle start (WGS84). Used for distance sort and leg distances.
  double _routeStartLat = 13.36139;
  double _routeStartLng = 77.11169;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matchesDeliverySearch(String name, String phone, String query) {
    if (query.isEmpty) return true;
    final n = name.toLowerCase();
    final p = phone.replaceAll(RegExp(r'\s'), '').toLowerCase();
    final q = query.toLowerCase().trim();
    final qDigits = q.replaceAll(RegExp(r'\D'), '');
    if (qDigits.length >= 3) {
      if (p.contains(qDigits)) return true;
    }
    return n.contains(q);
  }

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

  Widget _deliveryStopCard({
    required Key key,
    required BuildContext context,
    required AppRepository repo,
    required Customer c,
    required int routeIndex,
    required double? legKm,
    required ColorScheme cs,
  }) {
    final checked = repo.isDeliveryChecked(c.id);
    final hasMapsLink = mapsUriFromAddress(c.address) != null;
    return Card(
      key: key,
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
                onChanged: (_) => repo.toggleDeliveryDone(c.id),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    legKm != null
                        ? 'Stop ${routeIndex + 1} · ${legKm.toStringAsFixed(1)} km'
                        : 'Stop ${routeIndex + 1}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.tertiary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          decoration:
                              checked ? TextDecoration.lineThrough : null,
                          color: checked ? cs.onSurfaceVariant : null,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          c.phone,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Call',
                        icon: const Icon(Icons.phone_outlined, size: 22),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        onPressed: () =>
                            openCustomerPhoneDialer(context, c.phone),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _addressWithoutUrls(c.address),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  if (c.requestedDeliveryTime.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            'Time: ${c.requestedDeliveryTime}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: cs.tertiary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        if (c.strictDeliveryTime)
                          Tooltip(
                            message: 'Strict delivery time',
                            child: Icon(
                              Icons.schedule,
                              size: 18,
                              color: cs.error,
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (hasMapsLink) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: () =>
                            openAddressInGoogleMaps(context, c.address),
                        icon: const Icon(Icons.map_outlined, size: 20),
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
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final base = repo.customersInDeliverySlot(_slot);
    final start = LatLng(_routeStartLat, _routeStartLng);
    final routeSort =
        repo.isAdmin ? _sort : DeliveryListSort.byRequestedTime;
    final customMode =
        repo.isAdmin && routeSort == DeliveryListSort.custom;

    late List<Customer> list;
    late List<double?> routeKm;
    if (customMode) {
      final fb = optimizeDeliveryRouteByRequestedTime(base, start);
      list = repo.orderedCustomersForCustomRoute(_slot, base, fb.customers);
      final optCustom = routeMetricsForCustomerOrder(list, start);
      routeKm = optCustom.kmFromPrevious;
    } else if (routeSort == DeliveryListSort.byOptimizedRoute) {
      final opt = optimizeDeliveryRoute(base, start);
      list = opt.customers;
      routeKm = opt.kmFromPrevious;
    } else {
      final opt = optimizeDeliveryRouteByRequestedTime(base, start);
      list = opt.customers;
      routeKm = opt.kmFromPrevious;
    }

    list = prioritizeSubscriptionLastDay(list);
    routeKm = routeMetricsForCustomerOrder(list, start).kmFromPrevious;

    final done = repo.completedCountForSlot(_slot);
    final displayList = customMode
        ? List<Customer>.from(list)
        : <Customer>[
            ...list.where((c) => !repo.isDeliveryChecked(c.id)),
            ...list.where((c) => repo.isDeliveryChecked(c.id)),
          ];
    final filteredDisplay = displayList
        .where(
          (c) => _matchesDeliverySearch(c.name, c.phone, _search.text),
        )
        .toList();
    final cs = Theme.of(context).colorScheme;
    final routeTotalKm =
        routeKm.whereType<double>().fold(0.0, (a, b) => a + b);
    final allowDragReorder = customMode && _search.text.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today’s route'),
        actions: repo.isDeliveryAgent
            ? null
            : [
                IconButton(
                  tooltip: 'Set route start (depot)',
                  icon: const Icon(Icons.edit_location_alt_outlined),
                  onPressed:
                      list.isEmpty ? null : () => _editRouteStart(context),
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
          if (!repo.isDeliveryAgent)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: SegmentedButton<DeliveryListSort>(
                segments: [
                  const ButtonSegment(
                    value: DeliveryListSort.byOptimizedRoute,
                    label: Text('Shortest'),
                    icon: Icon(Icons.route_outlined),
                  ),
                  const ButtonSegment(
                    value: DeliveryListSort.byRequestedTime,
                    label: Text('By time'),
                    icon: Icon(Icons.schedule_outlined),
                  ),
                  if (repo.isAdmin)
                    const ButtonSegment(
                      value: DeliveryListSort.custom,
                      label: Text('Custom'),
                      icon: Icon(Icons.drag_indicator),
                    ),
                ],
                selected: {routeSort},
                onSelectionChanged: (s) {
                  setState(() => _sort = s.first);
                },
              ),
            ),
          if (allowDragReorder)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                'Drag the handle on each row to reorder. Saved for today.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search by name or phone',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          if (list.isNotEmpty && !repo.isDeliveryAgent)
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
                          child: Text(
                            'Depot ${_routeStartLat.toStringAsFixed(4)}, ${_routeStartLng.toStringAsFixed(4)}',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: repo.customersLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () async {
                      await repo.refreshCustomers();
                      await repo.loadManualDeliveryRouteOrders();
                    },
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
                        : filteredDisplay.isEmpty
                            ? ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                children: [
                                  SizedBox(
                                    height: MediaQuery.sizeOf(context).height *
                                        0.3,
                                    child: Center(
                                      child: Text(
                                        'No matches for your search.',
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
                            : allowDragReorder
                                ? ReorderableListView.builder(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      24,
                                    ),
                                    buildDefaultDragHandles: true,
                                    itemCount: filteredDisplay.length,
                                    onReorder: (oldIndex, newIndex) async {
                                      if (newIndex > oldIndex) newIndex--;
                                      final ids = displayList
                                          .map((c) => c.id)
                                          .toList();
                                      final id = ids.removeAt(oldIndex);
                                      ids.insert(newIndex, id);
                                      await repo.setManualDeliveryRouteOrder(
                                        _slot,
                                        ids,
                                      );
                                      if (context.mounted) setState(() {});
                                    },
                                    itemBuilder: (context, i) {
                                      final c = filteredDisplay[i];
                                      final routeIndex =
                                          list.indexWhere((x) => x.id == c.id);
                                      final legKm = routeIndex >= 0 &&
                                              routeIndex < routeKm.length
                                          ? routeKm[routeIndex]
                                          : null;
                                      return _deliveryStopCard(
                                        key: ValueKey(c.id),
                                        context: context,
                                        repo: repo,
                                        c: c,
                                        routeIndex: routeIndex,
                                        legKm: legKm,
                                        cs: cs,
                                      );
                                    },
                                  )
                                : ListView.builder(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      24,
                                    ),
                                    itemCount: filteredDisplay.length,
                                    itemBuilder: (context, i) {
                                      final c = filteredDisplay[i];
                                      final routeIndex = list.indexWhere(
                                        (x) => x.id == c.id,
                                      );
                                      final legKm = routeIndex >= 0 &&
                                              routeIndex < routeKm.length
                                          ? routeKm[routeIndex]
                                          : null;
                                      return _deliveryStopCard(
                                        key: ValueKey(c.id),
                                        context: context,
                                        repo: repo,
                                        c: c,
                                        routeIndex: routeIndex,
                                        legKm: legKm,
                                        cs: cs,
                                      );
                                    },
                                  ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: LinearProgressIndicator(
              value: list.isEmpty ? 0 : done / list.length,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              routeTotalKm == 0
                  ? '$done / ${list.length} · ${_slot.label}'
                  : '$done / ${list.length} · ${_slot.label} · '
                      '${routeTotalKm.toStringAsFixed(1)} km',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}
