import 'package:flutter/material.dart';

/// Shows a confirmation dialog when the user tries to leave with unsaved changes.
/// Returns [true] if user chose "Discard" (caller should pop), [false] if "Continue editing".
Future<bool> showUnsavedChangesDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Unsaved changes'),
      content: const Text(
        'Your changes will not be saved. Do you want to discard them?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Continue editing'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  return result ?? false;
}
