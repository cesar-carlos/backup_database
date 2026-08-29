import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_labels.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — local folder path field with a browse action.
class LocalDestinationFields extends StatelessWidget {
  const LocalDestinationFields({
    required this.pathController,
    required this.labelBuilder,
    required this.onSelectFolder,
    super.key,
  });

  final TextEditingController pathController;
  final DestinationDialogLabelBuilder labelBuilder;
  final VoidCallback onSelectFolder;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AppTextField(
            controller: pathController,
            label: labelBuilder('Caminho da pasta', 'Folder path'),
            hint: r'C:\Backups',
            prefixIcon: const Icon(FluentIcons.folder),
            validator: (String? value) {
              if (value == null || value.trim().isEmpty) {
                return labelBuilder(
                  'Caminho é obrigatório',
                  'Path is required',
                );
              }
              return null;
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.lg),
          child: AppIconButton(
            label: labelBuilder('Selecionar pasta', 'Select folder'),
            icon: FluentIcons.folder_open,
            onPressed: onSelectFolder,
          ),
        ),
      ],
    );
  }
}
