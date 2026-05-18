import 'package:backup_database/presentation/widgets/atoms/empty_state.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'Message only', type: EmptyState)
Widget buildEmptyStateMessageOnlyUseCase(BuildContext context) {
  return const SizedBox(
    height: 400,
    width: 480,
    child: EmptyState(message: 'Nothing here yet', icon: FluentIcons.inbox),
  );
}

@widgetbook.UseCase(name: 'With action', type: EmptyState)
Widget buildEmptyStateWithActionUseCase(BuildContext context) {
  return const SizedBox(
    height: 400,
    width: 480,
    child: EmptyState(
      message: 'No schedules match your filters',
      icon: FluentIcons.calendar,
      actionLabel: 'Clear filters',
      onAction: _noop,
    ),
  );
}

void _noop() {}
