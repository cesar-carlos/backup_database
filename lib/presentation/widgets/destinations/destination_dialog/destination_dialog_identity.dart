import 'dart:async';

import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_labels.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_type_meta.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

/// **Molecule** — destination type selector, name, and license banner.
class DestinationDialogIdentitySection extends StatelessWidget {
  const DestinationDialogIdentitySection({
    required this.selectedType,
    required this.isEditing,
    required this.nameController,
    required this.labelBuilder,
    required this.onTypeChanged,
    super.key,
  });

  final DestinationType selectedType;
  final bool isEditing;
  final TextEditingController nameController;
  final DestinationDialogLabelBuilder labelBuilder;
  final ValueChanged<DestinationType> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionCard(
          title: labelBuilder('Identificação', 'Identity'),
          description: labelBuilder(
            'Defina o tipo e o nome usados para identificar este destino na operação.',
            'Define the type and display name used to identify this destination in operations.',
          ),
          trailing: DestinationTypeBadge(type: selectedType),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DestinationTypeSelector(
                selectedType: selectedType,
                isEditing: isEditing,
                labelBuilder: labelBuilder,
                onTypeChanged: onTypeChanged,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: nameController,
                label: labelBuilder('Nome do destino', 'Destination name'),
                hint: labelBuilder(
                  'Ex: Backup local, FTP servidor, Google Drive, Dropbox',
                  'Ex: Local backup, FTP server, Google Drive, Dropbox',
                ),
                prefixIcon: const Icon(FluentIcons.tag),
                validator: (String? value) {
                  if (value == null || value.trim().isEmpty) {
                    return labelBuilder(
                      'Nome é obrigatório',
                      'Name is required',
                    );
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _DestinationLicenseBanner(
          selectedType: selectedType,
          labelBuilder: labelBuilder,
        ),
      ],
    );
  }
}

class _DestinationLicenseBanner extends StatelessWidget {
  const _DestinationLicenseBanner({
    required this.selectedType,
    required this.labelBuilder,
  });

  final DestinationType selectedType;
  final DestinationDialogLabelBuilder labelBuilder;

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

        final isGoogleDriveBlocked =
            selectedType == DestinationType.googleDrive && !hasGoogleDrive;
        final isDropboxBlocked =
            selectedType == DestinationType.dropbox && !hasDropbox;
        final isNextcloudBlocked =
            selectedType == DestinationType.nextcloud && !hasNextcloud;

        if (isGoogleDriveBlocked || isDropboxBlocked || isNextcloudBlocked) {
          return AppCallout(
            tone: AppCalloutTone.warning,
            message: labelBuilder(
              'Recursos premium inativos. Este destino permanece salvo, '
                  'mas não executa até ativar uma licença premium. '
                  'Acesse Configurações > Licenciamento.',
              'Premium features inactive. This destination stays saved, '
                  'but will not run until a premium license is activated. '
                  'Go to Settings > Licensing.',
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}

class _DestinationTypeSelector extends StatelessWidget {
  const _DestinationTypeSelector({
    required this.selectedType,
    required this.isEditing,
    required this.labelBuilder,
    required this.onTypeChanged,
  });

  final DestinationType selectedType;
  final bool isEditing;
  final DestinationDialogLabelBuilder labelBuilder;
  final ValueChanged<DestinationType> onTypeChanged;

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

        return AppDropdown<DestinationType>(
          label: labelBuilder('Tipo de destino', 'Destination type'),
          value: selectedType,
          placeholder: Text(
            labelBuilder('Tipo de destino', 'Destination type'),
          ),
          items: DestinationType.values.map((DestinationType type) {
            final isGoogleDriveBlocked =
                type == DestinationType.googleDrive && !hasGoogleDrive;
            final isDropboxBlocked =
                type == DestinationType.dropbox && !hasDropbox;
            final isNextcloudBlocked =
                type == DestinationType.nextcloud && !hasNextcloud;
            final isBlocked =
                isGoogleDriveBlocked || isDropboxBlocked || isNextcloudBlocked;
            final blockedColor = isBlocked
                ? FluentTheme.of(context).resources.controlStrokeColorDefault
                      .withValues(alpha: 0.4)
                : null;

            return ComboBoxItem<DestinationType>(
              value: type,
              enabled: !isBlocked,
              child: Row(
                children: [
                  Icon(
                    DestinationDialogTypeMeta.iconOf(type),
                    size: 20,
                    color: blockedColor,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            isBlocked
                                ? '${DestinationDialogTypeMeta.nameOf(type, labelBuilder)} (${labelBuilder('Requer licença', 'License required')})'
                                : DestinationDialogTypeMeta.nameOf(
                                    type,
                                    labelBuilder,
                                  ),
                            textAlign: TextAlign.start,
                            style: TextStyle(color: blockedColor),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isBlocked) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Icon(
                            FluentIcons.lock,
                            size: 16,
                            color: blockedColor,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: isEditing
              ? null
              : (DestinationType? value) {
                  if (value == null) {
                    return;
                  }
                  final isGoogleDriveBlocked =
                      value == DestinationType.googleDrive && !hasGoogleDrive;
                  final isDropboxBlocked =
                      value == DestinationType.dropbox && !hasDropbox;
                  final isNextcloudBlocked =
                      value == DestinationType.nextcloud && !hasNextcloud;

                  if (isGoogleDriveBlocked ||
                      isDropboxBlocked ||
                      isNextcloudBlocked) {
                    unawaited(
                      FluentInfoBarFeedback.showWarning(
                        context,
                        message: labelBuilder(
                          'Este destino requer uma licença válida. Acesse Configurações > Licenciamento para mais informações.',
                          'This destination requires a valid license. Go to Settings > Licensing for more information.',
                        ),
                      ),
                    );
                    return;
                  }

                  onTypeChanged(value);
                },
        );
      },
    );
  }
}
