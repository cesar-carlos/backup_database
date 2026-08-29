import 'package:backup_database/presentation/widgets/atoms/app_button.dart';
import 'package:backup_database/presentation/widgets/atoms/widget_texts.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — save/create action with loading affordance.
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

    return AppButton.primary(
      label: isEditing ? texts.save : texts.create,
      onPressed: onPressed,
      isLoading: isLoading,
      leading: const Icon(FluentIcons.save),
    );
  }
}
