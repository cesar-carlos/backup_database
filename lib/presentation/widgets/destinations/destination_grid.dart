import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

class DestinationGrid extends StatelessWidget {
  const DestinationGrid({
    required this.destinations,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleEnabled,
    super.key,
  });

  final List<BackupDestination> destinations;
  final ValueChanged<BackupDestination> onEdit;
  final ValueChanged<String> onDelete;
  final void Function(BackupDestination destination, bool enabled)
  onToggleEnabled;

  String _t(BuildContext context, String pt, String en) {
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
    return isPt ? pt : en;
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: AppDataGrid<BackupDestination>(
        minWidth: 1080,
        columns: [
          AppDataGridColumn<BackupDestination>(
            label: _t(context, 'Destino', 'Destination'),
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
            label: _t(context, 'Tipo', 'Type'),
            width: const FlexColumnWidth(1.4),
            cellBuilder: (context, row) => _TypeChip(
              label: _getTypeName(context, row.type),
              color: _getTypeColor(row.type),
            ),
          ),
          AppDataGridColumn<BackupDestination>(
            label: _t(context, 'Configuracao', 'Configuration'),
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
            label: _t(context, 'Status', 'Status'),
            width: const FlexColumnWidth(1.2),
            cellBuilder: (context, row) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ToggleSwitch(
                  checked: row.enabled,
                  onChanged: (enabled) => onToggleEnabled(row, enabled),
                ),
                const SizedBox(width: 8),
                Text(
                  row.enabled
                      ? _t(context, 'Ativo', 'Active')
                      : _t(context, 'Inativo', 'Inactive'),
                ),
              ],
            ),
          ),
        ],
        actions: [
          AppDataGridAction<BackupDestination>(
            icon: FluentIcons.edit,
            tooltip: _t(context, 'Editar', 'Edit'),
            onPressed: onEdit,
          ),
          AppDataGridAction<BackupDestination>(
            icon: FluentIcons.delete,
            iconColor: AppColors.error,
            tooltip: _t(context, 'Excluir', 'Delete'),
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
        return _t(context, 'Local', 'Local');
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
          return '${_t(context, 'Pasta', 'Folder')}: $folderName';
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
            return '${_t(context, 'Pasta', 'Folder')}: /$folderName';
          }
          return '${_t(context, 'Pasta', 'Folder')}: $folderPath/$folderName';
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

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: FluentTheme.of(context).typography.caption?.copyWith(
          color: color,
        ),
      ),
    );
  }
}
