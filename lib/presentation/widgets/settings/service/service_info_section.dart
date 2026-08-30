import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/settings_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Organism** — service execution facts and log directory.
class ServiceInfoSection extends StatelessWidget {
  const ServiceInfoSection({
    required this.onCopyLogPath,
    required this.onOpenLogFolder,
    super.key,
  });

  final VoidCallback onCopyLogPath;
  final VoidCallback onOpenLogFolder;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: appLocaleString(context, 'Informações', 'Information'),
      description: appLocaleString(
        context,
        'Referências operacionais do modo serviço em formato compacto.',
        'Operational service-mode references in a compact layout.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              SettingsFactTile(
                label: appLocaleString(
                  context,
                  'Execução',
                  'Execution',
                ),
                value: appLocaleString(
                  context,
                  'Sem usuário logado',
                  'Without logged-in user',
                ),
                caption: appLocaleString(
                  context,
                  'Backups continuam mesmo sem sessão aberta.',
                  'Backups keep running without an open session.',
                ),
              ),
              SettingsFactTile(
                label: appLocaleString(
                  context,
                  'Inicialização',
                  'Startup',
                ),
                value: appLocaleString(
                  context,
                  'Automática com o Windows',
                  'Automatic with Windows',
                ),
                caption: appLocaleString(
                  context,
                  'Quando o serviço está instalado e habilitado.',
                  'When the service is installed and enabled.',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SettingsTechnicalItem(
            title: appLocaleString(context, 'Logs do serviço', 'Service logs'),
            value: '${AppConstants.windowsServiceLogPath}\\',
            description: appLocaleString(
              context,
              'Diretório padrão de logs do Windows Service.',
              'Default Windows Service log directory.',
            ),
            onCopy: onCopyLogPath,
            onOpen: onOpenLogFolder,
            openTooltip: appLocaleString(context, 'Abrir pasta', 'Open folder'),
          ),
        ],
      ),
    );
  }
}
