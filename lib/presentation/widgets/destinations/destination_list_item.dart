import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/backup_destination.dart';

class DestinationListItem extends StatelessWidget {
  final BackupDestination destination;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onToggleEnabled;

  const DestinationListItem({
    super.key,
    required this.destination,
    this.onEdit,
    this.onDelete,
    this.onToggleEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: destination.enabled
              ? _getTypeColor(destination.type).withValues(alpha: 0.2)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Icon(
            _getTypeIcon(destination.type),
            color: destination.enabled
                ? _getTypeColor(destination.type)
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          destination.name,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getTypeColor(destination.type).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _getTypeName(destination.type),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _getTypeColor(destination.type),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _getConfigSummary(destination),
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: destination.enabled,
              onChanged: onToggleEnabled,
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEdit?.call();
                    break;
                  case 'delete':
                    onDelete?.call();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('Editar'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 20, color: AppColors.delete),
                      SizedBox(width: 8),
                      Text('Excluir', style: TextStyle(color: AppColors.delete)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  IconData _getTypeIcon(DestinationType type) {
    switch (type) {
      case DestinationType.local:
        return Icons.folder_outlined;
      case DestinationType.ftp:
        return Icons.cloud_upload_outlined;
      case DestinationType.googleDrive:
        return Icons.add_to_drive_outlined;
    }
  }

  Color _getTypeColor(DestinationType type) {
    switch (type) {
      case DestinationType.local:
        return AppColors.destinationLocal;
      case DestinationType.ftp:
        return AppColors.destinationFtp;
      case DestinationType.googleDrive:
        return AppColors.destinationGoogleDrive;
    }
  }

  String _getTypeName(DestinationType type) {
    switch (type) {
      case DestinationType.local:
        return 'Local';
      case DestinationType.ftp:
        return 'FTP';
      case DestinationType.googleDrive:
        return 'Google Drive';
    }
  }

  String _getConfigSummary(BackupDestination destination) {
    try {
      final config = destination.config;
      switch (destination.type) {
        case DestinationType.local:
          final path = RegExp(r'"path"\s*:\s*"([^"]*)"').firstMatch(config)?.group(1) ?? '';
          return path;
        case DestinationType.ftp:
          final host = RegExp(r'"host"\s*:\s*"([^"]*)"').firstMatch(config)?.group(1) ?? '';
          final remotePath = RegExp(r'"remotePath"\s*:\s*"([^"]*)"').firstMatch(config)?.group(1) ?? '';
          return '$host:$remotePath';
        case DestinationType.googleDrive:
          final folderName = RegExp(r'"folderName"\s*:\s*"([^"]*)"').firstMatch(config)?.group(1) ?? '';
          return 'Pasta: $folderName';
      }
    } catch (e) {
      return '';
    }
  }
}

