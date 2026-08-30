import 'package:backup_database/application/providers/auto_update_provider.dart';
import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — check / config / feed actions for the updater.
class UpdateActionsRow extends StatelessWidget {
  const UpdateActionsRow({
    required this.provider,
    required this.onCheckUpdates,
    required this.onOpenConfigFolder,
    required this.onCopyFeed,
    required this.onOpenFeed,
    super.key,
  });

  final AutoUpdateProvider provider;
  final VoidCallback onCheckUpdates;
  final VoidCallback onOpenConfigFolder;
  final VoidCallback onCopyFeed;
  final VoidCallback onOpenFeed;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        // P3#13: botão desabilitado quando o serviço está
        // disabled — checkNow no-op em disabled levava a UX
        // "clico e nada acontece, nem logs novos".
        Tooltip(
          message: provider.isDisabled
              ? appLocaleString(
                  context,
                  'Updater indisponivel. Resolva o motivo no '
                      'painel acima antes de tentar novamente.',
                  'Updater unavailable. Resolve the reason in the '
                      'panel above before retrying.',
                )
              : '',
          child: AppButton.primary(
            label: appLocaleString(
              context,
              'Verificar atualizacoes',
              'Check for updates',
            ),
            isLoading: provider.isChecking,
            onPressed: provider.isDisabled ? null : onCheckUpdates,
          ),
        ),
        // P3#14: ação corretiva inline quando faltam chaves de
        // config — abre a pasta do .env direto, sem o usuário
        // ter que decifrar o path no painel técnico.
        if (provider.disabledReason == AppUpdateDisabledReason.feedUrlMissing ||
            provider.disabledReason ==
                AppUpdateDisabledReason.dotenvLoadFailed ||
            provider.disabledReason ==
                AppUpdateDisabledReason.feedReaderException)
          AppButton(
            label: appLocaleString(
              context,
              'Abrir pasta de configuracao',
              'Open config folder',
            ),
            onPressed: onOpenConfigFolder,
          ),
        if (provider.feedUrl != null)
          AppButton(
            label: appLocaleString(context, 'Copiar feed', 'Copy feed'),
            onPressed: onCopyFeed,
          ),
        if (provider.feedUrl != null)
          AppButton(
            label: appLocaleString(context, 'Abrir feed', 'Open feed'),
            onPressed: onOpenFeed,
          ),
      ],
    );
  }
}
