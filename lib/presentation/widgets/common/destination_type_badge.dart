import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:fluent_ui/fluent_ui.dart';

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

  Color _color(FluentThemeData theme) {
    switch (type) {
      case DestinationType.local:
        return theme.resources.systemFillColorSuccessBackground;
      case DestinationType.ftp:
        return const Color(0xFF0066CC);
      case DestinationType.googleDrive:
        return const Color(0xFF4285F4);
      case DestinationType.dropbox:
        return const Color(0xFF0061FF);
      case DestinationType.nextcloud:
        return const Color(0xFF0082C9);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color(theme).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _color(theme),
        ),
      ),
      child: Text(
        _label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: _color(theme),
        ),
      ),
    );
  }
}
