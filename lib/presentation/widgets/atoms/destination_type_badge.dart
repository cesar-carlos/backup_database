import 'package:backup_database/core/theme/tokens/app_palette.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/presentation/widgets/atoms/app_status_chip.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Atom** — compact badge for [DestinationType] identity.
class DestinationTypeBadge extends StatelessWidget {
  const DestinationTypeBadge({required this.type, super.key});

  final DestinationType type;

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

  Color get _color {
    switch (type) {
      case DestinationType.local:
        return AppPalette.destinationLocal;
      case DestinationType.ftp:
        return AppPalette.destinationFtp;
      case DestinationType.googleDrive:
        return AppPalette.destinationGoogleDrive;
      case DestinationType.dropbox:
        return AppPalette.destinationDropbox;
      case DestinationType.nextcloud:
        return AppPalette.destinationNextcloud;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppStatusChip(
      label: _label,
      color: _color,
    );
  }
}
