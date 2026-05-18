import 'package:backup_database/presentation/widgets/atoms/app_text_field.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'Default', type: AppTextField)
Widget buildAppTextFieldDefaultUseCase(BuildContext context) {
  return const _AppTextFieldDefaultStory();
}

@widgetbook.UseCase(name: 'Focused', type: AppTextField)
Widget buildAppTextFieldFocusedUseCase(BuildContext context) {
  return const _AppTextFieldFocusedStory();
}

@widgetbook.UseCase(name: 'Error', type: AppTextField)
Widget buildAppTextFieldErrorUseCase(BuildContext context) {
  return const _AppTextFieldErrorStory();
}

@widgetbook.UseCase(name: 'Disabled', type: AppTextField)
Widget buildAppTextFieldDisabledUseCase(BuildContext context) {
  return const _AppTextFieldDisabledStory();
}

@widgetbook.UseCase(name: 'Prefix suffix', type: AppTextField)
Widget buildAppTextFieldPrefixSuffixUseCase(BuildContext context) {
  return const _AppTextFieldPrefixSuffixStory();
}

@widgetbook.UseCase(name: 'Knobs', type: AppTextField)
Widget buildAppTextFieldKnobsUseCase(BuildContext context) {
  return const _AppTextFieldKnobsStory();
}

class _AppTextFieldDefaultStory extends StatefulWidget {
  const _AppTextFieldDefaultStory();

  @override
  State<_AppTextFieldDefaultStory> createState() =>
      _AppTextFieldDefaultStoryState();
}

class _AppTextFieldDefaultStoryState extends State<_AppTextFieldDefaultStory> {
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
    return _fieldShell(
      AppTextField(
        label: 'Display name',
        hint: 'Enter a value',
        controller: _controller,
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}

class _AppTextFieldFocusedStory extends StatefulWidget {
  const _AppTextFieldFocusedStory();

  @override
  State<_AppTextFieldFocusedStory> createState() =>
      _AppTextFieldFocusedStoryState();
}

class _AppTextFieldFocusedStoryState extends State<_AppTextFieldFocusedStory> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: 'Focused on load');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _fieldShell(
      AppTextField(
        label: 'Autofocus',
        hint: 'Starts focused',
        controller: _controller,
        autofocus: true,
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}

class _AppTextFieldErrorStory extends StatefulWidget {
  const _AppTextFieldErrorStory();

  @override
  State<_AppTextFieldErrorStory> createState() =>
      _AppTextFieldErrorStoryState();
}

class _AppTextFieldErrorStoryState extends State<_AppTextFieldErrorStory> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: 'ab');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    if (value == null || value.length < 3) {
      return 'Enter at least 3 characters';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return _fieldShell(
      AppTextField(
        label: 'Validated',
        hint: 'Min 3 characters',
        controller: _controller,
        validator: _validate,
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}

class _AppTextFieldDisabledStory extends StatefulWidget {
  const _AppTextFieldDisabledStory();

  @override
  State<_AppTextFieldDisabledStory> createState() =>
      _AppTextFieldDisabledStoryState();
}

class _AppTextFieldDisabledStoryState
    extends State<_AppTextFieldDisabledStory> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: 'Read-only value');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _fieldShell(
      AppTextField(
        label: 'Disabled',
        hint: 'Cannot edit',
        controller: _controller,
        enabled: false,
      ),
    );
  }
}

class _AppTextFieldPrefixSuffixStory extends StatefulWidget {
  const _AppTextFieldPrefixSuffixStory();

  @override
  State<_AppTextFieldPrefixSuffixStory> createState() =>
      _AppTextFieldPrefixSuffixStoryState();
}

class _AppTextFieldPrefixSuffixStoryState
    extends State<_AppTextFieldPrefixSuffixStory> {
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
    return _fieldShell(
      AppTextField(
        label: 'Search',
        hint: 'Filter…',
        controller: _controller,
        prefixIcon: const Icon(FluentIcons.search),
        suffixIcon: IconButton(
          icon: const Icon(FluentIcons.clear),
          onPressed: () {
            _controller.clear();
            setState(() {});
          },
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}

class _AppTextFieldKnobsStory extends StatefulWidget {
  const _AppTextFieldKnobsStory();

  @override
  State<_AppTextFieldKnobsStory> createState() =>
      _AppTextFieldKnobsStoryState();
}

class _AppTextFieldKnobsStoryState extends State<_AppTextFieldKnobsStory> {
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
    final String label = context.knobs.string(
      label: 'Label',
      initialValue: 'Notes',
    );
    final String hint = context.knobs.string(
      label: 'Hint',
      initialValue: 'Optional',
    );
    final bool enabled = context.knobs.boolean(
      label: 'Enabled',
      initialValue: true,
    );
    return _fieldShell(
      AppTextField(
        label: label,
        hint: hint,
        enabled: enabled,
        controller: _controller,
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}

Widget _fieldShell(Widget field) {
  return Align(
    alignment: Alignment.topCenter,
    child: SizedBox(width: 360, child: field),
  );
}
