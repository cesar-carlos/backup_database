import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/settings_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Organism** — version, app mode and license metadata.
class SystemAboutSection extends StatelessWidget {
  const SystemAboutSection({
    required this.versionLabel,
    required this.modeLabel,
    super.key,
  });

  final String versionLabel;
  final String modeLabel;

  @override
  Widget build(BuildContext context) {
    final cards = [
      SettingsFactTile(
        label: appLocaleString(context, 'Versao', 'Version'),
        value: versionLabel,
        expandToFit: true,
        caption: appLocaleString(
          context,
          'Versao instalada nesta maquina.',
          'Version installed on this machine.',
        ),
      ),
      SettingsFactTile(
        label: appLocaleString(context, 'Modo atual', 'Current mode'),
        value: modeLabel,
        expandToFit: true,
        caption: appLocaleString(
          context,
          'Contexto de operacao ativo na inicializacao.',
          'Operation context active at startup.',
        ),
      ),
      SettingsFactTile(
        label: appLocaleString(context, 'Licenca', 'License'),
        value: 'MIT License',
        expandToFit: true,
        caption: appLocaleString(
          context,
          'Termo de distribuicao do aplicativo.',
          'Application distribution terms.',
        ),
      ),
    ];

    return AppSectionCard(
      title: appLocaleString(context, 'Sobre', 'About'),
      description: appLocaleString(
        context,
        'Metadados principais da instalacao local.',
        'Main metadata for the local installation.',
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= AppBreakpoints.compact) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: cards[1]),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: cards[2]),
                ],
              ),
            );
          }

          return Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: cards,
          );
        },
      ),
    );
  }
}
