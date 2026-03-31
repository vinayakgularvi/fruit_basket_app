import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_navigator.dart';
import '../data/app_repository.dart';
import '../utils/payment_receipt_pdf.dart';
import '../utils/schedule_after_frame.dart';
import '../utils/whatsapp_launch.dart';
import '../widgets/collected_amount_dialog.dart';
import '../widgets/payment_undo_snackbar.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matchesSearch(String name, String phone, String query) {
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

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final pending = repo.pendingPayments;
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final q = _search.text;
    final filtered = pending
        .where((p) => _matchesSearch(p.customerName, p.phone, q))
        .toList();
    final totalFiltered =
        filtered.fold<double>(0, (a, p) => a + p.amount);

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
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Search by name or phone',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: q.isNotEmpty
                          ? IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _search.clear();
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
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
                                  q.trim().isEmpty
                                      ? 'Total outstanding'
                                      : 'Outstanding (filtered)',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                Text(
                                  currency.format(totalFiltered),
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
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No matches for your search.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final p = filtered[i];
                            final matches = repo.customers
                                .where((c) => c.id == p.customerId)
                                .toList();
                            final cust =
                                matches.isEmpty ? null : matches.first;
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                              if ((p.phone).isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  p.phone,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                              ],
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
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: FilledButton.tonal(
                                        onPressed: p.kind == null ||
                                                cust == null
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
                                                await repo
                                                    .recordPaymentCollection(
                                                  p.customerId,
                                                  p.kind!,
                                                  collectedAmountRupees:
                                                      amount,
                                                );
                                                if (!context.mounted) {
                                                  return;
                                                }
                                                await scheduleAfterFrame(
                                                    () async {
                                                  final root =
                                                      rootNavigatorContext;
                                                  final dialogCtx = root !=
                                                              null &&
                                                          root.mounted
                                                      ? root
                                                      : context;
                                                  if (!dialogCtx.mounted) {
                                                    return null;
                                                  }
                                                  final action =
                                                      await showDialog<String>(
                                                    context: dialogCtx,
                                                    useRootNavigator: true,
                                                    builder: (ctx) =>
                                                        AlertDialog(
                                                      title: const Text(
                                                        'Payment recorded',
                                                      ),
                                                      content: const Text(
                                                        'Choose receipt action',
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.of(
                                                                      ctx)
                                                                  .pop(
                                                                      'skip',
                                                                    ),
                                                          child: const Text(
                                                            'Skip',
                                                          ),
                                                        ),
                                                        FilledButton(
                                                          onPressed: () =>
                                                              Navigator.of(
                                                                      ctx)
                                                                  .pop('pdf'),
                                                          child: const Text(
                                                            'Download PDF',
                                                          ),
                                                        ),
                                                        FilledButton.tonal(
                                                          onPressed: () =>
                                                              Navigator.of(
                                                                      ctx)
                                                                  .pop('wa'),
                                                          child: const Text(
                                                            'Send WhatsApp',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (!dialogCtx.mounted) {
                                                    return null;
                                                  }
                                                  if (action == 'pdf') {
                                                    await downloadPaymentReceiptPdf(
                                                      customer: cust,
                                                      collectedAmountRupees:
                                                          amount,
                                                      paymentLabel:
                                                          p.dueLabel,
                                                      collectedAt:
                                                          DateTime.now(),
                                                      collectedBy: repo
                                                          .currentUsername,
                                                    );
                                                  } else if (action ==
                                                      'wa') {
                                                    await sendReceiptToWhatsApp(
                                                      dialogCtx,
                                                      customer: cust,
                                                      collectedAmountRupees:
                                                          amount,
                                                      paymentLabel:
                                                          p.dueLabel,
                                                      collectedAt:
                                                          DateTime.now(),
                                                      collectedBy: repo
                                                          .currentUsername,
                                                    );
                                                  }
                                                  if (!dialogCtx.mounted) {
                                                    return null;
                                                  }
                                                  showPaymentRecordedWithUndo(
                                                    dialogCtx,
                                                    repo,
                                                    before,
                                                  );
                                                  return null;
                                                });
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
