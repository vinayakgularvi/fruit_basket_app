import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/customer.dart';

void showPaymentRecordedWithUndo(
  BuildContext context,
  AppRepository repo,
  Customer snapshotBefore,
) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('Payment recorded'),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          unawaited(repo.updateCustomer(snapshotBefore));
        },
      ),
    ),
  );
}
