import 'package:backup_database/application/providers/providers.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/constants/schedule_dialog_strings.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_section_title.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

class ScheduleDialogScriptTab extends StatelessWidget {
  const ScheduleDialogScriptTab({
    required this.postBackupScriptController,
    super.key,
  });

  final TextEditingController postBackupScriptController;

  @override
  Widget build(BuildContext context) {
    return Consumer<LicenseProvider>(
      builder: (BuildContext context, LicenseProvider licenseProvider, _) {
        final license = licenseProvider.currentLicense;
        final hasPostScript =
            licenseProvider.hasValidLicense &&
            (license?.hasFeature(LicenseFeatures.postBackupScript) ?? false);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ScheduleDialogSectionTitle(
                ScheduleDialogStrings.scriptTabTitle,
              ),
              const SizedBox(height: 16),
              if (!hasPostScript) ...[
                const InfoBar(
                  severity: InfoBarSeverity.warning,
                  title: Text(
                    ScheduleDialogStrings.scriptLicenseBlockedTitle,
                  ),
                  content: Text(
                    ScheduleDialogStrings.scriptLicenseBlockedMessage,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              InfoLabel(
                label: ScheduleDialogStrings.scriptFieldLabel,
                child: TextBox(
                  controller: postBackupScriptController,
                  placeholder: ScheduleDialogStrings.scriptFieldPlaceholder,
                  maxLines: 15,
                  minLines: 10,
                  readOnly: !hasPostScript,
                ),
              ),
              const SizedBox(height: 16),
              const InfoBar(
                title: Text(
                  ScheduleDialogStrings.scriptInfoTitle,
                ),
                content: Text(
                  ScheduleDialogStrings.scriptInfoMessage,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
