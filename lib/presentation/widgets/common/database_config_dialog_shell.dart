import 'dart:async';

import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

/// **Organism** — shared [ContentDialog] layout for database configuration
/// dialogs (title, scrollable body, actions, keyboard shortcuts).
class DatabaseConfigDialogShell extends StatelessWidget {
  const DatabaseConfigDialogShell({
    required this.constraints,
    required this.title,
    required this.body,
    required this.dialogActions,
    super.key,
    this.onSubmitIntent,
    this.onDismiss,
  });

  final BoxConstraints constraints;
  final Widget title;
  final Widget body;
  final List<Widget> dialogActions;
  final VoidCallback? onSubmitIntent;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (onDismiss != null) {
          onDismiss!();
        } else {
          unawaited(Navigator.of(context).maybePop());
        }
      },
    };
    if (onSubmitIntent != null) {
      bindings[const SingleActivator(LogicalKeyboardKey.enter, control: true)] =
          onSubmitIntent!;
    }

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        autofocus: true,
        child: ContentDialog(
          constraints: constraints,
          title: title,
          content: SingleChildScrollView(
            padding: AppSpacing.paddingLg,
            child: body,
          ),
          actions: dialogActions,
        ),
      ),
    );
  }
}
