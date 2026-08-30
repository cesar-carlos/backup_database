import 'dart:async';
import 'dart:io' show Platform;

import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/providers/providers.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/settings_ui.dart';
import 'package:backup_database/presentation/widgets/settings/system/system_density_row.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

/// **Organism** — theme, mica, accent, density and loading animations.
class SystemAppearanceSection extends StatelessWidget {
  const SystemAppearanceSection({
    required this.themeProvider,
    required this.useWindowsMicaBackdrop,
    required this.onMicaChanged,
    super.key,
  });

  final ThemeProvider themeProvider;
  final bool useWindowsMicaBackdrop;
  final ValueChanged<bool> onMicaChanged;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: appLocaleString(context, 'Aparencia', 'Appearance'),
      description: appLocaleString(
        context,
        'Preferencias visuais e de uso da interface.',
        'Visual and interaction preferences for the interface.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsToggleRow(
            title: appLocaleString(context, 'Tema escuro', 'Dark theme'),
            description: appLocaleString(
              context,
              'Alterna o tema principal da aplicacao.',
              'Switches the main application theme.',
            ),
            value: themeProvider.isDarkMode,
            onChanged: themeProvider.setDarkMode,
          ),
          if (Platform.isWindows) ...[
            const SizedBox(height: AppSpacing.lg),
            SettingsToggleRow(
              title: appLocaleString(
                context,
                'Backdrop Mica (Windows 11)',
                'Mica backdrop (Windows 11)',
              ),
              description: appLocaleString(
                context,
                'Aplica o efeito de superficie do Windows na janela.',
                'Applies the Windows surface effect to the window.',
              ),
              value: useWindowsMicaBackdrop,
              onChanged: onMicaChanged,
            ),
            const SizedBox(height: AppSpacing.lg),
            SettingsToggleRow(
              title: appLocaleString(
                context,
                'Cor de destaque do sistema',
                'System accent color',
              ),
              description: appLocaleString(
                context,
                'Usa a cor de destaque do Windows em vez da cor da marca.',
                'Uses the Windows accent color instead of the brand color.',
              ),
              value: themeProvider.useSystemAccentColor,
              onChanged: themeProvider.setUseSystemAccentColor,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const SystemDensityRow(),
          const SizedBox(height: AppSpacing.lg),
          Consumer<SkeletonLoadingPreferenceProvider>(
            builder: (context, skeletonPrefs, _) {
              return SettingsToggleRow(
                title: appLocaleString(
                  context,
                  'Animacoes de carregamento',
                  'Loading animations',
                ),
                description: appLocaleString(
                  context,
                  'Desative para reduzir movimento na tela.',
                  'Turn off to reduce on-screen motion.',
                ),
                value: skeletonPrefs.shimmerLoadingEffectsEnabled,
                onChanged: (bool enabled) {
                  unawaited(
                    skeletonPrefs.setShimmerLoadingEffectsEnabled(enabled),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
