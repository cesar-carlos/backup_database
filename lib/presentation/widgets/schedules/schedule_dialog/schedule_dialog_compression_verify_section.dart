import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/constants/schedule_dialog_strings.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_section_title.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

String _verifyPolicyDescription(VerifyPolicy policy) {
  switch (policy) {
    case VerifyPolicy.bestEffort:
      return 'Verifica a integridade do backup, mas continua mesmo em caso '
          'de falha na verificação.';
    case VerifyPolicy.strict:
      return 'Verifica a integridade do backup. Se a verificação falhar, o '
          'backup é considerado falho.';
    case VerifyPolicy.none:
      return 'Não realiza verificação de integridade do backup.';
  }
}

Widget _checkboxWithInfo({
  required String label,
  required bool value,
  required String infoText,
  ValueChanged<bool>? onChanged,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: InfoLabel(
          label: label,
          child: Checkbox(
            checked: value,
            onChanged: onChanged != null
                ? (bool? checked) => onChanged(checked ?? false)
                : null,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Tooltip(
          message: infoText,
          child: IconButton(
            icon: const Icon(FluentIcons.info, size: 16),
            onPressed: () {},
          ),
        ),
      ),
    ],
  );
}

class ScheduleDialogCompressionSchedulingSection extends StatelessWidget {
  const ScheduleDialogCompressionSchedulingSection({
    required this.compressBackup,
    required this.onCompressBackupChanged,
    required this.compressionFormat,
    required this.onCompressionFormatChanged,
    required this.schedulingEnabled,
    required this.onSchedulingEnabledChanged,
    super.key,
  });

  final bool compressBackup;
  final ValueChanged<bool> onCompressBackupChanged;
  final CompressionFormat compressionFormat;
  final ValueChanged<CompressionFormat> onCompressionFormatChanged;
  final bool schedulingEnabled;
  final ValueChanged<bool> onSchedulingEnabledChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScheduleDialogSectionTitle(ScheduleDialogStrings.options),
        const SizedBox(height: 12),
        InfoLabel(
          label: ScheduleDialogStrings.compressBackup,
          child: ToggleSwitch(
            checked: compressBackup,
            onChanged: onCompressBackupChanged,
          ),
        ),
        if (compressBackup) ...[
          const SizedBox(height: 16),
          AppDropdown<CompressionFormat>(
            label: ScheduleDialogStrings.compressionFormat,
            value: compressionFormat,
            placeholder: const Text(
              ScheduleDialogStrings.compressionFormatPlaceholder,
            ),
            items: const [
              ComboBoxItem<CompressionFormat>(
                value: CompressionFormat.zip,
                child: Text(ScheduleDialogStrings.compressionFormatZip),
              ),
              ComboBoxItem<CompressionFormat>(
                value: CompressionFormat.rar,
                child: Text(ScheduleDialogStrings.compressionFormatRar),
              ),
            ],
            onChanged: (CompressionFormat? value) {
              if (value != null) {
                onCompressionFormatChanged(value);
              }
            },
          ),
        ],
        const SizedBox(height: 16),
        InfoLabel(
          label: ScheduleDialogStrings.schedulingEnabled,
          child: ToggleSwitch(
            checked: schedulingEnabled,
            onChanged: onSchedulingEnabledChanged,
          ),
        ),
      ],
    );
  }
}

class ScheduleDialogIntegritySection extends StatelessWidget {
  const ScheduleDialogIntegritySection({
    required this.databaseType,
    required this.backupType,
    required this.enableChecksum,
    required this.onEnableChecksumChanged,
    required this.verifyAfterBackup,
    required this.onVerifyAfterBackupChanged,
    required this.verifyPolicy,
    required this.onVerifyPolicyChanged,
    super.key,
  });

