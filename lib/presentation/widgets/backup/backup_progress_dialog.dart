import 'package:backup_database/application/providers/backup_progress_provider.dart';
import 'package:backup_database/application/services/backup_orchestrator_service.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/l10n/upload_progress_labels.dart';
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
    final locale = Localizations.localeOf(context);
    final texts = _BackupProgressTexts.fromLocale(locale);

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

        return Semantics(
          label: texts.title,
          child: ContentDialog(
            title: Row(
              children: [
                if (progress.step == BackupStep.completed)
                  const Icon(
                    FluentIcons.check_mark,
                    color: AppColors.successIcon,
                  )
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
                    Semantics(
                      liveRegion: true,
                      label: UploadProgressLabels.localizeMessage(
                        progress.message,
                        locale,
                      ),
                      child: Text(
                        UploadProgressLabels.localizeMessage(
                          progress.message,
                          locale,
                        ),
                        style: FluentTheme.of(context).typography.bodyLarge,
                      ),
                    ),
                    if (progress.progress != null &&
                        progress.step != BackupStep.completed) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        label:
                            '${texts.overallProgressLabel}: '
                            '${(progress.progress!.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%',
                        child: Text(
                          '${texts.overallProgressLabel}: '
                          '${(progress.progress!.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%',
                          style: FluentTheme.of(context).typography.caption,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Semantics(
                        label:
                            '${texts.overallProgressLabel}, '
                            '${(progress.progress!.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%',
                        child: _CustomProgressBar(
                          value: progress.progress!.clamp(0.0, 1.0),
                        ),
                      ),
                    ],
                    if (progress.elapsed != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        label:
                            '${texts.elapsedLabel}: '
                            '${_formatDuration(progress.elapsed!, texts)}',
                        child: Text(
                          '${texts.elapsedLabel}: '
                          '${_formatDuration(progress.elapsed!, texts)}',
                          style:
                              FluentTheme.of(
                                context,
                              ).typography.caption?.copyWith(
                                color: AppColors.grey600,
                              ),
                        ),
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
              // Botão de cancelar disponível enquanto o backup está em
              // execução e ainda não foi cancelado. Habilitado apenas
              // quando temos `historyId` (orchestrator publica logo após
              // criar o registro do BackupHistory).
              if (progress.step != BackupStep.completed &&
                  progress.step != BackupStep.error)
                Button(
                  onPressed:
                      (progress.cancelRequested || progress.historyId == null)
                      ? null
                      : () {
                          // Confirmação rápida via diálogo simples
                          // para evitar cancelamento acidental.
                          _confirmAndCancel(
                            context: context,
                            provider: provider,
                            historyId: progress.historyId!,
                            texts: texts,
                          );
                        },
                  child: Text(
                    progress.cancelRequested
                        ? texts.cancellingButton
                        : texts.cancelButton,
                  ),
                ),
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
          ),
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

  static Future<void> _confirmAndCancel({
    required BuildContext context,
    required BackupProgressProvider provider,
    required String historyId,
    required _BackupProgressTexts texts,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: Text(texts.cancelConfirmTitle),
        content: Text(texts.cancelConfirmBody),
        actions: [
          Button(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(texts.cancelConfirmKeep),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(texts.cancelConfirmDo),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    provider.markCancelRequested();
    try {
      // Resolução tardia do orchestrator para evitar dependência circular
      // entre o widget e a camada de DI no momento do build inicial.
      getIt<BackupOrchestratorService>().cancelByHistoryId(historyId);
    } on Object catch (e) {
      debugPrint('Falha ao solicitar cancelamento de backup: $e');
    }
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
    required this.overallProgressLabel,
    required this.closeButton,
    required this.cancelButton,
    required this.cancellingButton,
    required this.cancelConfirmTitle,
    required this.cancelConfirmBody,
    required this.cancelConfirmKeep,
    required this.cancelConfirmDo,
    required this.minuteShort,
    required this.secondShort,
  });

  final String title;
  final String elapsedLabel;
  final String overallProgressLabel;
  final String closeButton;
  final String cancelButton;
  final String cancellingButton;
  final String cancelConfirmTitle;
  final String cancelConfirmBody;
  final String cancelConfirmKeep;
  final String cancelConfirmDo;
  final String minuteShort;
  final String secondShort;

  factory _BackupProgressTexts.fromLocale(Locale locale) {
    final language = locale.languageCode.toLowerCase();

    if (language == 'pt') {
      return const _BackupProgressTexts(
        title: 'Backup em execução',
        elapsedLabel: 'Tempo decorrido',
        overallProgressLabel: 'Progresso geral',
        closeButton: 'Fechar',
        cancelButton: 'Cancelar',
        cancellingButton: 'Cancelando…',
        cancelConfirmTitle: 'Cancelar backup?',
        cancelConfirmBody:
            'O processo será encerrado imediatamente. Arquivos parciais '
            'podem ser removidos. Tem certeza?',
        cancelConfirmKeep: 'Continuar backup',
        cancelConfirmDo: 'Cancelar agora',
        minuteShort: 'm',
        secondShort: 's',
      );
    }

    return const _BackupProgressTexts(
      title: 'Backup in progress',
      elapsedLabel: 'Elapsed time',
      overallProgressLabel: 'Overall progress',
      closeButton: 'Close',
      cancelButton: 'Cancel',
      cancellingButton: 'Cancelling…',
      cancelConfirmTitle: 'Cancel backup?',
      cancelConfirmBody:
          'The process will be terminated immediately. Partial files may '
          'be removed. Are you sure?',
      cancelConfirmKeep: 'Keep running',
      cancelConfirmDo: 'Cancel now',
      minuteShort: 'm',
      secondShort: 's',
    );
  }
}
