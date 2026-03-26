import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../utils/delivery_plan_dates.dart';
import '../utils/payment_schedule.dart';
import '../widgets/collected_amount_dialog.dart';
import '../widgets/payment_undo_snackbar.dart';

class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final pending = repo.pendingPayments;
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments'),
      ),
      body: pending.isEmpty
          ? Center(
              child: Text(
                'No pending payments. Great work!',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total outstanding',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                Text(
                                  currency.format(repo.totalPendingAmount),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Pending',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: pending.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final p = pending[i];
                      final matches = repo.customers
                          .where((c) => c.id == p.customerId)
                          .toList();
                      final cust =
                          matches.isEmpty ? null : matches.first;
                      final dueNextDay = cust == null
                          ? null
                          : paymentDueForNextCalendarDay(
                              cust,
                              dateOnly(DateTime.now()),
                            );
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.customerName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          p.dueLabel,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    currency.format(p.amount),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ],
                              ),
                              if (dueNextDay != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Next day: ₹${dueNextDay.amountRupees} · ${dueNextDay.label}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.tonal(
                                  onPressed: p.kind == null || cust == null
                                      ? null
                                      : () async {
                                          final before = cust;
                                          final amount =
                                              await showCollectedAmountDialog(
                                            context,
                                            suggestedRupees:
                                                p.amount.round(),
                                            title:
                                                'Mark paid — ${p.customerName}',
                                          );
                                          if (!context.mounted ||
                                              amount == null) {
                                            return;
                                          }
                                          await repo.recordPaymentCollection(
                                            p.customerId,
                                            p.kind!,
                                            collectedAmountRupees: amount,
                                          );
                                          if (!context.mounted) return;
                                          showPaymentRecordedWithUndo(
                                            context,
                                            repo,
                                            before,
                                          );
                                        },
                                  child: const Text('Mark paid'),
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
