import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_navigator.dart';
import '../data/app_repository.dart';
import '../models/customer.dart';
import '../models/payment.dart';
import '../utils/delivery_plan_dates.dart';
import '../utils/payment_receipt_pdf.dart';
import '../utils/payment_schedule.dart';
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

  /// Amount already collected toward the current billing period (estimate from due vs plan).
  int _paidInCurrentPeriod(Customer c, DateTime today) {
    if (!c.active) return 0;
    final pStart = periodStartForDate(c, today);
    if (pStart == null) return 0;
    final due = paymentDueForCustomer(c, today);
    if (due == null) return c.planPriceRupees;
    return (c.planPriceRupees - due.amountRupees).clamp(0, c.planPriceRupees);
  }

  /// Outstanding for today’s rules (0 if none due).
  int _remainingForCustomer(Customer c, DateTime today) {
    if (!c.active) return 0;
    final due = paymentDueForCustomer(c, today);
    return due?.amountRupees ?? 0;
  }

  Payment? _pendingPaymentFor(
    List<Payment> pending,
    String customerId,
  ) {
    for (final p in pending) {
      if (p.customerId == customerId) return p;
    }
    return null;
  }

  bool _canEditPeriodAmounts(Customer c, DateTime today) =>
      c.active && periodStartForDate(c, today) != null;

  Future<void> _editDue(
    BuildContext context,
    AppRepository repo,
    Customer c,
    DateTime today,
  ) async {
    if (!_canEditPeriodAmounts(c, today)) return;
    final controller = TextEditingController(
      text: '${_remainingForCustomer(c, today)}',
    );
    bool? ok;
    late final String entered;
    try {
      ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Due — ${c.name}'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Amount due (₹)',
              helperText: '0 = nothing owed for this period',
            ),
            autofocus: true,
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
    } finally {
      entered = controller.text;
      controller.dispose();
    }
    if (ok != true || !context.mounted) return;
    final v = int.tryParse(entered.trim());
    if (v == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid number')),
      );
      return;
    }
    await repo.adjustDueAmountForCurrentPeriod(c.id, v);
  }

  Future<void> _editPaid(
    BuildContext context,
    AppRepository repo,
    Customer c,
    DateTime today,
  ) async {
    if (!_canEditPeriodAmounts(c, today)) return;
    final controller = TextEditingController(
      text: '${_paidInCurrentPeriod(c, today)}',
    );
    bool? ok;
    late final String entered;
    try {
      ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Paid (period) — ${c.name}'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Amount paid (₹)',
              helperText:
                  'Plan is ₹${c.planPriceRupees} · adjusts what is still due',
            ),
            autofocus: true,
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
    } finally {
      entered = controller.text;
      controller.dispose();
    }
    if (ok != true || !context.mounted) return;
    final v = int.tryParse(entered.trim());
    if (v == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid number')),
      );
      return;
    }
    await repo.adjustPaidInCurrentPeriod(c.id, v);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final pending = repo.pendingPayments;
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final q = _search.text;
    final today = dateOnly(DateTime.now());

    final activeOnly = List<Customer>.from(repo.activeCustomers())
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

    final filtered = activeOnly
        .where((c) => _matchesSearch(c.name, c.phone, q))
        .toList();

    var totalPaid = 0;
    var totalRemaining = 0;
    for (final c in repo.activeCustomers()) {
      totalPaid += _paidInCurrentPeriod(c, today);
      totalRemaining += _remainingForCustomer(c, today);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments'),
      ),
      body: repo.customersLoading
          ? const Center(child: CircularProgressIndicator())
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Active customers · current period',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _SummaryTile(
                                  icon: Icons.payments_outlined,
                                  label: 'Total paid',
                                  value: currency.format(totalPaid),
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _SummaryTile(
                                  icon: Icons.pending_outlined,
                                  label: 'Remaining',
                                  value: currency.format(totalRemaining),
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
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
                            q.trim().isEmpty
                                ? 'No customers yet.'
                                : 'No matches for your search.',
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
                            final c = filtered[i];
                            final pmt = _pendingPaymentFor(pending, c.id);
                            final paid = _paidInCurrentPeriod(c, today);
                            final remaining = _remainingForCustomer(c, today);
                            final cs = Theme.of(context).colorScheme;

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
                                                c.name,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium,
                                              ),
                                              if (c.phone.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  c.phone,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: cs
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Paid (period): ${currency.format(paid)}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        color: cs.primary,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                ),
                                              ),
                                              IconButton(
                                                tooltip:
                                                    'Edit paid (this period)',
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 18,
                                                ),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(
                                                  minWidth: 28,
                                                  minHeight: 28,
                                                ),
                                                onPressed: _canEditPeriodAmounts(
                                                        c, today)
                                                    ? () => _editPaid(
                                                          context,
                                                          repo,
                                                          c,
                                                          today,
                                                        )
                                                    : null,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  remaining > 0
                                                      ? 'Due: ${currency.format(remaining)}'
                                                      : 'Due: —',
                                                  textAlign: TextAlign.end,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        color: remaining > 0
                                                            ? cs.error
                                                            : cs
                                                                .onSurfaceVariant,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: 'Edit amount due',
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 18,
                                                ),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(
                                                  minWidth: 28,
                                                  minHeight: 28,
                                                ),
                                                onPressed: _canEditPeriodAmounts(
                                                        c, today)
                                                    ? () => _editDue(
                                                          context,
                                                          repo,
                                                          c,
                                                          today,
                                                        )
                                                    : null,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: FilledButton.tonal(
                                        onPressed: pmt == null ||
                                                pmt.kind == null
                                            ? null
                                            : () async {
                                                final before = c;
                                                final amount =
                                                    await showCollectedAmountDialog(
                                                  context,
                                                  suggestedRupees:
                                                      pmt.amount.round(),
                                                  title:
                                                      'Add Payment — ${pmt.customerName}',
                                                );
                                                if (!context.mounted ||
                                                    amount == null) {
                                                  return;
                                                }
                                                await repo
                                                    .recordPaymentCollection(
                                                  pmt.customerId,
                                                  pmt.kind!,
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
                                                        const _PaymentRecordedReceiptDialog(),
                                                  );
                                                  if (!dialogCtx.mounted) {
                                                    return null;
                                                  }
                                                  if (action == 'pdf') {
                                                    await downloadPaymentReceiptPdf(
                                                      customer: c,
                                                      collectedAmountRupees:
                                                          amount,
                                                      paymentLabel:
                                                          pmt.dueLabel,
                                                      collectedAt:
                                                          DateTime.now(),
                                                      collectedBy: repo
                                                          .currentUsername,
                                                    );
                                                  } else if (action ==
                                                      'wa') {
                                                    await sendReceiptToWhatsApp(
                                                      dialogCtx,
                                                      customer: c,
                                                      collectedAmountRupees:
                                                          amount,
                                                      paymentLabel:
                                                          pmt.dueLabel,
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
                                        child: const Text('Add Payment'),
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

/// Receipt choice after recording a payment; closes with [Navigator.pop] `'skip'`
/// after 5 seconds if the user does not choose PDF or WhatsApp.
class _PaymentRecordedReceiptDialog extends StatefulWidget {
  const _PaymentRecordedReceiptDialog();

  @override
  State<_PaymentRecordedReceiptDialog> createState() =>
      _PaymentRecordedReceiptDialogState();
}

class _PaymentRecordedReceiptDialogState
    extends State<_PaymentRecordedReceiptDialog> {
  Timer? _autoClose;

  @override
  void initState() {
    super.initState();
    _autoClose = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      Navigator.of(context).pop('skip');
    });
  }

  @override
  void dispose() {
    _autoClose?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Payment recorded'),
      content: const Text('Choose receipt action'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('skip'),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop('pdf'),
          child: const Text('Download PDF'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop('wa'),
          child: const Text('Send WhatsApp'),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
