import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/presentation/widgets/atoms/destination_type_badge.dart';
import 'package:backup_database/presentation/widgets/molecules/config_list_item.dart';
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
      icon: DestinationTypeBadge.iconOf(destination.type),
      iconColor: DestinationTypeBadge.colorOf(destination.type),
      enabled: destination.enabled,
      onToggleEnabled: onToggleEnabled,
      onEdit: onEdit,
      onDelete: onDelete,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.xs),
          DestinationTypeBadge(type: destination.type),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _getConfigSummary(context, destination),
            style: FluentTheme.of(context).typography.body,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
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
            return fullPath.isEmpty ? '' : fullPath;
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
