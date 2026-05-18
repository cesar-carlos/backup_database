import 'package:backup_database/presentation/widgets/atoms/app_button.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'Default', type: AppButton)
Widget buildAppButtonDefaultUseCase(BuildContext context) {
  return AppButton(label: 'Save', onPressed: () {});
}

@widgetbook.UseCase(name: 'Primary', type: AppButton)
Widget buildAppButtonPrimaryUseCase(BuildContext context) {
  return AppButton.primary(label: 'Confirm', onPressed: () {});
}

@widgetbook.UseCase(name: 'Icon', type: AppButton)
Widget buildAppButtonIconUseCase(BuildContext context) {
  return AppButton.icon(
    icon: FluentIcons.save,
    label: 'Save',
    onPressed: () {},
  );
}

@widgetbook.UseCase(name: 'Loading', type: AppButton)
Widget buildAppButtonLoadingUseCase(BuildContext context) {
  return AppButton.loading();
}

@widgetbook.UseCase(name: 'Disabled', type: AppButton)
Widget buildAppButtonDisabledUseCase(BuildContext context) {
  return AppButton(label: 'Disabled', onPressed: null);
}
