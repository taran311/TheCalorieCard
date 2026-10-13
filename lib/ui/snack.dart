import 'dart:async';

import 'package:flutter/material.dart';

/// Snackbars with a button (Undo, View…) can stay on screen until tapped
/// in newer Flutter. This shows one that always goes after its duration.
extension TimedSnackBar on ScaffoldMessengerState {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showTimedSnackBar(
      SnackBar bar) {
    final controller = showSnackBar(bar);
    var closed = false;
    controller.closed.then((_) => closed = true);
    Timer(bar.duration + const Duration(milliseconds: 250), () {
      if (!closed) controller.close();
    });
    return controller;
  }
}
