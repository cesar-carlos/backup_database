import 'package:backup_database/presentation/widgets/organisms/app_dialog_shell.dart';
import 'package:fluent_ui/fluent_ui.dart';

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
    return AppDialogShell(
      constraints: constraints,
      title: title,
      content: body,
      actions: dialogActions,
      onSubmitIntent: onSubmitIntent,
      onDismiss: onDismiss,
    );
  }
}
