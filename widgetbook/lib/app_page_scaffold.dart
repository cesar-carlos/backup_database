import 'package:backup_database/presentation/widgets/organisms/app_page_scaffold.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'Default', type: AppPageScaffold)
Widget buildAppPageScaffoldDefaultUseCase(BuildContext context) {
  return AppPageScaffold(
    title: 'Schedules',
    actions: const [
      AppPageAction(label: 'Refresh', icon: FluentIcons.refresh),
      AppPageAction(
        label: 'New schedule',
        icon: FluentIcons.add,
        isPrimary: true,
      ),
    ],
    body: const Center(child: Text('Page body content')),
  );
}

@widgetbook.UseCase(name: 'With header message', type: AppPageScaffold)
Widget buildAppPageScaffoldWithBannerUseCase(BuildContext context) {
  return AppPageScaffold(
    title: 'Windows Service',
    headerBottom: const InfoBar(
      title: Text('Compatibility'),
      content: Text('Feature is available and ready to configure.'),
    ),
    body: const Center(child: Text('Service content')),
  );
}
