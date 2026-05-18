import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/presentation/widgets/common/widget_texts.dart';
import 'package:fluent_ui/fluent_ui.dart';

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

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              FluentIcons.error_badge,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              texts.error,
              style: FluentTheme.of(context).typography.title,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: FluentTheme.of(context).typography.body,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onRetry,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(FluentIcons.refresh, size: 16),
                    const SizedBox(width: 8),
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
