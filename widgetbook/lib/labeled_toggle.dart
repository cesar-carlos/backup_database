import 'package:backup_database/presentation/widgets/molecules/labeled_toggle.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'On', type: LabeledToggle)
Widget buildLabeledToggleOnUseCase(BuildContext context) {
  return const SizedBox(
    width: 420,
    child: LabeledToggle(
      title: 'Enabled',
      description: 'Include this destination in backups',
      value: true,
    ),
  );
}

@widgetbook.UseCase(name: 'Off', type: LabeledToggle)
Widget buildLabeledToggleOffUseCase(BuildContext context) {
  return const SizedBox(
    width: 420,
    child: LabeledToggle(title: 'Create subfolders by date', value: false),
  );
}

@widgetbook.UseCase(name: 'Disabled', type: LabeledToggle)
Widget buildLabeledToggleDisabledUseCase(BuildContext context) {
  return const SizedBox(
    width: 420,
    child: LabeledToggle(
      title: 'Cloud destination',
      value: false,
      disabledReason: 'Requires a license',
    ),
  );
}
