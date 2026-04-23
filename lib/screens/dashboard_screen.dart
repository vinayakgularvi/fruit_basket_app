import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../models/customer_list_filter.dart';
import '../models/delivery_slot.dart';
import '../utils/production_prep_totals.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, this.onOpenCustomersFilter});

  /// Admin: open Customers tab with this filter. Null = stat cards are not links.
  final void Function(CustomerListFilter filter)? onOpenCustomersFilter;

  Future<void> _showAddDeliveryAgentDialog(BuildContext context) async {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add delivery agent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: userCtrl,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
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
    if (ok == true && context.mounted) {
      final u = userCtrl.text.trim();
      final p = passCtrl.text.trim();
      if (u.isNotEmpty && p.isNotEmpty) {
        await context.read<AppRepository>().addDeliveryAgentUser(
              username: u,
              password: p,
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delivery agent "$u" added')),
          );
        }
      }
    }
    userCtrl.dispose();
    passCtrl.dispose();
  }

  Future<void> _showAddFruitBuyerDialog(BuildContext context) async {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add fruit buyer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: userCtrl,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
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
    if (ok == true && context.mounted) {
      final u = userCtrl.text.trim();
      final p = passCtrl.text.trim();
      if (u.isNotEmpty && p.isNotEmpty) {
        await context.read<AppRepository>().addFruitBuyerUser(
              username: u,
              password: p,
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fruit buyer "$u" added')),
          );
        }
      }
    }
    userCtrl.dispose();
    passCtrl.dispose();
  }

  Future<void> _showEditDeliveryAgentPayDialog(BuildContext context) async {
    final repo = context.read<AppRepository>();
    final agents = repo.deliveryAgentUsernames;
    if (agents.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No delivery agents found')),
      );
      return;
    }
    var selected = agents.first;
    final weeklyCtrl = TextEditingController(
      text: '${repo.deliveryAgentWeeklyAllowanceRupees(selected)}',
    );
    final perOrderCtrl = TextEditingController(
      text: '${repo.deliveryAgentPerOrderRupees(selected)}',
    );

    int parseAmount(String raw) => int.tryParse(raw.trim()) ?? 0;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            final weekly = parseAmount(weeklyCtrl.text);
            final perOrder = parseAmount(perOrderCtrl.text);
            final monthly = repo.estimatedMonthlyCompensationRupees(
              selected,
              weeklyAllowanceRupees: weekly,
              perOrderRupees: perOrder,
            );
            final monthlyOrders = repo.estimatedMonthlyOrdersForAgent(selected);
            return AlertDialog(
              title: const Text('Delivery agent pay'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selected,
                    decoration: const InputDecoration(labelText: 'Agent'),
                    items: agents
                        .map(
                          (u) => DropdownMenuItem<String>(
                            value: u,
                            child: Text(u),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setLocal(() {
                        selected = v;
                        weeklyCtrl.text =
                            '${repo.deliveryAgentWeeklyAllowanceRupees(v)}';
                        perOrderCtrl.text = '${repo.deliveryAgentPerOrderRupees(v)}';
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: weeklyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Weekly allowance (₹)',
                      prefixText: '₹ ',
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: perOrderCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Per order price (₹)',
                      prefixText: '₹ ',
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Auto monthly total: ₹$monthly',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Formula: (weekly allowance × 4) + '
                    '(per order × $monthlyOrders estimated monthly orders)',
                    style: Theme.of(context).textTheme.bodySmall,
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
            );
          },
        );
      },
    );

    if (saved == true && context.mounted) {
      await repo.updateDeliveryAgentCompensation(
        username: selected,
        weeklyAllowanceRupees: parseAmount(weeklyCtrl.text),
        perOrderRupees: parseAmount(perOrderCtrl.text),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated pay for "$selected"')),
        );
      }
    }
    weeklyCtrl.dispose();
    perOrderCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final deliveryOnly = repo.isDeliveryAgent;
    final currentAgent = repo.currentUsername ?? '';
    final weeklyAllowance = deliveryOnly
        ? repo.deliveryAgentWeeklyAllowanceRupees(currentAgent)
        : 0;
    final monthlyOrders = deliveryOnly
        ? repo.estimatedMonthlyOrdersForAgent(currentAgent)
        : 0;
    final monthlyEarnTotal = deliveryOnly
        ? repo.estimatedMonthlyCompensationRupees(currentAgent)
        : 0;
    final fruitBuyerHome =
        repo.isFruitBuyer && !repo.isAdmin && !repo.isDeliveryAgent;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fruit Basket'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            DateFormat('EEEE, MMM d').format(DateTime.now()),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          if (!deliveryOnly) const _ProductionPrepPackSection(),
          if (repo.isAdmin) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showAddDeliveryAgentDialog(context),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Add delivery agent'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showAddFruitBuyerDialog(context),
                  icon: const Icon(Icons.shopping_basket_outlined),
                  label: const Text('Add fruit buyer'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showEditDeliveryAgentPayDialog(context),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Delivery agent pay'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final wide = w > 560;
              final openCustomers = onOpenCustomersFilter;
              final cards = deliveryOnly
                  ? [
                      _StatCard(
                        icon: Icons.local_shipping,
                        label: 'Today’s deliveries',
                        value: '${repo.todayDeliveryCount}',
                        subtitle: 'stops planned',
                      ),
                      _StatCard(
                        icon: Icons.today_outlined,
                        label: 'Last day of plan',
                        value: '${repo.lastDayActiveCustomerCount}',
                        subtitle: 'active · subscription ends today',
                        onTap: openCustomers == null
                            ? null
                            : () =>
                                openCustomers(CustomerListFilter.lastDayOfPlan),
                      ),
                      _StatCard(
                        icon: Icons.currency_rupee,
                        label: 'Monthly revenue',
                        value: currency.format(13000),
                        subtitle: 'fixed monthly target',
                      ),
                      _StatCard(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Today payout',
                        value: currency.format(repo.todayDeliveryPayoutRupees),
                        subtitle:
                            '₹${repo.perOrderPayoutRupees} per order × ${repo.todayDeliveryCount}',
                      ),
                      if (weeklyAllowance > 0)
                        _StatCard(
                          icon: Icons.payments_outlined,
                          label: 'Weekly allowance',
                          value: currency.format(weeklyAllowance),
                          subtitle: 'Fixed weekly amount',
                        ),
                      _StatCard(
                        icon: Icons.trending_up,
                        label: 'Total you can earn',
                        value: currency.format(monthlyEarnTotal),
                        subtitle:
                            '(₹${repo.perOrderPayoutRupees} × $monthlyOrders orders) + '
                            '₹${weeklyAllowance * 4}/month allowance',
                      ),
                    ]
                  : fruitBuyerHome
                      ? [
                          _StatCard(
                            icon: Icons.shopping_basket_outlined,
                            label: 'To buy',
                            value: repo.neededFruitsLoading
                                ? '…'
                                : '${repo.pendingNeededFruitCount}',
                            subtitle: 'items still to purchase',
                          ),
                          const _StatCard(
                            icon: Icons.storefront_outlined,
                            label: 'Procurement',
                            value: 'Buy fruits',
                            subtitle: 'Add or edit what to purchase',
                          ),
                        ]
                      : [
                      _StatCard(
                        icon: Icons.local_shipping,
                        label: 'Today’s deliveries',
                        value: '${repo.todayDeliveryCount}',
                        subtitle: 'stops planned',
                      ),
                      _StatCard(
                        icon: Icons.today_outlined,
                        label: 'Last day of plan',
                        value: '${repo.lastDayActiveCustomerCount}',
                        subtitle: 'active · subscription ends today',
                        onTap: openCustomers == null
                            ? null
                            : () =>
                                openCustomers(CustomerListFilter.lastDayOfPlan),
                      ),
                      _StatCard(
                        icon: Icons.people,
                        label: 'Active customers',
                        value: '${repo.activeCustomers().length}',
                        subtitle: 'on subscription',
                      ),
                      _StatCard(
                        icon: Icons.person_add_alt_1,
                        label: 'New customers created',
                        value: '${repo.newCustomersPendingApprovalCount}',
                        subtitle: 'awaiting admin approval',
                        onTap: openCustomers == null
                            ? null
                            : () => openCustomers(
                                  CustomerListFilter.createdPendingApproval,
                                ),
                      ),
                      _StatCard(
                        icon: Icons.currency_rupee,
                        label: 'Subscription revenue',
                        value: currency.format(repo.monthlyRevenueEstimate),
                        subtitle: '≈ monthly from all active plan prices',
                      ),
                      _StatCard(
                        icon: Icons.payments_outlined,
                        label: 'Pending payments',
                        value: currency.format(repo.totalPendingAmount),
                        subtitle: repo.pendingPayments.isEmpty
                            ? 'none due'
                            : '${repo.pendingPayments.length} to collect',
                      ),
                    ];
              if (wide) {
                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: w > 900 ? 1.5 : 1.35,
                  children: cards,
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    cards[i],
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => context.read<AppRepository>().logout(),
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}

/// Kitchen prep counts by time: before 11 = today morning; 11–8pm = today evening;
/// after 8pm = next delivery-day morning (Sunday skipped).
class _ProductionPrepPackSection extends StatefulWidget {
  const _ProductionPrepPackSection();

  @override
  State<_ProductionPrepPackSection> createState() =>
      _ProductionPrepPackSectionState();
}

class _ProductionPrepPackSectionState extends State<_ProductionPrepPackSection> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final cs = Theme.of(context).colorScheme;
    final dayFmt = DateFormat.yMMMEd();
    final schedule = resolveProductionPrepScheduleView(DateTime.now());
    final counts = productionPackCountsForDaySlot(
      repo.customers,
      schedule.calendarDay,
      schedule.slot,
    );
    final stops = repo.customers
        .where(
          (c) => isCustomerCountedForProductionPrep(
            c,
            schedule.calendarDay,
            schedule.slot,
          ),
        )
        .length;
    final units = totalPackUnits(counts);
    const order = ProductionPackBucket.values;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.inventory_2_outlined, color: cs.primary, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        schedule.title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${dayFmt.format(schedule.calendarDay)} · '
                        '${schedule.slot.label} · '
                        '$stops stops · $units lines',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...order.map((b) {
              final n = counts[b] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        b.shortLabel,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Text(
                      '$n',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.primary, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: cs.onSurfaceVariant,
              size: 22,
            ),
          ],
        ],
      ),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? child
          : InkWell(
              onTap: onTap,
              child: child,
            ),
    );
  }
}
