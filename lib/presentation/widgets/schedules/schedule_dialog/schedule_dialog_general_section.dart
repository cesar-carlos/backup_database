import 'dart:async';

import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/utils/database_type_metadata.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_labels.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_section_title.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

class ScheduleDialogGeneralSection extends StatelessWidget {
  const ScheduleDialogGeneralSection({
    required this.formKey,
    required this.nameController,
    required this.nameFieldTouched,
    required this.onNameFirstInteraction,
    required this.databaseTypesForPicker,
    required this.databaseType,
    required this.onDatabaseTypeChanged,
    required this.databaseConfigDropdownKey,
    required this.databaseConfigDropdownBuilder,
    required this.backupType,
    required this.isSybaseConvertedDifferential,
    required this.onBackupTypeCommitted,
    super.key,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final bool nameFieldTouched;
  final VoidCallback onNameFirstInteraction;
  final List<DatabaseType> databaseTypesForPicker;
  final DatabaseType databaseType;
  final ValueChanged<DatabaseType>? onDatabaseTypeChanged;
  final Key databaseConfigDropdownKey;
  final WidgetBuilder databaseConfigDropdownBuilder;
  final BackupType backupType;
  final bool isSybaseConvertedDifferential;
  final ValueChanged<BackupType> onBackupTypeCommitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: nameController,
          label: 'Nome do Agendamento',
          hint: 'Ex: Backup Diário Produção',
          prefixIcon: const Icon(FluentIcons.tag),
          validator: (String? value) {
            if (nameFieldTouched) {
              if (value == null || value.trim().isEmpty) {
                return 'Nome é obrigatório';
              }
            }
            return null;
          },
          onChanged: (String value) {
            if (!nameFieldTouched) {
              onNameFirstInteraction();
            }
          },
        ),
        const SizedBox(height: 24),
        const ScheduleDialogSectionTitle('Banco de Dados'),
        const SizedBox(height: 12),
        AppDropdown<DatabaseType>(
          label: 'Tipo de Banco',
          value: databaseType,
          placeholder: const Text('Tipo de Banco'),
          items: databaseTypesForPicker.map((DatabaseType type) {
            return ComboBoxItem<DatabaseType>(
              value: type,
              child: Text(DatabaseTypeMetadata.of(type).titleLabel),
            );
          }).toList(),
          onChanged: onDatabaseTypeChanged == null
              ? null
              : (DatabaseType? value) {
                  if (value != null) {
                    onDatabaseTypeChanged!(value);
                    formKey.currentState?.validate();
                  }
                },
        ),
        const SizedBox(height: 16),
        Builder(
          key: databaseConfigDropdownKey,
          builder: databaseConfigDropdownBuilder,
        ),
        const SizedBox(height: 24),
        const ScheduleDialogSectionTitle('Tipo de Backup'),
        const SizedBox(height: 12),
        Consumer<LicenseProvider>(
          builder: (BuildContext context, LicenseProvider licenseProvider, _) {
            final license = licenseProvider.currentLicense;
            final hasDifferential =
                licenseProvider.hasValidLicense &&
                (license?.hasFeature(LicenseFeatures.differentialBackup) ??
                    false);
            final hasLog =
                licenseProvider.hasValidLicense &&
                (license?.hasFeature(LicenseFeatures.logBackup) ?? false);

            final List<BackupType> allTypes;
            if (databaseType == DatabaseType.sybase) {
              allTypes = [
                BackupType.full,
                BackupType.log,
                if (isSybaseConvertedDifferential) BackupType.differential,
              ];
            } else if (databaseType == DatabaseType.postgresql) {
              allTypes = [
                BackupType.full,
                BackupType.fullSingle,
                BackupType.differential,
                BackupType.log,
              ];
            } else if (databaseType == DatabaseType.firebird) {
              // Firebird suporta backup fisico (nbackup -B 0/-B 1) e
              // logico (gbak). O backend mapeia Diferencial/Log para
              // `nbackup -B 1` e Full Single para `gbak`. A regra
              // `FirebirdSupportedBackupTypesRule` aceita todos exceto
              // `convertedFullSingle`.
              allTypes = [
                BackupType.full,
                BackupType.fullSingle,
                BackupType.differential,
                BackupType.log,
              ];
            } else {
              allTypes = [
                BackupType.full,
                BackupType.differential,
                BackupType.log,
              ];
            }

            return AppDropdown<BackupType>(
              label: 'Tipo de Backup',
              value: backupType,
              placeholder: const Text('Tipo de Backup'),
              items: allTypes.map((BackupType type) {
                final isDifferentialBlocked =
                    type == BackupType.differential && !hasDifferential;
                final isLogBlocked = type == BackupType.log && !hasLog;
                final isSybaseConvertedType =
                    databaseType == DatabaseType.sybase &&
                    type == BackupType.differential;
                final isBlocked = isDifferentialBlocked || isLogBlocked;

                return ComboBoxItem<BackupType>(
                  value: type,
                  enabled: !isBlocked,
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                isBlocked
                                    ? '${type.displayName} (Requer licença)'
                                    : isSybaseConvertedType
                                    ? 'Incremental (Transaction Log)'
                                    : type.displayName,
                                textAlign: TextAlign.start,
                                style: TextStyle(
                                  color: isBlocked
                                      ? FluentTheme.of(context)
                                            .resources
                                            .controlStrokeColorDefault
                                            .withValues(alpha: 0.4)
                                      : isSybaseConvertedType
                                      ? FluentTheme.of(
                                          context,
                                        ).accentColor.defaultBrushFor(
                                          FluentTheme.of(context).brightness,
                                        )
                                      : null,
                                  fontStyle: isSybaseConvertedType
                                      ? FontStyle.italic
                                      : null,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isBlocked) ...[
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
                            if (isSybaseConvertedType) ...[
                              const SizedBox(width: 8),
                              Icon(
                                FluentIcons.switch_widget,
                                size: 14,
                                color: FluentTheme.of(context).accentColor,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (BackupType? value) {
                if (value != null) {
                  final licenseInner = licenseProvider.currentLicense;
                  final hasDifferentialInner =
                      licenseProvider.hasValidLicense &&
                      (licenseInner?.hasFeature(
                            LicenseFeatures.differentialBackup,
                          ) ??
                          false);
                  final hasLogInner =
                      licenseProvider.hasValidLicense &&
                      (licenseInner?.hasFeature(LicenseFeatures.logBackup) ??
                          false);

                  final isDifferentialBlocked =
                      value == BackupType.differential && !hasDifferentialInner;
                  final isLogBlocked = value == BackupType.log && !hasLogInner;

                  if (isDifferentialBlocked || isLogBlocked) {
                    unawaited(
                      FluentInfoBarFeedback.showWarning(
                        context,
                        message:
                            'Este tipo de backup requer uma licença válida. '
                            'Acesse Configurações > Licenciamento para mais informações.',
                      ),
                    );
                    return;
                  }

                  onBackupTypeCommitted(value);
                }
              },
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          ScheduleDialogLabels.backupTypeDescription(
            databaseType,
            backupType,
          ),
          style: FluentTheme.of(context).typography.caption,
        ),
      ],
    );
  }
}
