import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/presentation/widgets/common/widget_texts.dart';
import 'package:fluent_ui/fluent_ui.dart';

enum MessageType { success, info, warning, error }

class MessageModal extends StatelessWidget {
  const MessageModal({
    required this.title,
    required this.message,
    super.key,
    this.buttonLabel,
    this.type = MessageType.success,
  });
  final String title;
  final String message;
  final String? buttonLabel;
  final MessageType type;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    String? buttonLabel,
    MessageType type = MessageType.success,
  }) {
    return showDialog<void>(
      context: context,
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
    String? title,
    String? buttonLabel,
  }) {
    final texts = WidgetTexts.fromContext(context);
    return show(
      context,
      title: title ?? texts.success,
      message: message,
      buttonLabel: buttonLabel,
    );
  }

  static Future<void> showInfo(
    BuildContext context, {
    required String message,
    String? title,
    String? buttonLabel,
  }) {
    final texts = WidgetTexts.fromContext(context);
    return show(
      context,
      title: title ?? texts.information,
      message: message,
      buttonLabel: buttonLabel,
      type: MessageType.info,
    );
  }

  static Future<void> showWarning(
    BuildContext context, {
    required String message,
    String? title,
    String? buttonLabel,
  }) {
    final texts = WidgetTexts.fromContext(context);
    return show(
      context,
      title: title ?? texts.attention,
      message: message,
      buttonLabel: buttonLabel,
      type: MessageType.warning,
    );
  }

  static Future<void> showError(
    BuildContext context, {
    required String message,
    String? title,
    String? buttonLabel,
  }) {
    final texts = WidgetTexts.fromContext(context);
    return show(
      context,
      title: title ?? texts.error,
      message: message,
      buttonLabel: buttonLabel,
      type: MessageType.error,
    );
  }

  Color _getColor() {
    switch (type) {
      case MessageType.success:
        return AppColors.success;
      case MessageType.info:
        return AppColors.primary;
      case MessageType.warning:
        return AppColors.warning;
      case MessageType.error:
        return AppColors.error;
    }
  }

  IconData _getIcon() {
    switch (type) {
      case MessageType.success:
        return FluentIcons.check_mark;
      case MessageType.info:
        return FluentIcons.info;
      case MessageType.warning:
        return FluentIcons.warning;
      case MessageType.error:
        return FluentIcons.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final texts = WidgetTexts.fromContext(context);
    final color = _getColor();
    final icon = _getIcon();

    return ContentDialog(
      title: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: FluentTheme.of(context).typography.title?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Text(message, style: FluentTheme.of(context).typography.body),
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(buttonLabel ?? texts.ok),
        ),
      ],
    );
  }
}
