import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:backup_database/presentation/widgets/settings/license/license_feature_labels.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — allowed-feature checklist for the effective license.
class LicenseFeaturesList extends StatelessWidget {
  const LicenseFeaturesList({required this.license, super.key});

  final License license;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appLocaleString(context, 'Recursos permitidos', 'Allowed features'),
          style: FluentTheme.of(context).typography.bodyStrong,
        ),
        const SizedBox(height: AppSpacing.sm),
        ...license.allowedFeatures.map(
          (feature) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                Icon(
                  FluentIcons.accept,
                  size: 16,
                  color: context.colors.success,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(licenseFeatureLabel(context, feature)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
