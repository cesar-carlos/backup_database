import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/widgets/atoms/app_card.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Organism** - consistent section surface for settings, summaries and page
/// content blocks.
class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    required this.title,
    required this.child,
    super.key,
    this.description,
    this.trailing,
    this.banner,
    this.footer,
    this.padding,
  });

  final String title;
  final String? description;
  final Widget child;
  final Widget? trailing;
  final Widget? banner;
  final Widget? footer;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final titleStyle = FluentTheme.of(context).typography.subtitle;
    final captionStyle = FluentTheme.of(context).typography.caption;

    return AppCard(
      padding: padding ?? AppSpacing.paddingLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.md),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (banner != null) ...[
            banner!,
            const SizedBox(height: AppSpacing.md),
          ],
          child,
          if (footer != null) ...[
            const SizedBox(height: AppSpacing.md),
            footer!,
          ],
        ],
      ),
    );
  }
}
