import 'dart:async';

import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

class ScheduleDialogDestinationSelector extends StatelessWidget {
  const ScheduleDialogDestinationSelector({
    required this.destinations,
    required this.selectedDestinationIds,
    required this.onDestinationToggled,
    super.key,
  });

  final List<BackupDestination> destinations;
  final List<String> selectedDestinationIds;
  final void Function(String destinationId, bool selected) onDestinationToggled;

  @override
  Widget build(BuildContext context) {
    if (destinations.isEmpty) {
      return const _EmptyDestinationsWarning();
    }

    return _LicensedDestinationList(
      destinations: destinations,
      selectedDestinationIds: selectedDestinationIds,
      onDestinationToggled: onDestinationToggled,
    );
  }
}

class _EmptyDestinationsWarning extends StatelessWidget {
  const _EmptyDestinationsWarning();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(FluentIcons.warning, color: colors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Nenhum destino configurado. Configure um destino primeiro.',
              style: FluentTheme.of(
                context,
              ).typography.caption?.copyWith(color: colors.danger),
            ),
          ),
        ],
      ),
    );
  }
}

class _LicensedDestinationList extends StatelessWidget {
  const _LicensedDestinationList({
    required this.destinations,
    required this.selectedDestinationIds,
    required this.onDestinationToggled,
  });

  final List<BackupDestination> destinations;
  final List<String> selectedDestinationIds;
  final void Function(String destinationId, bool selected) onDestinationToggled;

  @override
  Widget build(BuildContext context) {
    return Consumer<LicenseProvider>(
      builder: (BuildContext context, LicenseProvider licenseProvider, _) {
        final hasGoogleDrive = licenseProvider.isFeatureUnlocked(
          LicenseFeatures.googleDrive,
        );
        final hasDropbox = licenseProvider.isFeatureUnlocked(
          LicenseFeatures.dropbox,
        );
        final hasNextcloud = licenseProvider.isFeatureUnlocked(
          LicenseFeatures.nextcloud,
        );

        bool isBlocked(DestinationType type) {
          if (type == DestinationType.googleDrive) return !hasGoogleDrive;
          if (type == DestinationType.dropbox) return !hasDropbox;
          if (type == DestinationType.nextcloud) return !hasNextcloud;
          return false;
        }

        return Column(
          children: destinations.map((BackupDestination destination) {
            return _DestinationRow(
              destination: destination,
              selected: selectedDestinationIds.contains(destination.id),
              blocked: isBlocked(destination.type),
              onToggled: onDestinationToggled,
            );
          }).toList(),
        );
      },
    );
  }
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.destination,
    required this.selected,
    required this.blocked,
    required this.onToggled,
  });

  final BackupDestination destination;
  final bool selected;
  final bool blocked;
  final void Function(String destinationId, bool selected) onToggled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(_destinationIcon(destination.type), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  destination.name,
                  style: FluentTheme.of(context).typography.body,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        blocked
                            ? '${_destinationTypeName(destination.type)} '
                                  '(Requer licença)'
                            : _destinationTypeName(destination.type),
                        style: FluentTheme.of(context).typography.caption
                            ?.copyWith(
                              color: blocked
                                  ? FluentTheme.of(context)
                                        .resources
                                        .controlStrokeColorDefault
                                        .withValues(alpha: 0.6)
                                  : null,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (blocked) ...[
                      const SizedBox(width: 8),
                      Icon(
                        FluentIcons.lock,
                        size: 14,
                        color: FluentTheme.of(context)
                            .resources
                            .controlStrokeColorDefault
                            .withValues(alpha: 0.6),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Checkbox(
            checked: selected,
            onChanged: (bool? value) {
              if ((value ?? false) && blocked) {
                unawaited(
                  FluentInfoBarFeedback.showWarning(
                    context,
                    message:
                        'Este destino requer uma licença válida. '
                        'Acesse Configurações > Licenciamento para mais '
                        'informações.',
                  ),
                );
                return;
              }
              onToggled(destination.id, value ?? false);
            },
          ),
        ],
      ),
    );
  }
}

String _destinationTypeName(DestinationType type) {
  switch (type) {
    case DestinationType.local:
      return 'Pasta Local';
    case DestinationType.ftp:
      return 'Servidor FTP';
    case DestinationType.googleDrive:
      return 'Google Drive';
    case DestinationType.dropbox:
      return 'Dropbox';
    case DestinationType.nextcloud:
      return 'Nextcloud';
  }
}

IconData _destinationIcon(DestinationType type) {
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
