import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

Future<bool> showDeleteConfirmationDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = 'Delete',
  String cancelText = 'Close',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelText),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}

