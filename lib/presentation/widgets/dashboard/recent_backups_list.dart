import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

class RecentBackupsList extends StatelessWidget {
  const RecentBackupsList({required this.backups, super.key});
  final List<BackupHistory> backups;

  @override
  Widget build(BuildContext context) {
    if (backups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            appLocaleString(
              context,
              'Nenhum backup recente',
              'No recent backup',
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: backups.length,
      itemBuilder: (context, index) {
        final backup = backups[index];
        return ListTile(
          leading: Icon(
            _getStatusIcon(backup.status),
            color: _getStatusColor(backup.status),
          ),
          title: Text(backup.databaseName),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(DateFormat('dd/MM/yyyy HH:mm').format(backup.startedAt)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    _getBackupTypeIcon(backup.backupType),
                    size: 14,
                    color: _getBackupTypeColor(backup.backupType),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    backupTypeFromString(backup.backupType).displayName,
                    style: TextStyle(
                      fontSize: 12,
                      color: _getBackupTypeColor(backup.backupType),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (_buildRequestedVsExecutedText(context, backup)
                  case final divergence?) ...[
                const SizedBox(height: 4),
                Text(
                  divergence,
                  style:
                      FluentTheme.of(
                        context,
                      ).typography.caption?.copyWith(
                        color: AppPalette.backupWarning,
                      ),
                ),
              ],
              if (_hasSybaseDetails(backup)) ...[
                const SizedBox(height: 4),
                Text(
                  _buildSybaseDetailsText(context, backup),
                  style: FluentTheme.of(context).typography.caption,
                ),
              ],
            ],
          ),
          trailing: Text(
            _getStatusText(context, backup.status),
            style: TextStyle(
              color: _getStatusColor(backup.status),
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }

  IconData _getStatusIcon(BackupStatus status) {
    switch (status) {
      case BackupStatus.success:
        return FluentIcons.check_mark;
      case BackupStatus.error:
        return FluentIcons.error;
      case BackupStatus.warning:
        return FluentIcons.warning;
      case BackupStatus.running:
        return FluentIcons.sync;
    }
  }

  Color _getStatusColor(BackupStatus status) {
    switch (status) {
      case BackupStatus.success:
        return AppPalette.backupSuccess;
      case BackupStatus.error:
        return AppPalette.backupError;
      case BackupStatus.warning:
        return AppPalette.backupWarning;
      case BackupStatus.running:
        return AppPalette.backupRunning;
    }
  }

  String _getStatusText(BuildContext context, BackupStatus status) {
    switch (status) {
      case BackupStatus.success:
        return appLocaleString(context, 'Sucesso', 'Success');
      case BackupStatus.error:
        return appLocaleString(context, 'Erro', 'Error');
      case BackupStatus.warning:
        return appLocaleString(context, 'Aviso', 'Warning');
      case BackupStatus.running:
        return appLocaleString(context, 'Em progresso', 'In progress');
    }
  }

  IconData _getBackupTypeIcon(String backupType) {
    final type = backupTypeFromString(backupType);
    switch (type) {
      case BackupType.full:
      case BackupType.fullSingle:
      case BackupType.convertedFullSingle:
        return FluentIcons.database;
      case BackupType.differential:
      case BackupType.convertedDifferential:
        return FluentIcons.database_sync;
      case BackupType.log:
      case BackupType.convertedLog:
        return FluentIcons.database_view;
    }
  }

  bool _hasSybaseDetails(BackupHistory backup) =>
      backup.databaseType.toLowerCase() == 'sybase' && backup.metrics != null;

  /// Quando o tipo de backup executado difere do solicitado (ex.: PG
  /// incremental → full por falta de base, ou Sybase log convertido),
  /// retorna texto curto descrevendo a divergência. Funciona para
  /// qualquer SGBD pois `requestedBackupType` em `sybaseOptions` agora é
  /// preenchido genericamente pelo orchestrator.
  String? _buildRequestedVsExecutedText(
    BuildContext context,
    BackupHistory backup,
  ) {
    final requestedType =
        backup.metrics?.sybaseOptions?['requestedBackupType'] as String?;
    if (requestedType == null ||
        requestedType.isEmpty ||
        requestedType == backup.backupType) {
      return null;
    }
    final requestedDisplay = backupTypeFromString(requestedType).displayName;
    final effectiveDisplay = backupTypeFromString(
      backup.backupType,
    ).displayName;
    return appLocaleString(
      context,
      'Solicitado: $requestedDisplay → Executado: $effectiveDisplay',
      'Requested: $requestedDisplay → Executed: $effectiveDisplay',
    );
  }

  String _buildSybaseDetailsText(BuildContext context, BackupHistory backup) {
    final parts = <String>[];
    final method = backup.metrics?.sybaseOptions?['backupMethod'] as String?;
    if (method != null) {
      parts.add(
        appLocaleString(context, 'Ferramenta: $method', 'Tool: $method'),
      );
    }
    final verify = backup.metrics?.flags.verifyPolicy;
    if (verify != null && verify != 'none') {
      final verifyLabel = _formatVerifyPolicy(context, verify);
      parts.add(
        appLocaleString(
          context,
          'Verificação: $verifyLabel',
          'Verify: $verifyLabel',
        ),
      );
    }
    return parts.join(' • ');
  }

  String _formatVerifyPolicy(BuildContext context, String policy) {
    switch (policy) {
      case 'log_unavailable':
        return appLocaleString(
          context,
          'indisponível (log)',
          'unavailable (log)',
        );
      case 'dbvalid':
        return 'dbvalid';
      case 'dbverify':
        return 'dbverify';
      case 'dbvalid_falhou':
        return appLocaleString(context, 'dbvalid falhou', 'dbvalid failed');
      case 'dbvalid/dbverify':
        return 'dbvalid';
      default:
        return policy;
    }
  }

  Color _getBackupTypeColor(String backupType) {
    final type = backupTypeFromString(backupType);
    switch (type) {
      case BackupType.full:
      case BackupType.fullSingle:
      case BackupType.convertedFullSingle:
        return AppPalette.primary;
      case BackupType.differential:
      case BackupType.convertedDifferential:
        return AppPalette.info;
      case BackupType.log:
      case BackupType.convertedLog:
        return AppPalette.warning;
    }
  }
}
