import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/providers/app_density_provider.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

/// **Organism** - shared shell for complex dialogs with shortcuts, scrollable
/// body and aligned actions.
class AppDialogShell extends StatelessWidget {
  const AppDialogShell({
    required this.title,
    required this.content,
    required this.actions,
    super.key,
    this.constraints,
    this.padding,
    this.scrollable = true,
    this.onSubmitIntent,
    this.onDismiss,
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;
  final bool scrollable;
  final VoidCallback? onSubmitIntent;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (onDismiss != null) {
          onDismiss!();
        } else {
          Navigator.of(context).maybePop();
        }
      },
    };
    if (onSubmitIntent != null) {
      bindings[const SingleActivator(LogicalKeyboardKey.enter, control: true)] =
          onSubmitIntent!;
    }
    final resolvedPadding =
        padding ?? InheritedAppDensity.resolve(context).contentPadding;

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        autofocus: true,
        child: ContentDialog(
          constraints: constraints ?? AppDialogConstraints.of(context),
          title: title,
          content: scrollable
              ? SingleChildScrollView(
                  padding: resolvedPadding,
                  child: content,
                )
              : Padding(
                  padding: resolvedPadding,
                  child: content,
                ),
          actions: actions,
        ),
      ),
    );
  }
}
