import 'package:backup_database/core/constants/schedule_dialog_strings.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_section_title.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ScheduleDialogDestinationsAndFolderSection extends StatelessWidget {
  const ScheduleDialogDestinationsAndFolderSection({
    required this.destinationSelector,
    required this.backupFolderController,
    required this.onSelectBackupFolderPressed,
    super.key,
  });

  final Widget destinationSelector;
  final TextEditingController backupFolderController;
  final VoidCallback onSelectBackupFolderPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScheduleDialogSectionTitle(ScheduleDialogStrings.destinations),
        const SizedBox(height: 12),
        destinationSelector,
        const SizedBox(height: 24),
        const ScheduleDialogSectionTitle(
          ScheduleDialogStrings.backupFolderSection,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                controller: backupFolderController,
                label: ScheduleDialogStrings.backupFolderLabel,
                hint: ScheduleDialogStrings.backupFolderHint,
                prefixIcon: const Icon(FluentIcons.folder),
                validator: (String? value) {
                  if (value == null || value.trim().isEmpty) {
                    return ScheduleDialogStrings.backupFolderRequired;
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: IconButton(
                icon: const Icon(FluentIcons.folder_open),
                onPressed: onSelectBackupFolderPressed,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          ScheduleDialogStrings.backupFolderDescription,
          style: FluentTheme.of(context).typography.caption,
        ),
      ],
    );
  }
}
