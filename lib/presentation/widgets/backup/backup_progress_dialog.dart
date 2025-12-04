import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../application/providers/backup_progress_provider.dart';

class BackupProgressDialog extends StatelessWidget {
  const BackupProgressDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const BackupProgressDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BackupProgressProvider>(
      builder: (context, provider, child) {
        final progress = provider.currentProgress;

        if (progress == null) {
          return const SizedBox.shrink();
        }

        return ContentDialog(
          title: Row(
            children: [
              if (progress.step == BackupStep.completed)
                const Icon(FluentIcons.check_mark, color: AppColors.successIcon)
              else if (progress.step == BackupStep.error)
                const Icon(FluentIcons.error, color: AppColors.errorIcon)
              else
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: ProgressRing(strokeWidth: 2),
                ),
              const SizedBox(width: 12),
              const Text('Backup em Execução'),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    progress.message,
                    style: FluentTheme.of(context).typography.bodyLarge,
                  ),
                  if (progress.progress != null &&
                      progress.step != BackupStep.completed) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: FluentTheme.of(
                          context,
                        ).resources.cardBackgroundFillColorDefault,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: ProgressBar(value: progress.progress),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(progress.progress! * 100).toStringAsFixed(0)}%',
                      style: FluentTheme.of(context).typography.caption,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (progress.elapsed != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Tempo decorrido: ${_formatDuration(progress.elapsed!)}',
                      style: FluentTheme.of(
                        context,
                      ).typography.caption?.copyWith(color: AppColors.grey600),
                    ),
                  ],
                  if (progress.error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.errorBackground,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.errorBorder),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            FluentIcons.error,
                            color: AppColors.errorIcon,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              progress.error!,
                              style: const TextStyle(
                                color: AppColors.errorText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            if (progress.step == BackupStep.completed ||
                progress.step == BackupStep.error)
              Button(
                onPressed: () {
                  provider.reset();
                  Navigator.of(context).pop();
                },
                child: const Text('Fechar'),
              ),
          ],
        );
      },
    );
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }
}
