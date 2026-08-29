import 'package:backup_database/core/theme/tokens/app_palette.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/presentation/widgets/atoms/app_status_chip.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Atom** — compact badge for [DestinationType] identity.
class DestinationTypeBadge extends StatelessWidget {
  const DestinationTypeBadge({required this.type, super.key});

  final DestinationType type;

  static Color colorOf(DestinationType type) {
    return switch (type) {
      DestinationType.local => AppPalette.destinationLocal,
      DestinationType.ftp => AppPalette.destinationFtp,
      DestinationType.googleDrive => AppPalette.destinationGoogleDrive,
      DestinationType.dropbox => AppPalette.destinationDropbox,
      DestinationType.nextcloud => AppPalette.destinationNextcloud,
    };
  }

  static IconData iconOf(DestinationType type) {
    return switch (type) {
      DestinationType.local => FluentIcons.folder,
      DestinationType.ftp => FluentIcons.cloud_upload,
      DestinationType.googleDrive => FluentIcons.cloud,
      DestinationType.dropbox => FluentIcons.cloud,
      DestinationType.nextcloud => FluentIcons.cloud,
    };
  }

  String get _label {
    switch (type) {
      case DestinationType.local:
        return 'LOCAL';
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

  @override
  Widget build(BuildContext context) {
    return AppStatusChip(
      label: _label,
      color: colorOf(type),
    );
  }
}
