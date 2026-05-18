import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Atom** — centered empty placeholder with optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.message,
    required this.icon,
    super.key,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: message,
      child: Center(
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ExcludeSemantics(
                child: Icon(
                  icon,
                  size: 64,
                  color: AppPalette.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.md, width: AppSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: FluentTheme.of(context).typography.subtitle,
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.lg, width: AppSpacing.lg),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppTargetSize.minimum,
                  ),
                  child: Button(
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
