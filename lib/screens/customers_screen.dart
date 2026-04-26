import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import 'package:intl/intl.dart';

import '../models/customer.dart';
import '../models/customer_list_filter.dart';
import '../models/delivery_slot.dart';
import '../models/subscription_plan.dart';
import '../utils/delivery_plan_dates.dart';
import '../utils/phone_launch.dart';
import '../utils/whatsapp_launch.dart';
import 'add_customer_screen.dart';
import '../widgets/manual_receipt_dialog.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key, this.initialFilter});

  /// Applied once when this widget is first created (e.g. after Home deep link).
  final CustomerListFilter? initialFilter;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _search = TextEditingController();
  late CustomerListFilter _filter;
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter ?? CustomerListFilter.all;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _undoSkipForCustomer(
    BuildContext context,
    AppRepository repo,
    Customer c,
    DateFormat df,
  ) async {
    final unique = c.skippedDeliveryDates.map(dateOnly).toSet().toList()
      ..sort();
    if (unique.isEmpty) return;
    final chosen = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Undo skip'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final d in unique)
                ListTile(
                  title: Text(df.format(d)),
                  onTap: () => Navigator.of(ctx).pop(d),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (chosen == null) return;
    try {
      await repo.undoSkipDeliveryDate(c.id, chosen);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not undo skip: $e')),
      );
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed skip for ${df.format(chosen)}.')),
    );
  }

  Future<void> _bulkAssignDeliveryAgent(
    BuildContext context,
    AppRepository repo,
  ) async {
    if (_selectedIds.isEmpty) return;
    final agents = repo.deliveryAgentUsernames;
    String? chosen;
    final applied = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Assign delivery agent'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Delivery agent',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  DropdownButton<String?>(
                    isExpanded: true,
                    value: chosen,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Unassigned'),
                      ),
                      ...agents.map(
                        (u) => DropdownMenuItem<String?>(
                          value: u,
                          child: Text(u),
                        ),
                      ),
                    ],
                    onChanged: (v) => setLocal(() => chosen = v),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Apply to selected'),
                ),
              ],
            );
          },
        );
      },
    );
    if (applied != true || !context.mounted) return;

    var ok = 0;
    try {
      for (final id in _selectedIds) {
        final idx = repo.customers.indexWhere((c) => c.id == id);
        if (idx < 0) continue;
        final c = repo.customers[idx];
        await repo.updateCustomer(
          c.copyWith(
            clearAssignedDeliveryAgent: chosen == null,
            assignedDeliveryAgentUsername: chosen,
          ),
        );
        ok++;
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update: $e')),
      );
      return;
    }
    if (!context.mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          chosen == null
              ? 'Cleared delivery agent for $ok customer(s).'
              : 'Assigned "$chosen" to $ok customer(s).',
        ),
      ),
    );
  }

  Future<void> _confirmRecontinueSubscription(
    BuildContext context,
    AppRepository repo,
    Customer c,
    DateFormat df,
  ) async {
    final newStart = dateOnly(c.endDate).add(const Duration(days: 1));
    final newEnd = endDateForBilling(newStart, c.billingPeriod);
    final periodWord = c.billingPeriod.periodNoun;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recontinue subscription'),
        content: Text(
          'Add one $periodWord: new period ${df.format(newStart)} → '
          '${df.format(newEnd)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Recontinue'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await repo.recontinueSubscription(c.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${c.name}: subscription extended.')),
    );
  }

  Future<void> _confirmSetInactive(
    BuildContext context,
    AppRepository repo,
    Customer c,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark inactive'),
        content: Text(
          'Mark "${c.name}" as inactive? They will be hidden from active '
          'lists until turned active again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Inactive'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await repo.setCustomerActive(c.id, false);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${c.name} marked inactive.')),
    );
  }

  List<Customer> _apply(
    List<Customer> all,
    String query,
    CustomerListFilter f,
  ) {
    // `repo.customers` is unmodifiable; sort() requires a mutable list.
    var list = List<Customer>.from(all);
    if (f == CustomerListFilter.recentlyDeleted) {
      final now = DateTime.now();
      list = list
          .where(
            (c) => c.deletedAt != null && c.isSoftDeleteRecoverable(now),
          )
          .toList();
    } else {
      list = list.where((c) => c.deletedAt == null).toList();
    }

    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((c) {
        return c.name.toLowerCase().contains(q) ||
            c.phone.toLowerCase().contains(q) ||
            c.address.toLowerCase().contains(q);
      }).toList();
    }
    final hideInactiveByDefault = f != CustomerListFilter.recentlyDeleted &&
        (f == CustomerListFilter.all ||
            f == CustomerListFilter.morning ||
            f == CustomerListFilter.evening ||
            f == CustomerListFilter.lastDayOfPlan);
    if (hideInactiveByDefault) {
      list = list.where((c) => c.active).toList();
    }

    switch (f) {
      case CustomerListFilter.all:
        break;
      case CustomerListFilter.morning:
        list =
            list.where((c) => c.preferredSlot == DeliverySlot.morning).toList();
        break;
      case CustomerListFilter.evening:
        list =
            list.where((c) => c.preferredSlot == DeliverySlot.evening).toList();
        break;
      case CustomerListFilter.activeOnly:
        list = list.where((c) => c.active).toList();
        break;
      case CustomerListFilter.inactiveOnly:
        list = list.where((c) => !c.active).toList();
        break;
      case CustomerListFilter.createdPendingApproval:
        list = list
            .where((c) => c.customerCreated && !c.adminApproved)
            .toList();
        break;
      case CustomerListFilter.lastDayOfPlan:
        list = list.where(subscriptionLastDayToday).toList();
        break;
      case CustomerListFilter.recentlyDeleted:
        break;
    }
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final items = _apply(repo.customers, _search.text, _filter);

    return Scaffold(
      appBar: AppBar(
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Exit selection',
                onPressed: () => setState(() {
                  _selectionMode = false;
                  _selectedIds.clear();
                }),
              )
            : null,
        title: _selectionMode
            ? Text(
                _selectedIds.isEmpty
                    ? 'Select customers'
                    : '${_selectedIds.length} selected',
              )
            : const Text('Customers'),
        actions: [
          if (_selectionMode) ...[
            TextButton(
              onPressed: items.isEmpty
                  ? null
                  : () => setState(() {
                        _selectedIds
                          ..clear()
                          ..addAll(items.map((c) => c.id));
                      }),
              child: const Text('All'),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonal(
                onPressed: _selectedIds.isEmpty
                    ? null
                    : () => _bulkAssignDeliveryAgent(context, repo),
                child: const Text('Assign'),
              ),
            ),
          ] else if (repo.isAdmin) ...[
            IconButton(
              icon: const Icon(Icons.local_shipping_outlined),
              tooltip: 'Select customers to assign delivery agent',
              onPressed: () => setState(() => _selectionMode = true),
            ),
          ],
        ],
      ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final filter = await Navigator.of(context)
                    .push<CustomerListFilter?>(
                  MaterialPageRoute(
                    builder: (_) => const AddCustomerScreen(),
                  ),
                );
                if (filter != null && mounted) {
                  setState(() => _filter = filter);
                }
              },
              icon: const Icon(Icons.person_add),
              label: const Text('Add customer'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search name, phone, address',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _filter == CustomerListFilter.all,
                  onSelected: () => setState(() => _filter = CustomerListFilter.all),
                ),
                _FilterChip(
                  label: 'Morning',
                  selected: _filter == CustomerListFilter.morning,
                  onSelected: () =>
                      setState(() => _filter = CustomerListFilter.morning),
                ),
                _FilterChip(
                  label: 'Evening',
                  selected: _filter == CustomerListFilter.evening,
                  onSelected: () =>
                      setState(() => _filter = CustomerListFilter.evening),
                ),
                _FilterChip(
                  label: 'Active',
                  selected: _filter == CustomerListFilter.activeOnly,
                  onSelected: () =>
                      setState(() => _filter = CustomerListFilter.activeOnly),
                ),
                _FilterChip(
                  label: 'Inactive',
                  selected: _filter == CustomerListFilter.inactiveOnly,
                  onSelected: () =>
                      setState(() => _filter = CustomerListFilter.inactiveOnly),
                ),
                _FilterChip(
                  label: 'Pending approval',
                  selected: _filter == CustomerListFilter.createdPendingApproval,
                  onSelected: () => setState(
                    () => _filter = CustomerListFilter.createdPendingApproval,
                  ),
                ),
                _FilterChip(
                  label: 'Last day',
                  selected: _filter == CustomerListFilter.lastDayOfPlan,
                  onSelected: () =>
                      setState(() => _filter = CustomerListFilter.lastDayOfPlan),
                ),
                _FilterChip(
                  label: 'Recently deleted',
                  selected: _filter == CustomerListFilter.recentlyDeleted,
                  onSelected: () => setState(
                    () => _filter = CustomerListFilter.recentlyDeleted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: repo.customersLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => repo.refreshCustomers(),
                    child: items.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.sizeOf(context).height * 0.35,
                                child: Center(
                                  child: Text(
                                    _filter ==
                                            CustomerListFilter.recentlyDeleted
                                        ? 'No recently deleted customers '
                                            '(or past the 30-day recovery window).'
                                        : 'No customers match your search.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final c = items[i];
                      final cs = Theme.of(context).colorScheme;
                      final df = DateFormat.yMMMd();
                      final dtf = DateFormat.yMMMd().add_jm();
                      final periodShort = c.billingPeriod.listAbbrev;
                      return GestureDetector(
                        onLongPress: repo.isAdmin &&
                                !_selectionMode &&
                                c.deletedAt == null
                            ? () => setState(() {
                                  _selectionMode = true;
                                  _selectedIds
                                    ..clear()
                                    ..add(c.id);
                                })
                            : null,
                        child: Card(
                          elevation: 0,
                          color: cs.surfaceContainerLow,
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.55),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (c.deletedAt != null) ...[
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: cs.errorContainer
                                          .withValues(alpha: 0.45),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                            'Removed ${dtf.format(c.deletedAt!)}. '
                                            'Auto-purged after '
                                            '${Customer.softDeleteRetention.inDays} '
                                            'days (about '
                                            '${dtf.format(c.deletedAt!.add(Customer.softDeleteRetention))}).',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          const SizedBox(height: 8),
                                          FilledButton.icon(
                                            onPressed: () async {
                                              await repo
                                                  .restoreDeletedCustomer(
                                                c.id,
                                              );
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    '${c.name} restored.',
                                                  ),
                                                ),
                                              );
                                            },
                                            icon: const Icon(
                                              Icons.restore_outlined,
                                            ),
                                            label: const Text(
                                              'Restore customer',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_selectionMode) ...[
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Checkbox(
                                          value: _selectedIds.contains(c.id),
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          visualDensity: VisualDensity.compact,
                                          onChanged: (_) => setState(() {
                                            if (_selectedIds.contains(c.id)) {
                                              _selectedIds.remove(c.id);
                                            } else {
                                              _selectedIds.add(c.id);
                                            }
                                          }),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: cs.primaryContainer,
                                      foregroundColor: cs.onPrimaryContainer,
                                      child: Text(
                                        c.name.isNotEmpty
                                            ? c.name[0].toUpperCase()
                                            : '?',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                c.name,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      fontWeight: FontWeight.w700,
                                                      height: 1.25,
                                                    ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Chip(
                                              avatar: Icon(
                                                c.preferredSlot ==
                                                        DeliverySlot.morning
                                                    ? Icons.wb_sunny_outlined
                                                    : Icons.nights_stay_outlined,
                                                size: 16,
                                                color: cs.secondary,
                                              ),
                                              label: Text(
                                                c.preferredSlot.label,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                              ),
                                              side: BorderSide(
                                                color: cs.outline
                                                    .withValues(alpha: 0.45),
                                              ),
                                              backgroundColor: cs.surface,
                                            ),
                                          ],
                                        ),
                                    const SizedBox(height: 6),
                                    Text(
                                      c.phone,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Icon(
                                            Icons.subscriptions_outlined,
                                            size: 16,
                                            color: cs.tertiary,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            '${c.planTier.title} · ₹${c.planPriceRupees}/$periodShort'
                                            '${c.secondaryPlanTier != null ? '\n+ ${c.secondaryPlanTier!.title} · ₹${c.secondaryPlanPriceRupees}/$periodShort' : ''}\n'
                                            'Total ₹${c.totalPlanPriceRupees}/$periodShort · '
                                            '${df.format(c.startDate)} → ${df.format(c.endDate)}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: cs.onSurfaceVariant,
                                                  height: 1.35,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                            maxLines: 4,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (subscriptionLastDayToday(c) &&
                                        c.deletedAt == null) ...[
                                      const SizedBox(height: 10),
                                      Material(
                                        elevation: 0,
                                        color: cs.tertiaryContainer
                                            .withValues(alpha: 0.55),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          side: BorderSide(
                                            color: cs.tertiary
                                                .withValues(alpha: 0.35),
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.today_outlined,
                                                    size: 20,
                                                    color: cs.onTertiaryContainer,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      'Last day of subscription',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelLarge
                                                          ?.copyWith(
                                                            color: cs
                                                                .onTertiaryContainer,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: [
                                                  FilledButton.tonalIcon(
                                                    onPressed: c.phone
                                                            .trim()
                                                            .isEmpty
                                                        ? null
                                                        : () =>
                                                            openCustomerPhoneDialer(
                                                              context,
                                                              c.phone,
                                                            ),
                                                    icon: const Icon(
                                                      Icons.call,
                                                      size: 20,
                                                    ),
                                                    label: const Text('Call'),
                                                  ),
                                                  if (_filter ==
                                                      CustomerListFilter
                                                          .lastDayOfPlan)
                                                    FilledButton.tonal(
                                                      onPressed: c.phone
                                                              .trim()
                                                              .isEmpty
                                                          ? null
                                                          : () => unawaited(
                                                                openSubscriptionExpiryWhatsApp(
                                                                  context,
                                                                  c.phone,
                                                                ),
                                                              ),
                                                      child: const Text(
                                                        'Send msg',
                                                      ),
                                                    ),
                                                  FilledButton.icon(
                                                    onPressed: () =>
                                                        _confirmRecontinueSubscription(
                                                      context,
                                                      repo,
                                                      c,
                                                      df,
                                                    ),
                                                    icon: const Icon(
                                                      Icons.event_repeat,
                                                      size: 20,
                                                    ),
                                                    label: const Text(
                                                      'Recontinue',
                                                    ),
                                                  ),
                                                  OutlinedButton.icon(
                                                    onPressed: () =>
                                                        _confirmSetInactive(
                                                      context,
                                                      repo,
                                                      c,
                                                    ),
                                                    icon: const Icon(
                                                      Icons
                                                          .person_off_outlined,
                                                      size: 20,
                                                    ),
                                                    label: const Text(
                                                      'Inactive',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (c.skippedDeliveryDays > 0) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Skipped days: ${c.skippedDeliveryDays}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: cs.tertiary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      if (c.skippedDeliveryDates.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Dates: ${c.skippedDeliveryDates.map(df.format).join(', ')}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: cs.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      c.address,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                            height: 1.3,
                                          ),
                                    ),
                                    if (c.requestedDeliveryTime.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Delivery time: ${c.requestedDeliveryTime}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: cs.tertiary,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                            ),
                                          ),
                                          if (c.strictDeliveryTime)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                left: 6,
                                                top: 1,
                                              ),
                                              child: Tooltip(
                                                message: 'Strict delivery time',
                                                child: Icon(
                                                  Icons.schedule,
                                                  size: 18,
                                                  color: cs.error,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                    if (c.notes.trim().isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'Notes',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        c.notes.trim(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                    if (c.lastPaymentAmountRupees != null &&
                                        c.lastPaymentAt != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'Last collected: ₹${c.lastPaymentAmountRupees} · '
                                        '${dtf.format(c.lastPaymentAt!)}'
                                        '${c.lastPaymentKind != null ? ' · ${c.lastPaymentKind}' : ''}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: cs.primary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                      ),
                                    ],
                                    if (!c.active) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'Inactive',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(color: cs.error),
                                      ),
                                    ],
                                    if (c.customerCreated && !c.adminApproved) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'Awaiting admin approval',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: cs.tertiary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (c.deletedAt == null) ...[
                          Divider(
                            height: 22,
                            thickness: 1,
                            color: cs.outlineVariant.withValues(alpha: 0.65),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              alignment: WrapAlignment.end,
                              spacing: 2,
                              runSpacing: 4,
                              children: [
                                IconButton(
                                  style: IconButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: cs.onSurfaceVariant,
                                  ),
                                  icon: const Icon(Icons.receipt_long_outlined),
                                  tooltip: 'Generate receipt',
                                  onPressed: () async {
                                    await showManualReceiptDialog(
                                      context: context,
                                      customer: c,
                                      repo: repo,
                                    );
                                  },
                                ),
                              if (repo.isAdmin && c.customerCreated && !c.adminApproved)
                                IconButton(
                                  style: IconButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: cs.primary,
                                  ),
                                  icon: const Icon(Icons.verified_outlined),
                                  tooltip: 'Approve customer',
                                  onPressed: () async {
                                    await repo.approveCustomer(c.id);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '${c.name} approved by admin.',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              if (repo.isAdmin && c.customerCreated && !c.adminApproved)
                                IconButton(
                                  style: IconButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: cs.error,
                                  ),
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Delete created customer',
                                  onPressed: () async {
                                    final shouldDelete = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Delete customer'),
                                        content: Text(
                                          'Remove "${c.name}" from active lists? '
                                          'They stay in Recently deleted for '
                                          '${Customer.softDeleteRetention.inDays} '
                                          'days so you can restore them.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(false),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(true),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (shouldDelete != true) return;
                                    await repo.deleteCustomer(c.id);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '${c.name} moved to Recently deleted.',
                                        ),
                                      ),
                                  );
                                },
                              ),
                              if (c.skippedDeliveryDates.isNotEmpty)
                                IconButton(
                                  style: IconButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: cs.tertiary,
                                  ),
                                  icon: const Icon(
                                    Icons.event_available_outlined,
                                  ),
                                  tooltip: 'Undo skip',
                                  onPressed: () => unawaited(
                                    _undoSkipForCustomer(
                                      context,
                                      repo,
                                      c,
                                      df,
                                    ),
                                  ),
                                ),
                              IconButton(
                                style: IconButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: cs.onSurfaceVariant,
                                ),
                                icon: const Icon(Icons.event_busy_outlined),
                                tooltip: 'Select skipped date',
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime.now().isBefore(c.startDate)
                                        ? c.startDate
                                        : DateTime.now(),
                                    firstDate: c.startDate,
                                    lastDate: c.endDate.add(const Duration(days: 365)),
                                  );
                                  if (picked == null) return;
                                  await repo.skipDeliveryDate(c.id, picked);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Skipped date saved: ${df.format(picked)}.',
                                      ),
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                style: IconButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: cs.primary,
                                ),
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Edit customer',
                                onPressed: () async {
                                  await Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          AddCustomerScreen(existing: c),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                          ],
                      ],
                    ),
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}
