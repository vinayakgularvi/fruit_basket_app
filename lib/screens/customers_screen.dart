import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import 'package:intl/intl.dart';

import '../models/customer.dart';
import '../models/delivery_slot.dart';
import '../models/subscription_plan.dart';
import 'add_customer_screen.dart';
import '../widgets/manual_receipt_dialog.dart';

enum _CustomerFilter {
  all,
  morning,
  evening,
  activeOnly,
  inactiveOnly,
  createdPendingApproval,
}

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _search = TextEditingController();
  _CustomerFilter _filter = _CustomerFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Customer> _apply(
    List<Customer> all,
    String query,
    _CustomerFilter f,
  ) {
    // `repo.customers` is unmodifiable; sort() requires a mutable list.
    var list = List<Customer>.from(all);
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((c) {
        return c.name.toLowerCase().contains(q) ||
            c.phone.toLowerCase().contains(q) ||
            c.address.toLowerCase().contains(q);
      }).toList();
    }
    final hideInactiveByDefault = f == _CustomerFilter.all ||
        f == _CustomerFilter.morning ||
        f == _CustomerFilter.evening;
    if (hideInactiveByDefault) {
      list = list.where((c) => c.active).toList();
    }

    switch (f) {
      case _CustomerFilter.all:
        break;
      case _CustomerFilter.morning:
        list =
            list.where((c) => c.preferredSlot == DeliverySlot.morning).toList();
        break;
      case _CustomerFilter.evening:
        list =
            list.where((c) => c.preferredSlot == DeliverySlot.evening).toList();
        break;
      case _CustomerFilter.activeOnly:
        list = list.where((c) => c.active).toList();
        break;
      case _CustomerFilter.inactiveOnly:
        list = list.where((c) => !c.active).toList();
        break;
      case _CustomerFilter.createdPendingApproval:
        list = list
            .where((c) => c.customerCreated && !c.adminApproved)
            .toList();
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
        title: const Text('Customers'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const AddCustomerScreen()),
          );
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
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _filter == _CustomerFilter.all,
                  onSelected: () => setState(() => _filter = _CustomerFilter.all),
                ),
                _FilterChip(
                  label: 'Morning',
                  selected: _filter == _CustomerFilter.morning,
                  onSelected: () =>
                      setState(() => _filter = _CustomerFilter.morning),
                ),
                _FilterChip(
                  label: 'Evening',
                  selected: _filter == _CustomerFilter.evening,
                  onSelected: () =>
                      setState(() => _filter = _CustomerFilter.evening),
                ),
                _FilterChip(
                  label: 'Active',
                  selected: _filter == _CustomerFilter.activeOnly,
                  onSelected: () =>
                      setState(() => _filter = _CustomerFilter.activeOnly),
                ),
                _FilterChip(
                  label: 'Inactive',
                  selected: _filter == _CustomerFilter.inactiveOnly,
                  onSelected: () =>
                      setState(() => _filter = _CustomerFilter.inactiveOnly),
                ),
                _FilterChip(
                  label: 'Customer created',
                  selected: _filter == _CustomerFilter.createdPendingApproval,
                  onSelected: () => setState(
                    () => _filter = _CustomerFilter.createdPendingApproval,
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
                                    'No customers match your search.',
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
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final c = items[i];
                      final cs = Theme.of(context).colorScheme;
                      final df = DateFormat.yMMMd();
                      final dtf = DateFormat.yMMMd().add_jm();
                      final periodShort =
                          c.billingPeriod == BillingPeriod.weekly ? 'wk' : 'mo';
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                child: Text(
                                  c.name.isNotEmpty
                                      ? c.name[0].toUpperCase()
                                      : '?',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                                .titleMedium,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Chip(
                                          label: Text(c.preferredSlot.label),
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          padding: EdgeInsets.zero,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      c.phone,
                                      style:
                                          Theme.of(context).textTheme.bodyMedium,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${c.planTier.title} · ₹${c.planPriceRupees}/$periodShort · ${df.format(c.startDate)} → ${df.format(c.endDate)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: cs.primary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
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
                                    const SizedBox(height: 2),
                                    Text(
                                      c.address,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: cs.onSurfaceVariant),
                                    ),
                                    if (c.requestedDeliveryTime.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Delivery time: ${c.requestedDeliveryTime}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: cs.tertiary,
                                              fontWeight: FontWeight.w500,
                                            ),
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
                              IconButton(
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
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Delete created customer',
                                  onPressed: () async {
                                    final shouldDelete = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Delete customer'),
                                        content: Text(
                                          'Delete "${c.name}"? This cannot be undone.',
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
                                          '${c.name} deleted.',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              IconButton(
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
