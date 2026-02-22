import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

class RecentBackupsList extends StatelessWidget {
  const RecentBackupsList({required this.backups, super.key});
  final List<BackupHistory> backups;

  String _t(BuildContext context, String pt, String en) {
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
    return isPt ? pt : en;
  }

  @override
  Widget build(BuildContext context) {
    if (backups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_t(context, 'Nenhum backup recente', 'No recent backup')),
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
        return AppColors.backupSuccess;
      case BackupStatus.error:
        return AppColors.backupError;
      case BackupStatus.warning:
        return AppColors.backupWarning;
      case BackupStatus.running:
        return AppColors.backupRunning;
    }
  }

  String _getStatusText(BuildContext context, BackupStatus status) {
    switch (status) {
      case BackupStatus.success:
        return _t(context, 'Sucesso', 'Success');
      case BackupStatus.error:
        return _t(context, 'Erro', 'Error');
      case BackupStatus.warning:
        return _t(context, 'Aviso', 'Warning');
      case BackupStatus.running:
        return _t(context, 'Em progresso', 'In progress');
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

  Color _getBackupTypeColor(String backupType) {
    final type = backupTypeFromString(backupType);
    switch (type) {
      case BackupType.full:
      case BackupType.fullSingle:
      case BackupType.convertedFullSingle:
        return AppColors.primary;
      case BackupType.differential:
      case BackupType.convertedDifferential:
        return Colors.blue;
      case BackupType.log:
      case BackupType.convertedLog:
        return Colors.orange;
    }
  }
}
