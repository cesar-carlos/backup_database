import 'package:backup_database/application/providers/windows_service_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/settings_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ServiceStatusSection extends StatelessWidget {
  const ServiceStatusSection({
    required this.statusText,
    required this.provider,
    super.key,
  });

  final String statusText;
  final WindowsServiceProvider provider;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: appLocaleString(context, 'Status do serviço', 'Service status'),
      description: appLocaleString(
        context,
        'Estado atual do processo em background e da instalação do serviço.',
        'Current background process state and service installation state.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              SettingsFactTile(
                label: appLocaleString(context, 'Estado', 'State'),
                value: statusText,
                caption: appLocaleString(
                  context,
                  'Situação observada pelo provedor neste instante.',
                  'State observed by the provider right now.',
                ),
              ),
              if (provider.status?.serviceName != null)
                SettingsFactTile(
                  label: appLocaleString(context, 'Serviço', 'Service'),
                  value: provider.status!.serviceName!,
                  caption: appLocaleString(
                    context,
                    'Nome registrado no Windows Service Manager.',
                    'Name registered in the Windows Service Manager.',
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppStatusChip(
            label: statusText,
            tone: provider.isLoading
                ? AppStatusChipTone.info
                : provider.isRunning
                ? AppStatusChipTone.success
                : provider.isInstalled
                ? AppStatusChipTone.warning
                : AppStatusChipTone.neutral,
            icon: provider.isLoading
                ? FluentIcons.sync
                : provider.isRunning
                ? FluentIcons.play
                : provider.isInstalled
                ? FluentIcons.pause
                : FluentIcons.circle_ring,
          ),
        ],
      ),
    );
  }
}
