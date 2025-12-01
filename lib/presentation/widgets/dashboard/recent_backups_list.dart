import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/backup_history.dart';

class RecentBackupsList extends StatelessWidget {
  final List<BackupHistory> backups;

  const RecentBackupsList({super.key, required this.backups});

  @override
  Widget build(BuildContext context) {
    if (backups.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Nenhum backup recente'),
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
          subtitle: Text(
            DateFormat('dd/MM/yyyy HH:mm').format(backup.startedAt),
          ),
          trailing: Text(
            _getStatusText(backup.status),
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
        return Icons.check_circle;
      case BackupStatus.error:
        return Icons.error;
      case BackupStatus.warning:
        return Icons.warning;
      case BackupStatus.running:
        return Icons.sync;
    }
  }

  Color _getStatusColor(BackupStatus status) {
    switch (status) {
      case BackupStatus.success:
        return Colors.green;
      case BackupStatus.error:
        return Colors.red;
      case BackupStatus.warning:
        return Colors.orange;
      case BackupStatus.running:
        return Colors.blue;
    }
  }

  String _getStatusText(BackupStatus status) {
    switch (status) {
      case BackupStatus.success:
        return 'Sucesso';
      case BackupStatus.error:
        return 'Erro';
      case BackupStatus.warning:
        return 'Aviso';
      case BackupStatus.running:
        return 'Em progresso';
    }
  }
}

