import 'package:backup_database/presentation/widgets/organisms/message_modal.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'Success', type: MessageModal)
Widget buildMessageModalSuccessUseCase(BuildContext context) {
  return const _MessageModalShell(
    child: MessageModal(
      title: 'Saved',
      message: 'Your changes were stored successfully.',
      type: MessageType.success,
    ),
  );
}

@widgetbook.UseCase(name: 'Info', type: MessageModal)
Widget buildMessageModalInfoUseCase(BuildContext context) {
  return const _MessageModalShell(
    child: MessageModal(
      title: 'Information',
      message:
          'This is an informational message with enough text to '
          'wrap inside the dialog content area.',
      type: MessageType.info,
    ),
  );
}

@widgetbook.UseCase(name: 'Warning', type: MessageModal)
Widget buildMessageModalWarningUseCase(BuildContext context) {
  return const _MessageModalShell(
    child: MessageModal(
      title: 'Attention',
      message: 'Proceed only if you understand the consequences.',
      type: MessageType.warning,
    ),
  );
}

@widgetbook.UseCase(name: 'Error', type: MessageModal)
Widget buildMessageModalErrorUseCase(BuildContext context) {
  return const _MessageModalShell(
    child: MessageModal(
      title: 'Error',
      message:
          'Connection refused: example.com:3050\n'
          'errno 10061',
      type: MessageType.error,
    ),
  );
}

@widgetbook.UseCase(name: 'Custom button', type: MessageModal)
Widget buildMessageModalCustomButtonUseCase(BuildContext context) {
  return const _MessageModalShell(
    child: MessageModal(
      title: 'Done',
      message: 'Operation completed.',
      type: MessageType.success,
      buttonLabel: 'Close',
    ),
  );
}

class _MessageModalShell extends StatelessWidget {
  const _MessageModalShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: child,
      ),
    );
  }
}
