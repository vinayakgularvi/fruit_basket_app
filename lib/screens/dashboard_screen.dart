import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../models/customer_list_filter.dart';

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

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final deliveryOnly = repo.isDeliveryAgent;
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
          const SizedBox(height: 8),
          Text(
            'Healthy subs · morning & evening',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
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
          if (fruitBuyerHome) ...[
            const SizedBox(height: 28),
            Text(
              'Quick tips',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Use the Buy fruits tab to maintain the shopping list. '
                  'Pull down on that screen to refresh from the server.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ],
          if (!deliveryOnly && !fruitBuyerHome) ...[
            const SizedBox(height: 28),
            Text(
              'Quick tips',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.wb_sunny_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Morning window',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pack fruit boxes first; chilled items last.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          Icons.nights_stay_outlined,
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Evening window',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Confirm meal counts before leaving the kitchen.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ],
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
