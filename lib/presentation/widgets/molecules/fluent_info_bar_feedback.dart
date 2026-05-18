import 'package:backup_database/presentation/widgets/atoms/widget_texts.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — transient Fluent InfoBar helpers for success/error feedback.
final class FluentInfoBarFeedback {
  FluentInfoBarFeedback._();

  static const Duration _infoBarDuration = Duration(seconds: 4);

  static Future<void> showSuccess(
    BuildContext context, {
    required String message,
    String? title,
  }) {
    if (!context.mounted) {
      return Future<void>.value();
    }
    final texts = WidgetTexts.fromContext(context);
    return _display(
      context,
      titleText: title ?? texts.success,
      message: message,
      severity: InfoBarSeverity.success,
    );
  }

  static Future<void> showInfo(
    BuildContext context, {
    required String message,
    String? title,
  }) {
    if (!context.mounted) {
      return Future<void>.value();
    }
    final texts = WidgetTexts.fromContext(context);
    return _display(
      context,
      titleText: title ?? texts.information,
      message: message,
      severity: InfoBarSeverity.info,
    );
  }

  static Future<void> showWarning(
    BuildContext context, {
    required String message,
    String? title,
  }) {
    if (!context.mounted) {
      return Future<void>.value();
    }
    final texts = WidgetTexts.fromContext(context);
    return _display(
      context,
      titleText: title ?? texts.attention,
      message: message,
      severity: InfoBarSeverity.warning,
    );
  }

  static Future<void> _display(
    BuildContext context, {
    required String titleText,
    required String message,
    required InfoBarSeverity severity,
  }) async {
    if (!context.mounted) {
      return;
    }
    await displayInfoBar(
      context,
      duration: _infoBarDuration,
      builder: (BuildContext _, VoidCallback close) {
        return InfoBar(
          title: Text(titleText),
          content: Text(message),
          severity: severity,
          onClose: close,
          isLong: message.length > 120,
        );
      },
    );
  }
}
