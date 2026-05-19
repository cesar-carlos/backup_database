import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'Empty', type: AppPageState)
Widget buildAppPageStateEmptyUseCase(BuildContext context) {
  return AppPageState.empty(
    title: 'No schedules configured',
    message: 'Create your first automation to start running backups.',
    actionLabel: 'Create schedule',
    onAction: () {},
  );
}

@widgetbook.UseCase(name: 'Error', type: AppPageState)
Widget buildAppPageStateErrorUseCase(BuildContext context) {
  return AppPageState.error(
    title: 'Could not load destinations',
    message: 'The server did not respond in time.',
    actionLabel: 'Retry',
    onAction: () {},
  );
}
