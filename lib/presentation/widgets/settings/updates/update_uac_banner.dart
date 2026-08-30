import 'package:backup_database/application/providers/auto_update_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — UAC-gate banner with an inline manual update action.
class UpdateUacBanner extends StatelessWidget {
  const UpdateUacBanner({
    required this.provider,
    required this.onUpdateNow,
    super.key,
  });

  final AutoUpdateProvider provider;
  final VoidCallback onUpdateNow;

  @override
  Widget build(BuildContext context) {
    return InfoBar(
      title: Text(
        appLocaleString(
          context,
          'Aprovacao UAC necessaria',
          'UAC approval required',
        ),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            provider.statusMessage ??
                appLocaleString(
                  context,
                  'O Windows pediria aprovacao UAC para instalar a '
                      'nova versao. Auto-update silencioso esta '
                      'pausado para nao quebrar a sua tela do nada. '
                      'Clique abaixo para iniciar manualmente e '
                      'confirmar o prompt.',
                  'Windows would request UAC approval to install the '
                      'new version. Silent auto-update is paused so '
                      'it does not interrupt you. Click below to '
                      'start it manually and confirm the prompt.',
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppButton.primary(
                label: appLocaleString(
                  context,
                  'Atualizar agora',
                  'Update now',
                ),
                isLoading: provider.isChecking,
                onPressed: onUpdateNow,
              ),
            ],
          ),
        ],
      ),
      severity: InfoBarSeverity.warning,
      isLong: true,
    );
  }
}
