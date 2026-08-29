import 'package:backup_database/core/theme/theme.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — title, optional description and a [ToggleSwitch].
class LabeledToggle extends StatelessWidget {
  const LabeledToggle({
    required this.title,
    required this.value,
    super.key,
    this.description,
    this.onChanged,
    this.disabledReason,
  });

  final String title;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final typography = FluentTheme.of(context).typography;
    final captionStyle = typography.caption;
    final titleStyle = typography.body?.copyWith(fontWeight: FontWeight.w600);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: titleStyle),
              if (description != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(description!, style: captionStyle),
              ],
              if (disabledReason != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  disabledReason!,
                  style: captionStyle?.copyWith(
                    color: context.colors.warning,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        ToggleSwitch(
          checked: value,
          onChanged: onChanged,
          semanticLabel: title,
        ),
      ],
    );
  }
}
