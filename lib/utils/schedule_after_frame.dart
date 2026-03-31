import 'dart:async';

import 'package:flutter/scheduler.dart';

/// Runs [callback] after the current frame completes.
/// Use after async work that triggers a provider rebuild, before opening dialogs or overlays.
Future<T?> scheduleAfterFrame<T>(Future<T?> Function() callback) {
  final completer = Completer<T?>();
  SchedulerBinding.instance.addPostFrameCallback((_) async {
    try {
      completer.complete(await callback());
    } catch (e, st) {
      if (!completer.isCompleted) {
        completer.completeError(e, st);
      }
    }
  });
  return completer.future;
}
