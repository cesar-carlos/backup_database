import 'package:flutter/material.dart';

enum MessageType { success, info, warning }

class MessageModal extends StatelessWidget {
  final String title;
  final String message;
  final String? buttonLabel;
  final MessageType type;

  const MessageModal({
    super.key,
    required this.title,
    required this.message,
    this.buttonLabel,
    this.type = MessageType.success,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    String? buttonLabel,
    MessageType type = MessageType.success,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => MessageModal(
        title: title,
        message: message,
        buttonLabel: buttonLabel,
        type: type,
      ),
    );
  }

  static Future<void> showSuccess(
    BuildContext context, {
    required String message,
    String title = 'Sucesso',
    String? buttonLabel,
  }) {
    return show(
      context,
      title: title,
      message: message,
      buttonLabel: buttonLabel,
      type: MessageType.success,
    );
  }

  static Future<void> showInfo(
    BuildContext context, {
    required String message,
    String title = 'Informação',
    String? buttonLabel,
  }) {
    return show(
      context,
      title: title,
      message: message,
      buttonLabel: buttonLabel,
      type: MessageType.info,
    );
  }

  static Future<void> showWarning(
    BuildContext context, {
    required String message,
    String title = 'Atenção',
    String? buttonLabel,
  }) {
    return show(
      context,
      title: title,
      message: message,
      buttonLabel: buttonLabel,
      type: MessageType.warning,
    );
  }

  Color _getColor(BuildContext context) {
    switch (type) {
      case MessageType.success:
        return Colors.green;
      case MessageType.info:
        return Theme.of(context).colorScheme.primary;
      case MessageType.warning:
        return Colors.orange;
    }
  }

  IconData _getIcon() {
    switch (type) {
      case MessageType.success:
        return Icons.check_circle_outline;
      case MessageType.info:
        return Icons.info_outline;
      case MessageType.warning:
        return Icons.warning_amber_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor(context);
    final icon = _getIcon();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: color,
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
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Text(buttonLabel ?? 'OK'),
        ),
      ],
    );
  }
}
