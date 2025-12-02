import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class ErrorModal extends StatelessWidget {
  final String title;
  final String message;
  final String? buttonLabel;

  const ErrorModal({
    super.key,
    this.title = 'Erro',
    required this.message,
    this.buttonLabel,
  });

  static Future<void> show(
    BuildContext context, {
    String title = 'Erro',
    required String message,
    String? buttonLabel,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          ErrorModal(title: title, message: message, buttonLabel: buttonLabel),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: Theme.of(context).colorScheme.error,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: AppColors.buttonTextOnColored,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Text(buttonLabel ?? 'OK'),
        ),
      ],
    );
  }
}
