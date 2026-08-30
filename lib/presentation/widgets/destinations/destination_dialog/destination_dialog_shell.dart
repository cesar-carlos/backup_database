import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_behavior.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_identity.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_labels.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_type_meta.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Atom** — destination dialog title with type icon.
class DestinationDialogTitle extends StatelessWidget {
  const DestinationDialogTitle({
    required this.selectedType,
    required this.isEditing,
    required this.labelBuilder,
    super.key,
  });

  final DestinationType selectedType;
  final bool isEditing;
  final DestinationDialogLabelBuilder labelBuilder;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          DestinationDialogTypeMeta.iconOf(selectedType),
          color: DestinationDialogTypeMeta.colorOf(selectedType),
        ),
        const SizedBox(width: 12),
        Text(
          isEditing
              ? labelBuilder('Editar destino', 'Edit destination')
              : labelBuilder('Novo destino', 'New destination'),
          style: FluentTheme.of(context).typography.title,
        ),
      ],
    );
  }
}

/// **Organism** — identity, type-specific fields and behavior sections.
class DestinationDialogContent extends StatelessWidget {
  const DestinationDialogContent({
    required this.formKey,
    required this.selectedType,
    required this.isEditing,
    required this.nameController,
    required this.labelBuilder,
    required this.onTypeChanged,
    required this.typeSpecificFields,
    required this.retentionDaysController,
    required this.createSubfoldersByDate,
    required this.isEnabled,
    required this.onCreateSubfoldersByDateChanged,
    required this.onEnabledChanged,
    super.key,
    this.ftpExtraSection,
  });

  final GlobalKey<FormState> formKey;
  final DestinationType selectedType;
  final bool isEditing;
  final TextEditingController nameController;
  final DestinationDialogLabelBuilder labelBuilder;
  final ValueChanged<DestinationType> onTypeChanged;
  final Widget typeSpecificFields;
  final Widget? ftpExtraSection;
  final TextEditingController retentionDaysController;
  final bool createSubfoldersByDate;
  final bool isEnabled;
  final ValueChanged<bool> onCreateSubfoldersByDateChanged;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DestinationDialogIdentitySection(
            selectedType: selectedType,
            isEditing: isEditing,
            nameController: nameController,
            labelBuilder: labelBuilder,
            onTypeChanged: onTypeChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          AppSectionCard(
            title: DestinationDialogTypeMeta.sectionTitle(
              selectedType,
              labelBuilder,
            ),
            description: DestinationDialogTypeMeta.sectionDescription(
              selectedType,
              labelBuilder,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                typeSpecificFields,
                if (ftpExtraSection != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  ftpExtraSection!,
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          DestinationDialogBehaviorSection(
            selectedType: selectedType,
            retentionDaysController: retentionDaysController,
            createSubfoldersByDate: createSubfoldersByDate,
            isEnabled: isEnabled,
            labelBuilder: labelBuilder,
            onCreateSubfoldersByDateChanged: onCreateSubfoldersByDateChanged,
            onEnabledChanged: onEnabledChanged,
          ),
        ],
      ),
    );
  }
}
