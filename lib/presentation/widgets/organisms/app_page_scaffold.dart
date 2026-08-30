import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/widgets/atoms/app_button.dart';
import 'package:backup_database/presentation/widgets/atoms/app_icon_button.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double _headerContentGap = 6;

class AppPageAction {
  const AppPageAction({
    required this.label,
    this.icon,
    this.onPressed,
    this.isPrimary = false,
    this.iconOnly = false,
    this.key,
  });

  final Key? key;
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool iconOnly;
}

/// **Organism** - standard management-page scaffold with aligned actions and
/// consistent content padding.
class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    required this.title,
    required this.body,
    super.key,
    this.actions = const <AppPageAction>[],
    this.commandBar,
    this.bodyPadding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      _headerContentGap,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
    this.headerBottom,
  });

  final String title;
  final Widget body;
  final List<AppPageAction> actions;
  final Widget? commandBar;
  final EdgeInsetsGeometry bodyPadding;
  final Widget? headerBottom;

  @override
  Widget build(BuildContext context) {
    final resolvedCommandBar =
        commandBar ??
        (actions.isEmpty ? null : _AppPageActionBar(actions: actions));

    return ScaffoldPage(
      header: PageHeader(
        title: Text(title),
        commandBar: resolvedCommandBar,
      ),
      content: Padding(
        padding: bodyPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (headerBottom != null) ...[
              headerBottom!,
              const SizedBox(height: AppSpacing.md),
            ],
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _AppPageActionBar extends StatelessWidget {
  const _AppPageActionBar({
    required this.actions,
  });

  final List<AppPageAction> actions;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              _AppPageActionButton(action: actions[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _AppPageActionButton extends StatelessWidget {
  const _AppPageActionButton({required this.action});

  final AppPageAction action;

  @override
  Widget build(BuildContext context) {
    if (action.iconOnly) {
      return AppIconButton(
        key: action.key,
        label: action.label,
        icon: action.icon ?? FluentIcons.refresh,
        onPressed: action.onPressed,
      );
    }

    if (action.isPrimary) {
      return AppButton.primary(
        key: action.key,
        label: action.label,
        onPressed: action.onPressed,
        leading: action.icon == null ? null : Icon(action.icon),
      );
    }

    if (action.icon != null) {
      return AppButton.icon(
        key: action.key,
        icon: action.icon!,
        label: action.label,
        onPressed: action.onPressed,
      );
    }

    return AppButton(
      key: action.key,
      label: action.label,
      onPressed: action.onPressed,
    );
  }
}
