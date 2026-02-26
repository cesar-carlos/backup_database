import 'package:backup_database/application/providers/backup_progress_provider.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

class BackupProgressDialog extends StatelessWidget {
  const BackupProgressDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => const BackupProgressDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final texts = _BackupProgressTexts.fromLocale(
      Localizations.localeOf(context),
    );

    return Consumer<BackupProgressProvider>(
      builder: (context, provider, child) {
        final progress = provider.currentProgress;

        if (progress == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            Navigator.of(context).maybePop();
          });
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
              Text(texts.title),
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
                    _CustomProgressBar(
                      value: progress.progress!.clamp(0.0, 1.0),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(progress.progress!.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%',
                      style: FluentTheme.of(context).typography.caption,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (progress.elapsed != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      '${texts.elapsedLabel}: ${_formatDuration(progress.elapsed!, texts)}',
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
                child: Text(texts.closeButton),
              ),
          ],
        );
      },
    );
  }

  static String _formatDuration(
    Duration duration,
    _BackupProgressTexts texts,
  ) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    if (minutes > 0) {
      return '$minutes${texts.minuteShort} $seconds${texts.secondShort}';
    }
    return '$seconds${texts.secondShort}';
  }
}

class _CustomProgressBar extends StatelessWidget {
  const _CustomProgressBar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(0.0, 1.0);
    final theme = FluentTheme.of(context);

    return Container(
      width: double.infinity,
      height: 8,
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              height: double.infinity,
              color: theme.resources.cardBackgroundFillColorDefault,
            ),
            FractionallySizedBox(
              widthFactor: clampedValue,
              alignment: Alignment.centerLeft,
              child: Container(
                height: double.infinity,
                decoration: BoxDecoration(
                  color: theme.accentColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupProgressTexts {
  const _BackupProgressTexts({
    required this.title,
    required this.elapsedLabel,
    required this.closeButton,
    required this.minuteShort,
    required this.secondShort,
  });

  final String title;
  final String elapsedLabel;
  final String closeButton;
  final String minuteShort;
  final String secondShort;

  factory _BackupProgressTexts.fromLocale(Locale locale) {
    final language = locale.languageCode.toLowerCase();

    if (language == 'pt') {
      return const _BackupProgressTexts(
        title: 'Backup em execução',
        elapsedLabel: 'Tempo decorrido',
        closeButton: 'Fechar',
        minuteShort: 'm',
        secondShort: 's',
      );
    }

    return const _BackupProgressTexts(
      title: 'Backup in progress',
      elapsedLabel: 'Elapsed time',
      closeButton: 'Close',
      minuteShort: 'm',
      secondShort: 's',
    );
  }
}
