import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../models/lead.dart';
import '../utils/phone_launch.dart';

class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key});

  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Lead> _filter(List<Lead> all, String query) {
    if (query.trim().isEmpty) return all;
    final q = query.trim().toLowerCase();
    final qDigits = q.replaceAll(RegExp(r'\D'), '');
    return all.where((l) {
      if (l.name.toLowerCase().contains(q)) return true;
      if (l.mobile.toLowerCase().contains(q)) return true;
      if (qDigits.length >= 3 &&
          l.mobile.replaceAll(RegExp(r'\D'), '').contains(qDigits)) {
        return true;
      }
      if (l.source.toLowerCase().contains(q)) return true;
      return false;
    }).toList();
  }

  String _formatSource(String source) {
    if (source.isEmpty) return '—';
    return source.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final all = repo.leads;
    final items = _filter(all, _search.text);
    final df = DateFormat.yMMMd().add_jm();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leads'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search name, phone, source',
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
          Expanded(
            child: repo.leadsLoading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? Center(
                        child: Text(
                          all.isEmpty
                              ? 'No leads yet. New entries from Firestore will appear here.'
                              : 'No matches for your search.',
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => repo.refreshLeads(),
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final l = items[i];
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            l.name.isNotEmpty ? l.name : '—',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Call',
                                          icon: Icon(
                                            Icons.phone_outlined,
                                            color: cs.primary,
                                          ),
                                          onPressed: l.mobile.isEmpty
                                              ? null
                                              : () => openCustomerPhoneDialer(
                                                    context,
                                                    l.mobile,
                                                  ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        FilterChip(
                                          label: const Text('Called'),
                                          selected: l.called,
                                          onSelected: (v) async {
                                            try {
                                              await repo.updateLeadFollowUp(
                                                l.id,
                                                called: v,
                                              );
                                            } catch (_) {
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Could not save. Check Firestore rules (write).',
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                        ),
                                        FilterChip(
                                          label: const Text('Not interested'),
                                          selected: l.notInterested,
                                          onSelected: (v) async {
                                            try {
                                              await repo.updateLeadFollowUp(
                                                l.id,
                                                notInterested: v,
                                              );
                                            } catch (_) {
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Could not save. Check Firestore rules (write).',
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        if (l.price.isNotEmpty)
                                          Chip(
                                            label: Text(l.price),
                                            visualDensity:
                                                VisualDensity.compact,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                          ),
                                        if (l.plan.isNotEmpty)
                                          Chip(
                                            label: Text(l.plan),
                                            visualDensity:
                                                VisualDensity.compact,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                          ),
                                        if (l.billing.isNotEmpty)
                                          Chip(
                                            label: Text(l.billing),
                                            visualDensity:
                                                VisualDensity.compact,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    _line(
                                      context,
                                      Icons.phone_outlined,
                                      l.mobile.isNotEmpty
                                          ? l.mobile
                                          : '—',
                                    ),
                                    if (l.mealLabel.isNotEmpty)
                                      _line(
                                        context,
                                        Icons.restaurant_outlined,
                                        l.mealLabel,
                                      )
                                    else if (l.meal.isNotEmpty)
                                      _line(
                                        context,
                                        Icons.restaurant_outlined,
                                        l.meal,
                                      ),
                                    if (l.goal.isNotEmpty)
                                      _line(
                                        context,
                                        Icons.flag_outlined,
                                        l.goal,
                                      ),
                                    if (l.calendar.isNotEmpty)
                                      _line(
                                        context,
                                        Icons.calendar_today_outlined,
                                        l.calendar,
                                      ),
                                    _line(
                                      context,
                                      Icons.label_outline,
                                      _formatSource(l.source),
                                    ),
                                    if (l.createdAt != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        df.format(l.createdAt!.toLocal()),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
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

  Widget _line(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
