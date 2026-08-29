import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:fluent_ui/fluent_ui.dart';

enum _AppButtonVariant { standard, primary }

const double _progressSize = 20;
const double _progressStrokeWidth = 2;

/// **Atom** — Fluent button composed from slots (`leading` / `trailing`) and
/// named factories for common shapes.
class AppButton extends StatelessWidget {
  const AppButton._({
    required this.label,
    required this._variant,
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
        variant: _AppButtonVariant.standard,
        label: '',
        isLoadingLayout: true,
      );
    }
    final resolvedLeading = leading ?? (icon != null ? Icon(icon) : null);
    return AppButton._(
      key: key,
      variant: _AppButtonVariant.standard,
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
    bool isLoading = false,
    String? loadingLabel,
  }) {
    return AppButton._(
      key: key,
      variant: _AppButtonVariant.primary,
      label: isLoading ? (loadingLabel ?? label) : label,
      onPressed: isLoading ? null : onPressed,
      leading: isLoading ? null : leading,
      trailing: isLoading ? null : trailing,
      isLoadingLayout: isLoading,
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
      variant: _AppButtonVariant.standard,
      label: label,
      onPressed: onPressed,
      leading: Icon(icon),
      trailing: trailing,
    );
  }

  factory AppButton.loading({Key? key}) {
    return AppButton._(
      key: key,
      variant: _AppButtonVariant.standard,
      label: '',
      isLoadingLayout: true,
    );
  }

  final _AppButtonVariant _variant;
  final String label;
  final VoidCallback? onPressed;
  final Widget? leading;
  final Widget? trailing;
  final bool isLoadingLayout;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (isLoadingLayout) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: _progressSize,
            height: _progressSize,
            child: ProgressRing(strokeWidth: _progressStrokeWidth),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      );
    } else {
      final leadingForRow = switch (leading) {
        null => null,
        final Widget w when label.isNotEmpty => ExcludeSemantics(child: w),
        final Widget w => w,
      };

      child = (leading != null || trailing != null)
          ? FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ?leadingForRow,
                  if (leading != null)
                    const SizedBox(
                      width: AppSpacing.sm,
                      height: AppSpacing.sm,
                    ),
                  if (label.isNotEmpty) Text(label),
                  if (trailing != null) ...[
                    const SizedBox(
                      width: AppSpacing.sm,
                      height: AppSpacing.sm,
                    ),
                    trailing!,
                  ],
                ],
              ),
            )
          : Text(label);
    }

    final Widget button = switch (_variant) {
      _AppButtonVariant.primary => FilledButton(
        onPressed: onPressed,
        child: child,
      ),
      _AppButtonVariant.standard => Button(
        onPressed: onPressed,
        child: child,
      ),
    };

    final String semanticsLabel;
    if (isLoadingLayout && label.isEmpty) {
      semanticsLabel = 'Loading';
    } else if (label.isEmpty) {
      semanticsLabel = 'Button';
    } else {
      semanticsLabel = label;
    }

    return Semantics(
      button: true,
      label: semanticsLabel,
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
