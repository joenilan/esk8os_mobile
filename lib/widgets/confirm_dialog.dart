import 'package:flutter/material.dart';

import 'esk8_theme.dart';

/// Confirmation dialog for destructive or disruptive actions (deleting a trip,
/// resetting the board trip, bridge mode, reboot). Returns `true` only if the
/// user confirms. Sharp corners + CAM palette to match the dashboard; the
/// confirm action is red when [destructive], accent otherwise.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Esk8Theme.scaffold,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: Esk8Theme.border),
        borderRadius: BorderRadius.zero, // the board never rounds
      ),
      title: Text(title,
          style: const TextStyle(
              color: Esk8Theme.textPrimary, fontWeight: FontWeight.bold)),
      content: Text(message, style: const TextStyle(color: Esk8Theme.label)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel, style: const TextStyle(color: Esk8Theme.dim)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel,
              style: TextStyle(
                  color: destructive ? Esk8Theme.danger : Esk8Theme.accent,
                  fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
  return result ?? false;
}
