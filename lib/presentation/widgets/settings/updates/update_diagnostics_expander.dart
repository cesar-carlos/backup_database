import 'package:backup_database/application/providers/auto_update_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/widgets/settings/settings_ui.dart';
import 'package:backup_database/presentation/widgets/settings/updates/update_settings_labels.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Organism** — collapsed technical diagnostics for the updater.
class UpdateDiagnosticsExpander extends StatelessWidget {
  const UpdateDiagnosticsExpander({
    required this.provider,
    required this.onCopyFeed,
    required this.onOpenFeed,
    required this.onCopyContextPath,
    required this.onOpenContextFolder,
    required this.onCopyDiagnosticsPath,
    required this.onOpenDiagnosticsFolder,
    required this.onCopyLockPath,
    required this.onOpenLockFolder,
    super.key,
  });

  final AutoUpdateProvider provider;
  final VoidCallback onCopyFeed;
  final VoidCallback onOpenFeed;
  final VoidCallback onCopyContextPath;
  final VoidCallback onOpenContextFolder;
  final VoidCallback onCopyDiagnosticsPath;
  final VoidCallback onOpenDiagnosticsFolder;
  final VoidCallback onCopyLockPath;
  final VoidCallback onOpenLockFolder;

  @override
  Widget build(BuildContext context) {
    return Expander(
      header: Text(
        appLocaleString(
          context,
          'Updater technical details',
          'Updater technical details',
        ),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (provider.feedUrl != null)
            SettingsTechnicalItem(
              title: appLocaleString(
                context,
                'Feed configurado',
                'Configured feed',
              ),
              value: provider.feedUrl!,
              description: appLocaleString(
                context,
                'Origem consultada para novas versoes.',
                'Source consulted for new versions.',
              ),
              onCopy: onCopyFeed,
              onOpen: onOpenFeed,
              openTooltip: appLocaleString(
                context,
                'Abrir feed',
                'Open feed',
              ),
            ),
          if (provider.feedUrl != null) const SizedBox(height: AppSpacing.lg),
          SettingsTechnicalItem(
            title: appLocaleString(context, 'Ultimo ciclo', 'Last cycle'),
            value: provider.lastAttemptNumber != null
                ? '#${provider.lastAttemptNumber} • '
                      '${autoUpdateSourceText(context, provider.lastSource)} • '
                      '${autoUpdateStageText(context, provider.currentStage)}'
                : appLocaleString(
                    context,
                    'Nenhuma execucao registrada.',
                    'No execution recorded.',
                  ),
            description: appLocaleString(
              context,
              'Resumo do ultimo fluxo observado pelo provider.',
              'Summary of the latest flow observed by the provider.',
            ),
          ),
          // P3#15: estado do dotenv (sempre visível). Ajuda
          // diagnosticar misconfig em segundos vs. a sessão de
          // detective que motivou a auditoria.
          if (provider.disabledReason != null) ...[
            const SizedBox(height: AppSpacing.lg),
            SettingsTechnicalItem(
              title: appLocaleString(
                context,
                'Motivo do disable',
                'Disabled reason',
              ),
              value: autoUpdateDisabledReasonLabel(provider.disabledReason!),
              description: appLocaleString(
                context,
                'Causa raiz do estado "indisponivel". Use para '
                    'mapear contra logs.',
                'Root cause of the "unavailable" state. Map against '
                    'logs.',
              ),
            ),
          ],
          // §audit-2026-05-28 wave 4 (UI banner): label técnico do
          // último motivo de bloqueio — útil para correlacionar
          // com logs `[auto-update] silencioso bloqueado: ...`.
          if (provider.blockReason != null) ...[
            const SizedBox(height: AppSpacing.lg),
            SettingsTechnicalItem(
              title: appLocaleString(
                context,
                'Motivo do bloqueio',
                'Block reason',
              ),
              value: autoUpdateBlockReasonLabel(provider.blockReason!),
              description: appLocaleString(
                context,
                'Causa do ultimo ciclo bloqueado. Use para mapear '
                    'contra logs e decidir se o ciclo proximo vai '
                    'destravar sozinho.',
                'Cause of the last blocked cycle. Use to map against '
                    'logs and decide whether the next cycle will '
                    'unblock on its own.',
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SettingsTechnicalItem(
            title: appLocaleString(
              context,
              'Telemetria do updater',
              'Updater telemetry',
            ),
            value:
                'Ciclo: ${autoUpdateDurationLabel(context, provider.lastCheckDuration)}\n'
                'Download: ${autoUpdateDurationLabel(context, provider.lastDownloadDuration)}\n'
                'Ultima falha: ${autoUpdateStageText(context, provider.lastFailureStage)}',
            description: appLocaleString(
              context,
              'Duracoes e ultima etapa de falha conhecida.',
              'Durations and latest known failure stage.',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SettingsTechnicalItem(
            title: appLocaleString(
              context,
              'Contexto do updater',
              'Updater context',
            ),
            value: provider.updateContextPath,
            description: appLocaleString(
              context,
              'Arquivo de suporte com contexto operacional do updater.',
              'Support file with updater operational context.',
            ),
            onCopy: onCopyContextPath,
            onOpen: onOpenContextFolder,
            openTooltip: appLocaleString(
              context,
              'Abrir pasta',
              'Open folder',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SettingsTechnicalItem(
            title: appLocaleString(
              context,
              'Historico operacional',
              'Operational history',
            ),
            value: provider.diagnosticsPath,
            description: appLocaleString(
              context,
              'Historico persistido de tentativas e diagnosticos.',
              'Persisted history of attempts and diagnostics.',
            ),
            onCopy: onCopyDiagnosticsPath,
            onOpen: onOpenDiagnosticsFolder,
            openTooltip: appLocaleString(
              context,
              'Abrir pasta',
              'Open folder',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SettingsTechnicalItem(
            title: appLocaleString(
              context,
              'Lock global do updater',
              'Updater global lock',
            ),
            value: provider.lockFilePath,
            description: appLocaleString(
              context,
              'Arquivo de coordenacao entre instancias.',
              'Coordination file shared between instances.',
            ),
            onCopy: onCopyLockPath,
            onOpen: onOpenLockFolder,
            openTooltip: appLocaleString(
              context,
              'Abrir pasta',
              'Open folder',
            ),
          ),
        ],
      ),
    );
  }
}
