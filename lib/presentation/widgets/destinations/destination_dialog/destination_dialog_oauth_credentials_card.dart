import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — prompt to configure OAuth client credentials.
class OAuthCredentialsSectionCard extends StatelessWidget {
  const OAuthCredentialsSectionCard({
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onPressed,
    super.key,
  });

  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: FluentTheme.of(
          context,
        ).resources.cardBackgroundFillColorDefault.withValues(alpha: 0.3),
        borderRadius: AppRadius.circularMd,
        border: Border.all(
          color: context.colors.info.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.settings,
                color: context.colors.info,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                title,
                style: FluentTheme.of(
                  context,
                ).typography.subtitle?.copyWith(color: context.colors.info),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(description, style: FluentTheme.of(context).typography.caption),
          const SizedBox(height: 12),
          AppButton.icon(
            icon: FluentIcons.lock,
            label: actionLabel,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}
