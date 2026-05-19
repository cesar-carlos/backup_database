import 'package:backup_database/presentation/widgets/organisms/app_section_card.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'Default', type: AppSectionCard)
Widget buildAppSectionCardDefaultUseCase(BuildContext context) {
  return const AppSectionCard(
    title: 'Auto update',
    description: 'Track update readiness, last result and operational paths.',
    child: Text('Operational section content'),
  );
}

@widgetbook.UseCase(name: 'With banner and footer', type: AppSectionCard)
Widget buildAppSectionCardFullUseCase(BuildContext context) {
  return AppSectionCard(
    title: 'Windows Service',
    description: 'Control service lifecycle and inspect the current status.',
    banner: const InfoBar(
      title: Text('UAC'),
      content: Text('Administrator confirmation is required.'),
      severity: InfoBarSeverity.warning,
    ),
    footer: Align(
      alignment: Alignment.centerLeft,
      child: Button(onPressed: () {}, child: const Text('Review details')),
    ),
    child: const Text('Status, actions and diagnostics go here.'),
  );
}
