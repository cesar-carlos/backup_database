import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

class DestinationGrid extends StatelessWidget {
  const DestinationGrid({
    required this.destinations,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onToggleEnabled,
    super.key,
  });

  final List<BackupDestination> destinations;
  final ValueChanged<BackupDestination> onEdit;
  final ValueChanged<BackupDestination> onDuplicate;
  final ValueChanged<String> onDelete;
  final void Function(BackupDestination destination, bool enabled)
  onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: AppDataGrid<BackupDestination>(
        minWidth: 900,
        columns: [
          AppDataGridColumn<BackupDestination>(
            label: appLocaleString(context, 'Destino', 'Destination'),
            width: const FlexColumnWidth(2),
            cellBuilder: (context, row) => Row(
              children: [
                Icon(
                  _getTypeIcon(row.type),
                  size: 18,
                  color: _getTypeColor(row.type),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    row.name,
                    overflow: TextOverflow.ellipsis,
                    style: FluentTheme.of(context).typography.bodyStrong,
                  ),
                ),
              ],
            ),
          ),
          AppDataGridColumn<BackupDestination>(
            label: appLocaleString(context, 'Tipo', 'Type'),
            width: const FlexColumnWidth(0.95),
            cellBuilder: (context, row) => AppStatusChip(
              label: _getTypeName(context, row.type),
              color: _getTypeColor(row.type),
            ),
          ),
          AppDataGridColumn<BackupDestination>(
            label: appLocaleString(context, 'Configuração', 'Configuration'),
            width: const FlexColumnWidth(3),
            cellBuilder: (context, row) => Tooltip(
              message: _getConfigSummary(context, row),
              child: Text(
                _getConfigSummary(context, row),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          AppDataGridColumn<BackupDestination>(
            label: appLocaleString(context, 'Status', 'Status'),
            width: const FlexColumnWidth(1.2),
            cellBuilder: (context, row) => Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ToggleSwitch(
                  checked: row.enabled,
                  onChanged: (enabled) => onToggleEnabled(row, enabled),
                ),
                Text(
                  row.enabled
                      ? appLocaleString(context, 'Ativo', 'Active')
                      : appLocaleString(context, 'Inativo', 'Inactive'),
                ),
              ],
            ),
          ),
        ],
        actions: [
          AppDataGridAction<BackupDestination>(
            icon: FluentIcons.edit,
            tooltip: appLocaleString(context, 'Editar', 'Edit'),
            onPressed: onEdit,
          ),
          AppDataGridAction<BackupDestination>(
            icon: FluentIcons.copy,
            tooltip: appLocaleString(context, 'Duplicar', 'Duplicate'),
            onPressed: onDuplicate,
          ),
          AppDataGridAction<BackupDestination>(
            icon: FluentIcons.delete,
            iconColor: AppColors.error,
            tooltip: appLocaleString(context, 'Excluir', 'Delete'),
            onPressed: (row) => onDelete(row.id),
          ),
        ],
        rows: destinations,
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

  String _getTypeName(BuildContext context, DestinationType type) {
    switch (type) {
      case DestinationType.local:
        return appLocaleString(context, 'Local', 'Local');
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

  String _getConfigSummary(
    BuildContext context,
    BackupDestination destination,
  ) {
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
          return '${appLocaleString(context, 'Pasta', 'Folder')}: $folderName';
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
            return '${appLocaleString(context, 'Pasta', 'Folder')}: /$folderName';
          }
          return '${appLocaleString(context, 'Pasta', 'Folder')}: $folderPath/$folderName';
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
            return fullPath;
          }
          if (fullPath.isEmpty) {
            return serverUrl;
          }
          return '$serverUrl $fullPath';
      }
    } on Object {
      return '';
    }
  }
}
