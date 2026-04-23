import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../models/customer.dart';
import '../models/delivery_slot.dart';
import '../utils/delivery_plan_dates.dart';
import '../utils/delivery_route_optimizer.dart';
import '../utils/maps_links.dart';
import '../utils/phone_launch.dart';

enum _AdminRouteOrder { byTime, custom }

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen>
    with WidgetsBindingObserver {
  DeliverySlot _slot = DeliverySlot.morning;
  final _search = TextEditingController();

  /// Admin-only: custom uses saved drag order and allows reorder; by time uses
  /// the optimized route (same as delivery view).
  _AdminRouteOrder _adminRouteOrder = _AdminRouteOrder.custom;

  /// Default route start for leg-distance metrics (no in-app editor).
  static const LatLng _kRouteStart = LatLng(13.36139, 77.11169);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(context.read<AppRepository>().loadManualDeliveryRouteOrders());
    }
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

  Widget _deliveryStopCard({
    Key? key,
    required BuildContext context,
    required AppRepository repo,
    required Customer c,
    required int routeIndex,
    required double? legKm,
    required ColorScheme cs,
  }) {
    final delivered = repo.isDeliveryChecked(c.id);
    final hasMapsLink = mapsUriFromAddress(c.address) != null;
    final theme = Theme.of(context);
    final addr = _addressWithoutUrls(c.address);
    const actionStyle = ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      minimumSize: WidgetStatePropertyAll(Size(104, 36)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return Card(
      key: key,
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: cs.tertiaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            legKm != null
                                ? '${routeIndex + 1} · ${legKm.toStringAsFixed(1)} km'
                                : '${routeIndex + 1}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onTertiaryContainer,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (c.strictDeliveryTime) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: 'Strict delivery time',
                          child: Icon(
                            Icons.schedule,
                            size: 16,
                            color: cs.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    c.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      decoration:
                          delivered ? TextDecoration.lineThrough : null,
                      color: delivered ? cs.onSurfaceVariant : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    c.phone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (addr.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      addr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.25,
                      ),
                    ),
                  ],
                  if (c.requestedDeliveryTime.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        child: Text(
                          c.requestedDeliveryTime,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSecondaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FilledButton.tonalIcon(
                  style: actionStyle,
                  onPressed: () =>
                      openCustomerPhoneDialer(context, c.phone),
                  icon: Icon(
                    Icons.phone_outlined,
                    size: 18,
                    color: cs.primary,
                  ),
                  label: const Text('Call'),
                ),
                if (hasMapsLink) ...[
                  const SizedBox(height: 6),
                  FilledButton.tonalIcon(
                    style: actionStyle,
                    onPressed: () =>
                        openAddressInGoogleMaps(context, c.address),
                    icon: Icon(
                      Icons.pin_drop,
                      size: 18,
                      color: cs.primary,
                    ),
                    label: const Text('Maps'),
                  ),
                ],
                const SizedBox(height: 6),
                if (delivered)
                  OutlinedButton(
                    style: actionStyle,
                    onPressed: () => repo.toggleDeliveryDone(c.id),
                    child: const Text('Undo'),
                  )
                else
                  FilledButton(
                    style: actionStyle,
                    onPressed: () => repo.toggleDeliveryDone(c.id),
                    child: const Text('Delivered'),
                  ),
              ],
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
    const start = _kRouteStart;
    final isAdmin = repo.isAdmin;
    final isDeliveryAgent = repo.isDeliveryAgent;
    final useCustomOrder =
        isDeliveryAgent || (isAdmin && _adminRouteOrder == _AdminRouteOrder.custom);

    late List<Customer> list;
    late List<double?> routeKm;
    if (useCustomOrder) {
      final fb = optimizeDeliveryRouteByRequestedTime(base, start);
      list = repo.orderedCustomersForCustomRoute(_slot, base, fb.customers);
    } else {
      final opt = optimizeDeliveryRouteByRequestedTime(base, start);
      list = opt.customers;
    }

    // Admin custom order is authoritative; do not re-sort last-day plans ahead.
    if (!useCustomOrder) {
      list = prioritizeSubscriptionLastDay(list);
    }
    routeKm = routeMetricsForCustomerOrder(list, start).kmFromPrevious;

    final done = repo.completedCountForSlot(_slot);
    final displayList = useCustomOrder
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
    final allowDragReorder =
        isAdmin && useCustomOrder && _search.text.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today’s route'),
        actions: repo.isDeliveryAgent
            ? null
            : [
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
          if (isAdmin)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: SegmentedButton<_AdminRouteOrder>(
                segments: const [
                  ButtonSegment(
                    value: _AdminRouteOrder.byTime,
                    label: Text('By time'),
                    icon: Icon(Icons.schedule_outlined),
                  ),
                  ButtonSegment(
                    value: _AdminRouteOrder.custom,
                    label: Text('Custom'),
                    icon: Icon(Icons.swap_vert),
                  ),
                ],
                selected: {_adminRouteOrder},
                onSelectionChanged: (s) {
                  setState(() => _adminRouteOrder = s.first);
                },
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
                                    buildDefaultDragHandles: false,
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
                                      return ReorderableDragStartListener(
                                        index: i,
                                        key: ValueKey(c.id),
                                        child: _deliveryStopCard(
                                          context: context,
                                          repo: repo,
                                          c: c,
                                          routeIndex: routeIndex,
                                          legKm: legKm,
                                          cs: cs,
                                        ),
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