  final DatabaseType databaseType;
  final BackupType backupType;
  final bool enableChecksum;
  final ValueChanged<bool> onEnableChecksumChanged;
  final bool verifyAfterBackup;
  final ValueChanged<bool> onVerifyAfterBackupChanged;
  final VerifyPolicy verifyPolicy;
  final ValueChanged<VerifyPolicy> onVerifyPolicyChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScheduleDialogSectionTitle('Verificação de Integridade'),
        const SizedBox(height: 12),
        if (databaseType == DatabaseType.firebird &&
            backupType != BackupType.fullSingle) ...[
          const InfoBar(
            title: Text('Firebird (backup físico)'),
            content: Text(
              'Verify after backup não restaura ficheiros .nbk; a verificação '
              'por `gbak -c` aplica-se apenas a Full Single (.fbk). Com esta '
              'opção ativa, o serviço regista aviso e ignora o passo em '
              'backups físicos (nbackup). Política estrita com nbackup é '
              'rejeitada na execução.',
            ),
            severity: InfoBarSeverity.warning,
          ),
          const SizedBox(height: 12),
        ],
        if (databaseType == DatabaseType.sqlServer)
          Consumer<LicenseProvider>(
            builder: (BuildContext context, LicenseProvider licenseProvider, _) {
              final license = licenseProvider.currentLicense;
              final hasChecksum =
                  licenseProvider.hasValidLicense &&
                  (license?.hasFeature(LicenseFeatures.checksum) ?? false);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _checkboxWithInfo(
                          label: hasChecksum
                              ? 'Enable CheckSum'
                              : 'Enable CheckSum (Requer licença)',
                          value: enableChecksum,
                          onChanged: hasChecksum
                              ? onEnableChecksumChanged
                              : null,
                          infoText: hasChecksum
                              ? 'Habilita o cálculo de checksums durante o backup. '
                                    'Detecta corrupção de dados durante o processo de backup.'
                              : 'Este recurso requer uma licença válida. '
                                    'Acesse Configurações > Licenciamento para mais informações.',
                        ),
                      ),
                      if (!hasChecksum) ...[
                        const SizedBox(width: 8),
                        Icon(
                          FluentIcons.lock,
                          size: 16,
                          color: FluentTheme.of(context)
                              .resources
                              .controlStrokeColorDefault
                              .withValues(alpha: 0.4),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        Consumer<LicenseProvider>(
          builder: (BuildContext context, LicenseProvider licenseProvider, _) {
            final license = licenseProvider.currentLicense;
            final hasVerifyIntegrity =
                licenseProvider.hasValidLicense &&
                (license?.hasFeature(LicenseFeatures.verifyIntegrity) ?? false);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _checkboxWithInfo(
                        label: hasVerifyIntegrity
                            ? 'Verify After Backup'
                            : 'Verify After Backup (Requer licença)',
                        value: verifyAfterBackup,
                        onChanged: hasVerifyIntegrity
                            ? onVerifyAfterBackupChanged
                            : null,
                        infoText: hasVerifyIntegrity
                            ? (databaseType == DatabaseType.sqlServer
                                  ? 'Verifica a integridade do backup após criação usando RESTORE VERIFYONLY. '
                                        'Garante que o backup pode ser restaurado sem restaurar os dados.'
                                  : databaseType == DatabaseType.postgresql
                                  ? 'Verifica a integridade do backup após criação usando pg_verifybackup. '
                                        'Garante que o backup está íntegro e pode ser restaurado.'
                                  : databaseType == DatabaseType.firebird
                                  ? 'Após Full Single (gbak), verifica o .fbk '
                                        'restaurando para um ficheiro .fdb '
                                        'temporário local (`gbak -c`) e apaga-o. '
                                        'Não se aplica a backup físico (nbackup). '
                                        'Política estrita: falha na verificação '
                                        'aborta o backup com erro.'
                                  : 'Verifica a integridade do backup após criação usando dbvalid '
                                        '(fallback dbverify). Garante que o backup está íntegro.')
                            : 'Este recurso requer uma licença válida. '
                                  'Acesse Configurações > Licenciamento para mais informações.',
                      ),
                    ),
                    if (!hasVerifyIntegrity) ...[
                      const SizedBox(width: 8),
                      Icon(
                        FluentIcons.lock,
                        size: 16,
                        color: FluentTheme.of(context)
                            .resources
                            .controlStrokeColorDefault
                            .withValues(alpha: 0.4),
                      ),
                    ],
                  ],
                ),
                if (verifyAfterBackup) ...[
                  const SizedBox(height: 16),
                  AppDropdown<VerifyPolicy>(
                    label: 'Política de Verificação',
                    value: verifyPolicy,
                    placeholder: const Text('Política de Verificação'),
                    items: const [
                      ComboBoxItem<VerifyPolicy>(
                        value: VerifyPolicy.bestEffort,
                        child: Text('Melhor Esforço (Best Effort)'),
                      ),
                      ComboBoxItem<VerifyPolicy>(
                        value: VerifyPolicy.strict,
                        child: Text('Estrito (Strict)'),
                      ),
                      ComboBoxItem<VerifyPolicy>(
                        value: VerifyPolicy.none,
                        child: Text('Nenhum (None)'),
                      ),
                    ],
                    onChanged: (VerifyPolicy? value) {
                      if (value != null) {
                        onVerifyPolicyChanged(value);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _verifyPolicyDescription(verifyPolicy),
                    style: FluentTheme.of(context).typography.caption,
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}
