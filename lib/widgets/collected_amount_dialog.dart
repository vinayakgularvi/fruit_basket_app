import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_navigator.dart';

/// Confirms how many rupees were collected (defaults to [suggestedRupees]).
/// Returns null if cancelled.
Future<int?> showCollectedAmountDialog(
  BuildContext context, {
  required int suggestedRupees,
  String title = 'Amount collected',
}) {
  final controller = TextEditingController(text: '$suggestedRupees');
  final root = rootNavigatorContext;
  final dialogContext =
      root != null && root.mounted ? root : context;
  return showDialog<int>(
    context: dialogContext,
    useRootNavigator: true,
    builder: (ctx) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Rupees (₹)',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            final v = int.tryParse(controller.text.trim());
            if (v != null && v >= 0) Navigator.pop(ctx, v);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v == null || v < 0) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('Confirm'),
          ),
        ],
      );
    },
  ).whenComplete(controller.dispose);
}
