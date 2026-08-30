import 'dart:async';

import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/providers/providers.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

/// **Molecule** — table density dropdown for system settings.
class SystemDensityRow extends StatelessWidget {
  const SystemDensityRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppDensityProvider>(
      builder: (context, densityProvider, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appLocaleString(
                context,
                'Densidade das tabelas',
                'Table density',
              ),
              style: FluentTheme.of(context).typography.bodyStrong,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              appLocaleString(
                context,
                'Controla o espacamento visual de listas e grades.',
                'Controls the visual spacing of lists and data grids.',
              ),
              style: FluentTheme.of(context).typography.caption,
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: 220,
              child: AppDropdown<AppDensity>(
                compact: true,
                label: appLocaleString(
                  context,
                  'Densidade das tabelas',
                  'Table density',
                ),
                value: densityProvider.density,
                items: [
                  ComboBoxItem(
                    value: AppDensity.compact,
                    child: Text(
                      appLocaleString(context, 'Compacta', 'Compact'),
                    ),
                  ),
                  ComboBoxItem(
                    value: AppDensity.comfortable,
                    child: Text(
                      appLocaleString(context, 'Confortavel', 'Comfortable'),
                    ),
                  ),
                  ComboBoxItem(
                    value: AppDensity.spacious,
                    child: Text(
                      appLocaleString(context, 'Espacosa', 'Spacious'),
                    ),
                  ),
                ],
                onChanged: (AppDensity? value) {
                  if (value != null) {
                    unawaited(densityProvider.setDensity(value));
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
