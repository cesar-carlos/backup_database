import 'package:backup_database/presentation/widgets/common/widget_texts.dart';
import 'package:fluent_ui/fluent_ui.dart';

class CancelButton extends StatelessWidget {
  const CancelButton({super.key, this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final texts = WidgetTexts.fromContext(context);

    return Button(
      onPressed: onPressed ?? () => Navigator.of(context).pop(),
      child: Text(texts.cancel),
    );
  }
}
