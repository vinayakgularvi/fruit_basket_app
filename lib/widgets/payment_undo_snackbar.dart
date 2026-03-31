import 'dart:async';

import 'package:flutter/material.dart';

import '../app_navigator.dart';
import '../data/app_repository.dart';
import '../models/customer.dart';

void showPaymentRecordedWithUndo(
  BuildContext context,
  AppRepository repo,
  Customer snapshotBefore,
) {
  final root = rootNavigatorContext;
  final snackContext =
      root != null && root.mounted ? root : context;
  if (!snackContext.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(snackContext);
  if (messenger == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Payment recorded'),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            unawaited(repo.updateCustomer(snapshotBefore));
          },
        ),
      ),
    );
  });
}
