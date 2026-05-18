import 'package:backup_database/presentation/widgets/atoms/widget_texts.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Atom** — labeled Fluent combo box bound to a value list.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    required this.label,
    required this.value,
    required this.items,
    super.key,
    this.onChanged,
    this.placeholder,
    this.compact = false,
  });
  final String label;
  final T? value;
  final List<ComboBoxItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final Widget? placeholder;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final texts = WidgetTexts.fromContext(context);
    final combo = SizedBox(
      width: double.infinity,
      child: ComboBox<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        isExpanded: true,
        placeholder: placeholder ?? Text(texts.select(label)),
      ),
    );

    if (compact) {
      return combo;
    }

    return InfoLabel(
      label: label,
      child: combo,
    );
  }
}
