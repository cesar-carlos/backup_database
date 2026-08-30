import 'package:backup_database/presentation/widgets/molecules/host_port_fields.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'Default', type: HostPortFields)
Widget buildHostPortFieldsDefaultUseCase(BuildContext context) {
  return const _HostPortFieldsStory();
}

class _HostPortFieldsStory extends StatefulWidget {
  const _HostPortFieldsStory();

  @override
  State<_HostPortFieldsStory> createState() => _HostPortFieldsStoryState();
}

class _HostPortFieldsStoryState extends State<_HostPortFieldsStory> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: '127.0.0.1');
    _portController = TextEditingController(text: '1433');
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 520,
      child: HostPortFields(
        hostController: _hostController,
        portController: _portController,
        hostLabel: 'Host',
        portLabel: 'Port',
      ),
    );
  }
}
