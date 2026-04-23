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
    final anchor = paymentScheduleAnchorDate(c, today);
    final pStart = periodStartForDate(c, anchor);
    if (pStart == null) return 0;
    final due = paymentDueForCustomer(c, anchor);
    final total = c.totalPlanPriceRupees;
    if (due == null) return total;
    return (total - due.amountRupees).clamp(0, total);
  }

  /// Outstanding for today’s rules (0 if none due).
  int _remainingForCustomer(Customer c, DateTime today) {
    if (!c.active) return 0;
    final anchor = paymentScheduleAnchorDate(c, today);
    final due = paymentDueForCustomer(c, anchor);
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

  bool _canEditPeriodAmounts(Customer c, DateTime today) {
    if (!c.active) return false;
    final anchor = paymentScheduleAnchorDate(c, today);
    return periodStartForDate(c, anchor) != null;
  }

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
                  'Plan total is ₹${c.totalPlanPriceRupees} · adjusts what is still due',
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
        .toList()
      ..sort((a, b) {
        final ra = _remainingForCustomer(a, today);
        final rb = _remainingForCustomer(b, today);
        final za = ra == 0;
        final zb = rb == 0;
        if (za != zb) {
          return za ? 1 : -1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    var totalPlanAmount = 0;
    var totalPaid = 0;
    var totalRemaining = 0;
    for (final c in repo.activeCustomers()) {
      totalPlanAmount += c.totalPlanPriceRupees;
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
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Active customers · current period',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _SummaryTile(
                                  icon: Icons.account_balance_wallet_outlined,
                                  label: 'Total payment',
                                  value: currency.format(totalPlanAmount),
                                  color: Theme.of(context).colorScheme.tertiary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _SummaryTile(
                                  icon: Icons.payments_outlined,
                                  label: 'Collected',
                                  value: currency.format(totalPaid),
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
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
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, i) {
                            final c = filtered[i];
                            final pmt = _pendingPaymentFor(pending, c.id);
                            final paid = _paidInCurrentPeriod(c, today);
                            final remaining = _remainingForCustomer(c, today);
                            final cs = Theme.of(context).colorScheme;
                            final inBillingWindow =
                                periodStartForDate(c, today) != null;
                            final canEditPeriod =
                                _canEditPeriodAmounts(c, today);
                            final canCollect =
                                pmt != null && pmt.kind != null;

                            Future<void> onCollectPressed() async {
                              if (!inBillingWindow) {
                                await showDialog<void>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Outside billing period'),
                                    content: const Text(
                                      'This customer is currently outside the '
                                      'active billing period, so payment '
                                      'collection is not available. You can '
                                      'still use Edit paid / Edit remaining to '
                                      'correct amounts for the nearest '
                                      'subscription segment.',
                                    ),
                                    actions: [
                                      FilledButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('OK'),
                                      ),
                                    ],
                                  ),
                                );
                                return;
                              }
                              if (!canCollect) {
                                final choice = await showDialog<String>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('No payment due'),
                                    content: const Text(
                                      'Nothing is scheduled to collect for '
                                      'this billing period. Use Edit paid or '
                                      'Edit remaining if you need to change amounts.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, 'close'),
                                        child: const Text('Close'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, 'paid'),
                                        child: const Text('Edit paid'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, 'due'),
                                        child: const Text('Edit remaining'),
                                      ),
                                    ],
                                  ),
                                );
                                if (!context.mounted) return;
                                if (choice == 'paid') {
                                  await _editPaid(context, repo, c, today);
                                } else if (choice == 'due') {
                                  await _editDue(context, repo, c, today);
                                }
                                return;
                              }

                              final before = c;
                              final amount = await showCollectedAmountDialog(
                                context,
                                suggestedRupees: pmt.amount.round(),
                                title: 'Add Payment — ${pmt.customerName}',
                              );
                              if (!context.mounted || amount == null) {
                                return;
                              }
                              await repo.recordPaymentCollection(
                                pmt.customerId,
                                pmt.kind!,
                                collectedAmountRupees: amount,
                              );
                              if (!context.mounted) {
                                return;
                              }
                              await scheduleAfterFrame(() async {
                                final root = rootNavigatorContext;
                                final dialogCtx =
                                    root != null && root.mounted ? root : context;
                                if (!dialogCtx.mounted) {
                                  return null;
                                }
                                final action = await showDialog<String>(
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
                                    collectedAmountRupees: amount,
                                    paymentLabel: pmt.dueLabel,
                                    collectedAt: DateTime.now(),
                                    collectedBy: repo.currentUsername,
                                  );
                                } else if (action == 'wa') {
                                  await sendReceiptToWhatsApp(
                                    dialogCtx,
                                    customer: c,
                                    collectedAmountRupees: amount,
                                    paymentLabel: pmt.dueLabel,
                                    collectedAt: DateTime.now(),
                                    collectedBy: repo.currentUsername,
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
                            }

                            return Card(
                              elevation: 0,
                              color: cs.surfaceContainerLow,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: cs.outlineVariant.withValues(alpha: 0.55),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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
                                                    .titleSmall
                                                    ?.copyWith(
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                              ),
                                              if (c.phone.isNotEmpty) ...[
                                                const SizedBox(height: 2),
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
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        _AmountBadge(
                                          label: 'Total',
                                          value: currency.format(
                                            c.totalPlanPriceRupees,
                                          ),
                                          color: cs.tertiary,
                                        ),
                                        _AmountBadge(
                                          label: 'Paid',
                                          value: currency.format(paid),
                                          color: cs.primary,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: _AmountBadge(
                                            label: 'Remaining',
                                            value: remaining > 0
                                                ? currency.format(remaining)
                                                : currency.format(0),
                                            color: remaining > 0
                                                ? cs.error
                                                : cs.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            if (remaining > 0) ...[
                                              OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      const Color(0xFF25D366),
                                                  side: const BorderSide(
                                                    color: Color(0xFF25D366),
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                                  tapTargetSize: MaterialTapTargetSize
                                                      .shrinkWrap,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                                icon: const Icon(
                                                  Icons.chat_outlined,
                                                  size: 16,
                                                ),
                                                label: const Text(
                                                  'Send msg',
                                                  style: TextStyle(fontSize: 12),
                                                ),
                                                onPressed: () =>
                                                    openPaymentPendingWhatsApp(
                                                  context,
                                                  phone: c.phone,
                                                  remainingRupees: remaining,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                            ] else if (remaining == 0 &&
                                                repo.isAdmin) ...[
                                              OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: cs.error,
                                                  side: BorderSide(
                                                    color: cs.error,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                                  tapTargetSize: MaterialTapTargetSize
                                                      .shrinkWrap,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 16,
                                                ),
                                                label: const Text(
                                                  'Delete',
                                                  style: TextStyle(fontSize: 12),
                                                ),
                                                onPressed: () async {
                                                  final shouldDelete =
                                                      await showDialog<bool>(
                                                    context: context,
                                                    builder: (ctx) =>
                                                        AlertDialog(
                                                      title: const Text(
                                                        'Delete customer',
                                                      ),
                                                      content: Text(
                                                        'Delete "${c.name}"? '
                                                        'This cannot be undone.',
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.of(ctx)
                                                                  .pop(false),
                                                          child:
                                                              const Text('Cancel'),
                                                        ),
                                                        FilledButton(
                                                          onPressed: () =>
                                                              Navigator.of(ctx)
                                                                  .pop(true),
                                                          child: const Text(
                                                            'Delete',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (shouldDelete != true ||
                                                      !context.mounted) {
                                                    return;
                                                  }
                                                  await repo.deleteCustomer(c.id);
                                                  if (!context.mounted) return;
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        '${c.name} deleted.',
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                              const SizedBox(height: 4),
                                            ],
                                            FilledButton.icon(
                                              style: FilledButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 6,
                                                ),
                                                tapTargetSize: MaterialTapTargetSize
                                                    .shrinkWrap,
                                              ),
                                              icon: const Icon(
                                                Icons.payments_outlined,
                                                size: 16,
                                              ),
                                              onPressed: onCollectPressed,
                                              label: Text(
                                                !inBillingWindow
                                                    ? 'Outside period'
                                                    : remaining > 0
                                                        ? 'Collect payment'
                                                        : 'No payment due',
                                                style:
                                                    const TextStyle(fontSize: 13),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    if (canEditPeriod) ...[
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 0,
                                        runSpacing: 0,
                                        children: [
                                          TextButton.icon(
                                            style: TextButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 4,
                                              ),
                                              visualDensity: VisualDensity.compact,
                                              tapTargetSize:
                                                  MaterialTapTargetSize.shrinkWrap,
                                            ),
                                            onPressed: () => _editPaid(
                                              context,
                                              repo,
                                              c,
                                              today,
                                            ),
                                            icon: Icon(
                                              Icons.edit_outlined,
                                              size: 14,
                                              color: cs.primary,
                                            ),
                                            label: Text(
                                              'Edit paid',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: cs.primary,
                                              ),
                                            ),
                                          ),
                                          TextButton.icon(
                                            style: TextButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 4,
                                              ),
                                              visualDensity: VisualDensity.compact,
                                              tapTargetSize:
                                                  MaterialTapTargetSize.shrinkWrap,
                                            ),
                                            onPressed: () => _editDue(
                                              context,
                                              repo,
                                              c,
                                              today,
                                            ),
                                            icon: Icon(
                                              Icons.edit_outlined,
                                              size: 14,
                                              color: cs.error,
                                            ),
                                            label: Text(
                                              'Edit remaining',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: cs.error,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
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
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
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

class _AmountBadge extends StatelessWidget {
  const _AmountBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 10,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
