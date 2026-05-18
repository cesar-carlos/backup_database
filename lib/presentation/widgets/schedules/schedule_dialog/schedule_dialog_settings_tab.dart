import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_advanced_database_section.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_compression_verify_section.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_destinations_section.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_timeouts_section.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/widgets.dart';

class ScheduleDialogSettingsTab extends StatelessWidget {
  const ScheduleDialogSettingsTab({
    required this.destinationSelector,
    required this.backupFolderController,
    required this.onSelectBackupFolderPressed,
    required this.compressBackup,
    required this.onCompressBackupChanged,
    required this.compressionFormat,
    required this.onCompressionFormatChanged,
    required this.schedulingEnabled,
    required this.onSchedulingEnabledChanged,
    required this.backupTimeoutMinutesController,
    required this.verifyTimeoutMinutesController,
    required this.onBackupTimeoutMinutesParsed,
    required this.onVerifyTimeoutMinutesParsed,
    required this.databaseType,
    required this.backupType,
    required this.enableChecksum,
    required this.onEnableChecksumChanged,
    required this.verifyAfterBackup,
    required this.onVerifyAfterBackupChanged,
    required this.verifyPolicy,
    required this.onVerifyPolicyChanged,
    required this.sqlServerAdvancedBuilder,
    required this.sybaseAdvancedBuilder,
    required this.firebirdAdvancedBuilder,
    super.key,
  });

  final Widget destinationSelector;
  final TextEditingController backupFolderController;
  final VoidCallback onSelectBackupFolderPressed;
  final bool compressBackup;
  final ValueChanged<bool> onCompressBackupChanged;
  final CompressionFormat compressionFormat;
  final ValueChanged<CompressionFormat> onCompressionFormatChanged;
  final bool schedulingEnabled;
  final ValueChanged<bool> onSchedulingEnabledChanged;
  final TextEditingController backupTimeoutMinutesController;
  final TextEditingController verifyTimeoutMinutesController;
  final ValueChanged<int> onBackupTimeoutMinutesParsed;
  final ValueChanged<int> onVerifyTimeoutMinutesParsed;
  final DatabaseType databaseType;
  final BackupType backupType;
  final bool enableChecksum;
  final ValueChanged<bool> onEnableChecksumChanged;
  final bool verifyAfterBackup;
  final ValueChanged<bool> onVerifyAfterBackupChanged;
  final VerifyPolicy verifyPolicy;
  final ValueChanged<VerifyPolicy> onVerifyPolicyChanged;
  final Widget Function() sqlServerAdvancedBuilder;
  final Widget Function() sybaseAdvancedBuilder;
  final Widget Function() firebirdAdvancedBuilder;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScheduleDialogDestinationsAndFolderSection(
            destinationSelector: destinationSelector,
            backupFolderController: backupFolderController,
            onSelectBackupFolderPressed: onSelectBackupFolderPressed,
          ),
          const SizedBox(height: 24),
          ScheduleDialogCompressionSchedulingSection(
            compressBackup: compressBackup,
            onCompressBackupChanged: onCompressBackupChanged,
            compressionFormat: compressionFormat,
            onCompressionFormatChanged: onCompressionFormatChanged,
            schedulingEnabled: schedulingEnabled,
            onSchedulingEnabledChanged: onSchedulingEnabledChanged,
          ),
          const SizedBox(height: 24),
          ScheduleDialogTimeoutsSection(
            backupTimeoutMinutesController: backupTimeoutMinutesController,
            verifyTimeoutMinutesController: verifyTimeoutMinutesController,
            onBackupTimeoutMinutesParsed: onBackupTimeoutMinutesParsed,
            onVerifyTimeoutMinutesParsed: onVerifyTimeoutMinutesParsed,
          ),
          const SizedBox(height: 24),
          ScheduleDialogIntegritySection(
            databaseType: databaseType,
            backupType: backupType,
            enableChecksum: enableChecksum,
            onEnableChecksumChanged: onEnableChecksumChanged,
            verifyAfterBackup: verifyAfterBackup,
            onVerifyAfterBackupChanged: onVerifyAfterBackupChanged,
            verifyPolicy: verifyPolicy,
            onVerifyPolicyChanged: onVerifyPolicyChanged,
          ),
          ScheduleDialogAdvancedDatabaseSection.build(
            databaseType: databaseType,
            sqlServerAdvancedBuilder: sqlServerAdvancedBuilder,
            sybaseAdvancedBuilder: sybaseAdvancedBuilder,
            firebirdAdvancedBuilder: firebirdAdvancedBuilder,
          ),
        ],
      ),
    );
  }
}
