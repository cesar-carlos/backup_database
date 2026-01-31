import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/presentation/widgets/common/config_list_item.dart';
import 'package:fluent_ui/fluent_ui.dart';

class DestinationListItem extends StatelessWidget {
  const DestinationListItem({
    required this.destination,
    super.key,
    this.onEdit,
    this.onDelete,
    this.onToggleEnabled,
  });
  final BackupDestination destination;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    return ConfigListItem(
      name: destination.name,
      icon: _getTypeIcon(destination.type),
      iconColor: _getTypeColor(destination.type),
      enabled: destination.enabled,
      onToggleEnabled: onToggleEnabled,
      onEdit: onEdit,
      onDelete: onDelete,
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
                  style: FluentTheme.of(context).typography.caption?.copyWith(
                    color: _getTypeColor(destination.type),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _getConfigSummary(destination),
            style: FluentTheme.of(context).typography.body,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  IconData _getTypeIcon(DestinationType type) {
    switch (type) {
      case DestinationType.local:
        return FluentIcons.folder;
      case DestinationType.ftp:
        return FluentIcons.cloud_upload;
      case DestinationType.googleDrive:
        return FluentIcons.cloud;
      case DestinationType.dropbox:
        return FluentIcons.cloud;
      case DestinationType.nextcloud:
        return FluentIcons.cloud;
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
      case DestinationType.dropbox:
        return AppColors.destinationDropbox;
      case DestinationType.nextcloud:
        return AppColors.destinationNextcloud;
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
      case DestinationType.dropbox:
        return 'Dropbox';
      case DestinationType.nextcloud:
        return 'Nextcloud';
    }
  }

  String _getConfigSummary(BackupDestination destination) {
    try {
      final config = destination.config;
      switch (destination.type) {
        case DestinationType.local:
          final path =
              RegExp(r'"path"\s*:\s*"([^"]*)"').firstMatch(config)?.group(1) ??
              '';
          return path;
        case DestinationType.ftp:
          final host =
              RegExp(r'"host"\s*:\s*"([^"]*)"').firstMatch(config)?.group(1) ??
              '';
          final remotePath =
              RegExp(
                r'"remotePath"\s*:\s*"([^"]*)"',
              ).firstMatch(config)?.group(1) ??
              '';
          return '$host:$remotePath';
        case DestinationType.googleDrive:
          final folderName =
              RegExp(
                r'"folderName"\s*:\s*"([^"]*)"',
              ).firstMatch(config)?.group(1) ??
              '';
          return 'Pasta: $folderName';
        case DestinationType.dropbox:
          final folderPath =
              RegExp(
                r'"folderPath"\s*:\s*"([^"]*)"',
              ).firstMatch(config)?.group(1) ??
              '';
          final folderName =
              RegExp(
                r'"folderName"\s*:\s*"([^"]*)"',
              ).firstMatch(config)?.group(1) ??
              '';
          if (folderPath.isEmpty) {
            return 'Pasta: /$folderName';
          }
          return 'Pasta: $folderPath/$folderName';
        case DestinationType.nextcloud:
          final serverUrl =
              RegExp(
                r'"serverUrl"\s*:\s*"([^"]*)"',
              ).firstMatch(config)?.group(1) ??
              '';
          final remotePath =
              RegExp(
                r'"remotePath"\s*:\s*"([^"]*)"',
              ).firstMatch(config)?.group(1) ??
              '';
          final folderName =
              RegExp(
                r'"folderName"\s*:\s*"([^"]*)"',
              ).firstMatch(config)?.group(1) ??
              '';

          final folderSummary = folderName.isEmpty ? '' : '/$folderName';
          final pathSummary = remotePath.isEmpty ? '' : remotePath;
          final fullPath = '$pathSummary$folderSummary';

          if (serverUrl.isEmpty) {
            return fullPath.isEmpty ? '' : fullPath;
          }
          if (fullPath.isEmpty) {
            return serverUrl;
          }
          return '$serverUrl $fullPath';
      }
    } on Object catch (e) {
      return '';
    }
  }
}
