import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Atom** — Fluent button composed from slots (`leading` / `trailing`) and
/// named factories for common shapes.
class AppButton extends StatelessWidget {
  const AppButton._({
    required this.label,
    super.key,
    this.onPressed,
    this.leading,
    this.trailing,
    this.isLoadingLayout = false,
  });

  factory AppButton({
    required String label,
    Key? key,
    VoidCallback? onPressed,
    IconData? icon,
    Widget? leading,
    Widget? trailing,
    bool isLoading = false,
  }) {
    if (isLoading) {
      return AppButton._(
        key: key,
        label: '',
        isLoadingLayout: true,
      );
    }
    final resolvedLeading = leading ?? (icon != null ? Icon(icon) : null);
    return AppButton._(
      key: key,
      label: label,
      onPressed: onPressed,
      leading: resolvedLeading,
      trailing: trailing,
    );
  }

  factory AppButton.primary({
    required String label,
    Key? key,
    VoidCallback? onPressed,
    Widget? leading,
    Widget? trailing,
  }) {
    return AppButton._(
      key: key,
      label: label,
      onPressed: onPressed,
      leading: leading,
      trailing: trailing,
    );
  }

  factory AppButton.icon({
    required IconData icon,
    required String label,
    Key? key,
    VoidCallback? onPressed,
    Widget? trailing,
  }) {
    return AppButton._(
      key: key,
      label: label,
      onPressed: onPressed,
      leading: Icon(icon),
      trailing: trailing,
    );
  }

  factory AppButton.loading({Key? key}) {
    return AppButton._(
      key: key,
      label: '',
      isLoadingLayout: true,
    );
  }

  final String label;
  final VoidCallback? onPressed;
  final Widget? leading;
  final Widget? trailing;
  final bool isLoadingLayout;

  @override
  Widget build(BuildContext context) {
    if (isLoadingLayout) {
      return Semantics(
        label: 'Loading',
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppTargetSize.comfortable,
          ),
          child: const Button(
            onPressed: null,
            child: SizedBox(
              width: 20,
              height: 20,
              child: ProgressRing(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    final leadingForRow = switch (leading) {
      null => null,
      final Widget w when label.isNotEmpty => ExcludeSemantics(child: w),
      final Widget w => w,
    };

    final child = (leading != null || trailing != null)
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?leadingForRow,
              if (leading != null)
                const SizedBox(width: AppSpacing.sm, height: AppSpacing.sm),
              if (label.isNotEmpty) Text(label),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm, height: AppSpacing.sm),
                trailing!,
              ],
            ],
          )
        : Text(label);

    final button = Button(
      onPressed: onPressed,
      child: child,
    );

    return Semantics(
      button: true,
      label: label.isEmpty ? 'Button' : label,
      enabled: onPressed != null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppTargetSize.comfortable,
        ),
        child: button,
      ),
    );
  }
}
