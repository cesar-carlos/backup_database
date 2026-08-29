import 'package:backup_database/presentation/widgets/atoms/app_icon_button.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'Default', type: AppIconButton)
Widget buildAppIconButtonDefaultUseCase(BuildContext context) {
  return AppIconButton(
    label: 'Refresh',
    icon: FluentIcons.refresh,
    onPressed: () {},
  );
}

@widgetbook.UseCase(name: 'Disabled', type: AppIconButton)
Widget buildAppIconButtonDisabledUseCase(BuildContext context) {
  return const AppIconButton(label: 'Refresh', icon: FluentIcons.refresh);
}
