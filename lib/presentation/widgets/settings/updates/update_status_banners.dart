import 'package:backup_database/application/providers/auto_update_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — error and "update available" InfoBars.
class UpdateStatusBanners extends StatelessWidget {
  const UpdateStatusBanners({required this.provider, super.key});

  final AutoUpdateProvider provider;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (provider.error != null) ...[
          const SizedBox(height: AppSpacing.md),
          InfoBar(
            title: Text(
              appLocaleString(context, 'Falha recente', 'Recent failure'),
            ),
            content: Text(provider.error!),
            severity: InfoBarSeverity.error,
            isLong: true,
          ),
        ],
        if (provider.updateAvailable) ...[
          const SizedBox(height: AppSpacing.md),
          InfoBar(
            title: Text(
              appLocaleString(
                context,
                'Atualizacao disponivel',
                'Update available',
              ),
            ),
            content: Text(
              appLocaleString(
                context,
                'Uma nova versao esta pronta para o ciclo automatico.',
                'A new version is ready for the automatic cycle.',
              ),
            ),
            severity: InfoBarSeverity.success,
            isLong: true,
          ),
        ],
      ],
    );
  }
}
