import 'dart:async';

import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/widgets/atoms/widget_texts.dart';
import 'package:backup_database/presentation/widgets/molecules/action_button.dart';
import 'package:backup_database/presentation/widgets/molecules/cancel_button.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar, Text;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

enum MessageType { success, info, warning, error }

/// **Organism** — modal message surface with semantic accents and design
/// tokens.
class MessageModal extends StatelessWidget {
  const MessageModal({
    required this.title,
    required this.message,
    super.key,
    this.buttonLabel,
    this.type = MessageType.success,
    this.onCopy,
  });

  final String title;
  final String message;
  final String? buttonLabel;
  final MessageType type;
  final VoidCallback? onCopy;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    String? buttonLabel,
    MessageType type = MessageType.success,
    VoidCallback? onCopy,
  }) {
    return showDialog<void>(
      context: context,
      transitionDuration: AppDuration.normal,
      builder: (BuildContext context) => MessageModal(
        title: title,
        message: message,
        buttonLabel: buttonLabel,
        type: type,
        onCopy: onCopy,
      ),
    );
  }

  static Future<void> showSuccess(
    BuildContext context, {
    required String message,
    String? title,
    String? buttonLabel,
    VoidCallback? onCopy,
  }) {
    final texts = WidgetTexts.fromContext(context);
    return show(
      context,
      title: title ?? texts.success,
      message: message,
      buttonLabel: buttonLabel,
      onCopy: onCopy,
    );
  }

  static Future<void> showInfo(
    BuildContext context, {
    required String message,
    String? title,
    String? buttonLabel,
    VoidCallback? onCopy,
  }) {
    final texts = WidgetTexts.fromContext(context);
    return show(
      context,
      title: title ?? texts.information,
      message: message,
      buttonLabel: buttonLabel,
      type: MessageType.info,
      onCopy: onCopy,
    );
  }

  static Future<void> showWarning(
    BuildContext context, {
    required String message,
    String? title,
    String? buttonLabel,
    VoidCallback? onCopy,
  }) {
    final texts = WidgetTexts.fromContext(context);
    return show(
      context,
      title: title ?? texts.attention,
      message: message,
      buttonLabel: buttonLabel,
      type: MessageType.warning,
      onCopy: onCopy,
    );
  }

  static Future<void> showError(
    BuildContext context, {
    required String message,
    String? title,
    String? buttonLabel,
    VoidCallback? onCopy,
  }) {
    final texts = WidgetTexts.fromContext(context);
    return show(
      context,
      title: title ?? texts.error,
      message: message,
      buttonLabel: buttonLabel,
      type: MessageType.error,
      onCopy: onCopy,
    );
  }

  static Future<bool> showConfirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    IconData? confirmIcon,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      transitionDuration: AppDuration.normal,
      builder: (BuildContext dialogContext) {
        return ContentDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            CancelButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            ActionButton(
              label: confirmLabel,
              icon: confirmIcon,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  static Future<String?> showInputConfirm(
    BuildContext context, {
    required String title,
    required String message,
    required String fieldLabel,
    required String initialValue,
    required String confirmLabel,
    IconData? confirmIcon,
  }) {
    return showDialog<String?>(
      context: context,
      transitionDuration: AppDuration.normal,
      builder: (BuildContext dialogContext) {
        return _MessageModalInputConfirm(
          title: title,
          message: message,
          fieldLabel: fieldLabel,
          initialValue: initialValue,
          confirmLabel: confirmLabel,
          confirmIcon: confirmIcon,
        );
      },
    );
  }

  Color _colorFor(AppSemanticColors colors) {
    switch (type) {
      case MessageType.success:
        return colors.success;
      case MessageType.info:
        return colors.info;
      case MessageType.warning:
        return colors.warning;
      case MessageType.error:
        return colors.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    final texts = WidgetTexts.fromContext(context);
    final colors = context.colors;
    final color = _colorFor(colors);
    final icon = _getIcon();
    final showErrorType = type == MessageType.error;

    final copyButton = (onCopy != null || showErrorType)
        ? Button(
            onPressed: () {
              unawaited(Clipboard.setData(ClipboardData(text: message)));
              onCopy?.call();
              final messenger = ScaffoldMessenger.maybeOf(context);
              if (context.mounted && messenger != null) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Texto copiado'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(
                vertical: AppSpacing.md,
                horizontal: AppSpacing.sm,
              ),
              child: Text('Copiar'),
            ),
          )
        : null;

    return Semantics(
      namesRoute: true,
      label: title,
      child: ContentDialog(
        title: Row(
          children: [
            ExcludeSemantics(
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: AppSpacing.sm, height: AppSpacing.sm),
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
        content: Padding(
          padding: AppSpacing.paddingLg,
          child: SizedBox(
            width: 600,
            child: SelectableText(
              message,
              style: FluentTheme.of(context).typography.body,
            ),
          ),
        ),
        actions: [
          ...copyButton != null ? [copyButton] : const <Widget>[],
          Button(
            onPressed: () => Navigator.of(context).pop(),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.md,
                horizontal: AppSpacing.sm,
              ),
              child: Text(buttonLabel ?? texts.ok),
            ),
          ),
        ],
      ),
    );
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
}

class _MessageModalInputConfirm extends StatefulWidget {
  const _MessageModalInputConfirm({
    required this.title,
    required this.message,
    required this.fieldLabel,
    required this.initialValue,
    required this.confirmLabel,
    this.confirmIcon,
  });

  final String title;
  final String message;
  final String fieldLabel;
  final String initialValue;
  final String confirmLabel;
  final IconData? confirmIcon;

  @override
  State<_MessageModalInputConfirm> createState() =>
      _MessageModalInputConfirmState();
}

class _MessageModalInputConfirmState extends State<_MessageModalInputConfirm> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = _controller.text.trim().isNotEmpty;
    return ContentDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.message),
            const SizedBox(height: AppSpacing.md),
            InfoLabel(
              label: widget.fieldLabel,
              child: TextBox(
                controller: _controller,
                autofocus: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        CancelButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
        ActionButton(
          label: widget.confirmLabel,
          icon: widget.confirmIcon,
          onPressed: canConfirm
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
        ),
      ],
    );
  }
}
