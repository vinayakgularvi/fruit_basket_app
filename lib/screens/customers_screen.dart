import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../models/customer.dart';
import '../models/delivery_slot.dart';
import 'add_customer_screen.dart';

enum _CustomerFilter { all, morning, evening, activeOnly, inactiveOnly }

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
    var list = all;
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((c) {
        return c.name.toLowerCase().contains(q) ||
            c.phone.toLowerCase().contains(q) ||
            c.address.toLowerCase().contains(q);
      }).toList();
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
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      'No customers match your search.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final c = items[i];
                      final cs = Theme.of(context).colorScheme;
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
                                      c.address,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: cs.onSurfaceVariant),
                                    ),
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
