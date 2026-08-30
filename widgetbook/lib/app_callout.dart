import 'package:backup_database/presentation/widgets/atoms/app_callout.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'Info', type: AppCallout)
Widget buildAppCalloutInfoUseCase(BuildContext context) {
  return const SizedBox(
    width: 420,
    child: AppCallout(message: 'Fill host and port to continue'),
  );
}

@widgetbook.UseCase(name: 'Warning', type: AppCallout)
Widget buildAppCalloutWarningUseCase(BuildContext context) {
  return const SizedBox(
    width: 420,
    child: AppCallout(
      message: 'This destination requires a license',
      tone: AppCalloutTone.warning,
    ),
  );
}

@widgetbook.UseCase(name: 'Danger', type: AppCallout)
Widget buildAppCalloutDangerUseCase(BuildContext context) {
  return const SizedBox(
    width: 420,
    child: AppCallout(
      message: 'Connection refused',
      tone: AppCalloutTone.danger,
    ),
  );
}

@widgetbook.UseCase(name: 'Success', type: AppCallout)
Widget buildAppCalloutSuccessUseCase(BuildContext context) {
  return const SizedBox(
    width: 420,
    child: AppCallout(
      message: 'Connection succeeded',
      tone: AppCalloutTone.success,
    ),
  );
}
