import 'package:backup_database/application/providers/windows_service_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — last Windows service operation error.
class ServiceErrorSection extends StatelessWidget {
  const ServiceErrorSection({required this.provider, super.key});

  final WindowsServiceProvider provider;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: appLocaleString(context, 'Falha recente', 'Recent failure'),
      description: appLocaleString(
        context,
        'Último erro retornado ao consultar ou operar o serviço.',
        'Latest error returned while querying or operating the service.',
      ),
      child: InfoBar(
        title: Text(appLocaleString(context, 'Erro', 'Error')),
        content: SelectableText(provider.error!),
        severity: InfoBarSeverity.error,
        isLong: true,
      ),
    );
  }
}
