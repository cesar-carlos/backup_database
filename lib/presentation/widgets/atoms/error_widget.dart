import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:backup_database/presentation/widgets/atoms/widget_texts.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Atom** — centered error surface with optional retry action.
class AppErrorWidget extends StatelessWidget {
  const AppErrorWidget({
    required this.message,
    super.key,
    this.onRetry,
  });
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final texts = WidgetTexts.fromContext(context);
    final colors = context.colors;

    return Center(
      child: Padding(
        padding: AppSpacing.paddingLg,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.error_badge,
              size: 64,
              color: colors.danger,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              texts.error,
              style: FluentTheme.of(context).typography.title,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: FluentTheme.of(context).typography.body,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: onRetry,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(FluentIcons.refresh, size: 16),
                    const SizedBox(width: AppSpacing.sm),
                    Text(texts.retry),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
