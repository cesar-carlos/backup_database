import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/firebird/firebird_config_dialog/firebird_dialog_labels.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — name, host/port, database file and alias.
class FirebirdConnectionSection extends StatelessWidget {
  const FirebirdConnectionSection({
    required this.nameController,
    required this.hostController,
    required this.portController,
    required this.databaseFileController,
    required this.aliasController,
    required this.useEmbedded,
    super.key,
  });

  final TextEditingController nameController;
  final TextEditingController hostController;
  final TextEditingController portController;
  final TextEditingController databaseFileController;
  final TextEditingController aliasController;
  final bool useEmbedded;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: nameController,
          label: appLocaleString(
            context,
            'Nome da configuração',
            'Configuration name',
          ),
          hint: 'Ex: Produção Firebird',
          validator: (String? value) {
            if (value == null || value.trim().isEmpty) {
              return appLocaleString(
                context,
                'Nome é obrigatório',
                'Name is required',
              );
            }
            return null;
          },
          prefixIcon: const Icon(FluentIcons.tag),
        ),
        const SizedBox(height: AppSpacing.md),
        HostPortFields(
          hostController: hostController,
          portController: portController,
          hostLabel: appLocaleString(context, 'Host', 'Host'),
          portLabel: appLocaleString(context, 'Porta', 'Port'),
          hostHint: appLocaleString(
            context,
            'localhost ou IP',
            'localhost or IP',
          ),
          portHint: '$defaultFirebirdPort',
          hostEnabled: !useEmbedded,
          hostValidator: (String? value) {
            if (!useEmbedded && (value == null || value.trim().isEmpty)) {
              return appLocaleString(
                context,
                'Host é obrigatório',
                'Host is required',
              );
            }
            return null;
          },
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: databaseFileController,
          label: appLocaleString(
            context,
            'Arquivo do banco (.fdb)',
            'Database file (.fdb)',
          ),
          hint: r'C:\Dados\minha_base.fdb',
          validator: (String? value) {
            final pathEmpty = value == null || value.trim().isEmpty;
            final aliasEmpty = aliasController.text.trim().isEmpty;
            if (pathEmpty && aliasEmpty) {
              return appLocaleString(
                context,
                'Informe o caminho do arquivo ou um alias',
                'Enter the database file path or an alias',
              );
            }
            return null;
          },
          prefixIcon: const Icon(FluentIcons.open_file),
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: aliasController,
          label: appLocaleString(
            context,
            'Alias (opcional)',
            'Alias (optional)',
          ),
          hint: appLocaleString(
            context,
            'Nome lógico no databases.conf',
            'Logical name in databases.conf',
          ),
          prefixIcon: const Icon(FluentIcons.link),
        ),
      ],
    );
  }
}
