import 'package:backup_database/presentation/widgets/molecules/password_field.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'Default', type: PasswordField)
Widget buildPasswordFieldDefaultUseCase(BuildContext context) {
  return const _PasswordFieldShell(child: PasswordField());
}

@widgetbook.UseCase(name: 'With value', type: PasswordField)
Widget buildPasswordFieldWithValueUseCase(BuildContext context) {
  return const _PasswordFieldWithValueStory();
}

@widgetbook.UseCase(name: 'Validation error', type: PasswordField)
Widget buildPasswordFieldValidationUseCase(BuildContext context) {
  return const _PasswordFieldValidationStory();
}

@widgetbook.UseCase(name: 'Disabled', type: PasswordField)
Widget buildPasswordFieldDisabledUseCase(BuildContext context) {
  return const _PasswordFieldShell(
    child: PasswordField(enabled: false, label: 'Password', hint: 'Locked'),
  );
}

class _PasswordFieldShell extends StatelessWidget {
  const _PasswordFieldShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: 360, child: child),
    );
  }
}

class _PasswordFieldWithValueStory extends StatefulWidget {
  const _PasswordFieldWithValueStory();

  @override
  State<_PasswordFieldWithValueStory> createState() =>
      _PasswordFieldWithValueStoryState();
}

class _PasswordFieldWithValueStoryState
    extends State<_PasswordFieldWithValueStory> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: 'hunter2');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PasswordFieldShell(
      child: PasswordField(
        controller: _controller,
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}

class _PasswordFieldValidationStory extends StatefulWidget {
  const _PasswordFieldValidationStory();

  @override
  State<_PasswordFieldValidationStory> createState() =>
      _PasswordFieldValidationStoryState();
}

class _PasswordFieldValidationStoryState
    extends State<_PasswordFieldValidationStory> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PasswordFieldShell(
      child: PasswordField(
        label: 'Senha',
        controller: _controller,
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}
