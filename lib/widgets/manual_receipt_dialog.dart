import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_navigator.dart';
import '../data/app_repository.dart';
import '../models/customer.dart';
import '../models/subscription_plan.dart';
import '../utils/payment_receipt_pdf.dart';

/// Dialog to generate a PDF receipt with prefilled customer details and amount.
Future<void> showManualReceiptDialog({
  required BuildContext context,
  required Customer customer,
  required AppRepository repo,
}) async {
  final root = rootNavigatorContext;
  final dialogCtx = root != null && root.mounted ? root : context;
  if (!dialogCtx.mounted) return;

  final nameCtrl = TextEditingController(text: customer.name);
  final phoneCtrl = TextEditingController(text: customer.phone);
  final planCtrl = TextEditingController(
    text: _planSummary(customer),
  );
  final amountCtrl = TextEditingController(
    text: '${customer.planPriceRupees}',
  );
  var collectedAt = DateTime.now();
  final dateFmt = DateFormat('dd MMM yyyy');
  final timeFmt = DateFormat('hh:mm a');

  try {
    await showDialog<void>(
      context: dialogCtx,
      useRootNavigator: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('Generate receipt'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: planCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Plan',
                        hintText: 'Shown as payment description on receipt',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        border: OutlineInputBorder(),
                        prefixText: '₹ ',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: collectedAt,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked == null) return;
                              setStateDialog(() {
                                collectedAt = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                  collectedAt.hour,
                                  collectedAt.minute,
                                );
                              });
                            },
                            icon: const Icon(Icons.calendar_today_outlined),
                            label: Text(dateFmt.format(collectedAt)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: ctx,
                                initialTime: TimeOfDay.fromDateTime(collectedAt),
                              );
                              if (picked == null) return;
                              setStateDialog(() {
                                collectedAt = DateTime(
                                  collectedAt.year,
                                  collectedAt.month,
                                  collectedAt.day,
                                  picked.hour,
                                  picked.minute,
                                );
                              });
                            },
                            icon: const Icon(Icons.schedule_outlined),
                            label: Text(timeFmt.format(collectedAt)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final amt = int.tryParse(amountCtrl.text.trim());
                    if (name.isEmpty || amt == null || amt < 0) {
                      return;
                    }
                    final phone = phoneCtrl.text.trim();
                    final planLabel = planCtrl.text.trim().isEmpty
                        ? 'Payment'
                        : planCtrl.text.trim();
                    final forCustomer = customer.copyWith(
                      name: name,
                      phone: phone,
                    );
                    final selectedCollectedAt = collectedAt;
                    Navigator.pop(ctx);
                    await downloadPaymentReceiptPdf(
                      customer: forCustomer,
                      collectedAmountRupees: amt,
                      paymentLabel: planLabel,
                      collectedAt: selectedCollectedAt,
                      collectedBy: repo.currentUsername,
                    );
                  },
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Generate receipt'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    planCtrl.dispose();
    amountCtrl.dispose();
  }
}

String _planSummary(Customer c) {
  final unit = c.billingPeriod.priceUnitWord;
  final period = switch (c.billingPeriod) {
    BillingPeriod.weekly => 'Weekly',
    BillingPeriod.monthly => 'Monthly',
    BillingPeriod.trial2Day => '2-day trial',
  };
  return '${c.planTier.title} · $period · ₹${c.planPriceRupees}/$unit';
}
