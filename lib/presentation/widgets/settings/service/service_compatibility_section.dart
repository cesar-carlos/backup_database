import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/settings_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Organism** — expandable Windows compatibility diagnostics snapshot.
class ServiceCompatibilitySection extends StatelessWidget {
  const ServiceCompatibilitySection({
    required this.diagnostics,
    required this.onCopyDiagnostics,
    super.key,
  });

  final String diagnostics;
  final VoidCallback onCopyDiagnostics;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: appLocaleString(
        context,
        'Diagnóstico de compatibilidade',
        'Compatibility diagnostics',
      ),
      description: appLocaleString(
        context,
        'Snapshot técnico do ambiente Windows para suporte.',
        'Technical Windows environment snapshot for support.',
      ),
      child: Expander(
        header: Text(
          appLocaleString(
            context,
            'Ver diagnóstico detalhado',
            'View detailed diagnostics',
          ),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsTechnicalItem(
              title: appLocaleString(
                context,
                'Snapshot atual',
                'Current snapshot',
              ),
              value: diagnostics,
              description: appLocaleString(
                context,
                'Resumo técnico usado em troubleshooting.',
                'Technical summary used in troubleshooting.',
              ),
              onCopy: onCopyDiagnostics,
            ),
          ],
        ),
      ),
    );
  }
}
