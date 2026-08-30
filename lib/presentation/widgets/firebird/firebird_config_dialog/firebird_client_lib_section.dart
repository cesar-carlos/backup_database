import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:backup_database/domain/value_objects/firebird_config_enums.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/firebird/firebird_config_dialog/firebird_dialog_labels.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — client library, version hint, service manager, crypt
/// key, enabled flag and connection-test hint.
class FirebirdClientLibSection extends StatelessWidget {
  const FirebirdClientLibSection({
    required this.clientLibController,
    required this.cryptKeyController,
    required this.serverVersionHint,
    required this.serviceManagerMode,
    required this.isEnabled,
    required this.onServerVersionHintChanged,
    required this.onServiceManagerModeChanged,
    required this.onEnabledChanged,
    super.key,
  });

  final TextEditingController clientLibController;
  final TextEditingController cryptKeyController;
  final FirebirdServerVersionHint serverVersionHint;
  final FirebirdServiceManagerMode serviceManagerMode;
  final bool isEnabled;
  final ValueChanged<FirebirdServerVersionHint> onServerVersionHintChanged;
  final ValueChanged<FirebirdServiceManagerMode> onServiceManagerModeChanged;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: clientLibController,
          label: appLocaleString(
            context,
            'fbclient.dll (opcional)',
            'fbclient.dll (optional)',
          ),
          hint: appLocaleString(
            context,
            'Caminho completo se não estiver no PATH',
            'Full path if not on PATH',
          ),
          prefixIcon: const Icon(FluentIcons.folder),
        ),
        const SizedBox(height: AppSpacing.md),
        AppDropdown<FirebirdServerVersionHint>(
          label: appLocaleString(
            context,
            'Versão do servidor (dica)',
            'Server version (hint)',
          ),
          value: serverVersionHint,
          items: FirebirdServerVersionHint.values
              .map(
                (FirebirdServerVersionHint v) =>
                    ComboBoxItem<FirebirdServerVersionHint>(
                      value: v,
                      child: Text(firebirdVersionHintLabel(context, v)),
                    ),
              )
              .toList(growable: false),
          onChanged: (FirebirdServerVersionHint? value) {
            if (value != null) {
              onServerVersionHintChanged(value);
            }
          },
        ),
        const SizedBox(height: AppSpacing.md),
        AppDropdown<FirebirdServiceManagerMode>(
          label: appLocaleString(
            context,
            'Gerenciador de serviço',
            'Service manager',
          ),
          value: serviceManagerMode,
          items: FirebirdServiceManagerMode.values
              .map(
                (FirebirdServiceManagerMode v) =>
                    ComboBoxItem<FirebirdServiceManagerMode>(
                      value: v,
                      child: Text(firebirdServiceManagerModeLabel(context, v)),
                    ),
              )
              .toList(growable: false),
          onChanged: (FirebirdServiceManagerMode? value) {
            if (value != null) {
              onServiceManagerModeChanged(value);
            }
          },
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: cryptKeyController,
          label: appLocaleString(
            context,
            'Chave de criptografia (não suportada nesta versão)',
            'Encryption key (not supported in this version)',
          ),
          hint: appLocaleString(
            context,
            'Backup logico encriptado requer -CRYPT + -KEYHOLDER + '
                '-KEYNAME (FB 3+); UI dedicada virá em versão futura.',
            'Encrypted logical backup needs -CRYPT + -KEYHOLDER + '
                '-KEYNAME (FB 3+); dedicated UI coming in a future '
                'release.',
          ),
          prefixIcon: const Icon(FluentIcons.lock),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          appLocaleString(
            context,
            'Aviso: backups Firebird com chave preenchida são '
                'rejeitados antes de invocar gbak (a flag -key não '
                'existe; -KEYNAME sozinho não encripta). Valor é '
                'preservado entre versões via secure storage.',
            'Warning: Firebird backups with a key filled are rejected '
                'before invoking gbak (the -key flag does not exist; '
                '-KEYNAME alone does not encrypt). Value is preserved '
                'across versions via secure storage.',
          ),
          style: FluentTheme.of(context).typography.caption,
        ),
        const SizedBox(height: AppSpacing.md),
        LabeledToggle(
          title: appLocaleString(context, 'Habilitado', 'Enabled'),
          description: appLocaleString(
            context,
            'Configuração ativa para uso em agendamentos',
            'Configuration active for schedules',
          ),
          value: isEnabled,
          onChanged: onEnabledChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        InfoLabel(
          label: appLocaleString(
            context,
            'Teste de conexão',
            'Connection test',
          ),
          child: Text(
            appLocaleString(
              context,
              'Usa gstat -h com as credenciais informadas (mesma base '
                  'usada pelo agendamento).',
              'Uses gstat -h with the credentials entered (same probe '
                  'as scheduling).',
            ),
          ),
        ),
      ],
    );
  }
}
