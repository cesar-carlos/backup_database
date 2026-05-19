import 'package:backup_database/presentation/widgets/molecules/cancel_button.dart';
import 'package:backup_database/presentation/widgets/organisms/app_dialog_shell.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'Default', type: AppDialogShell)
Widget buildAppDialogShellDefaultUseCase(BuildContext context) {
  return AppDialogShell(
    constraints: const BoxConstraints(maxWidth: 520),
    title: const Text('New destination'),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        Text('Dialog body content'),
        SizedBox(height: 16),
        TextBox(placeholder: 'Name'),
      ],
    ),
    actions: [
      CancelButton(onPressed: () {}),
      FilledButton(onPressed: () {}, child: const Text('Save')),
    ],
  );
}
