import 'package:backup_database/presentation/widgets/common/widget_texts.dart';
import 'package:fluent_ui/fluent_ui.dart';

class SaveButton extends StatelessWidget {
  const SaveButton({
    required this.onPressed,
    super.key,
    this.isEditing = false,
    this.isLoading = false,
  });
  final VoidCallback? onPressed;
  final bool isEditing;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final texts = WidgetTexts.fromContext(context);

    return Button(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: ProgressRing(strokeWidth: 2),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(FluentIcons.save),
                const SizedBox(width: 8),
                Text(isEditing ? texts.save : texts.create),
              ],
            ),
    );
  }
}
