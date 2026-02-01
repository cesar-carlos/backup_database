import 'package:backup_database/core/theme/app_colors.dart';
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
              'Erro',
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
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.refresh, size: 16),
                    SizedBox(width: 8),
                    Text('Tentar novamente'),
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
