import 'package:backup_database/presentation/widgets/atoms/widget_texts.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — dismiss/cancel action with localized label.
class CancelButton extends StatelessWidget {
  const CancelButton({super.key, this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final texts = WidgetTexts.fromContext(context);

    return Semantics(
      button: true,
      label: texts.cancel,
      child: Button(
        onPressed: onPressed ?? () => Navigator.of(context).pop(),
        child: Text(texts.cancel),
      ),
    );
  }
}
