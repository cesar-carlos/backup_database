import 'dart:async';
import 'dart:io' show Platform;

import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/services/temp_directory_service.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:backup_database/presentation/boot/windows_native_chrome_bootstrap.dart';
import 'package:backup_database/presentation/providers/providers.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/machine_storage_settings_section.dart';
import 'package:backup_database/presentation/widgets/settings/settings_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

class GeneralSettingsTab extends StatefulWidget {
  const GeneralSettingsTab({super.key});

  @override
  State<GeneralSettingsTab> createState() => _GeneralSettingsTabState();
}

class _GeneralSettingsTabState extends State<GeneralSettingsTab> {
  String? _tempDownloadsPath;
  bool _isLoadingTempPath = false;
  bool _useWindowsMicaBackdrop = true;

  final TempDirectoryService _tempService = getIt<TempDirectoryService>();

  @override
  void initState() {
    super.initState();
    unawaited(_loadTempPath());
    unawaited(_loadWindowsChromePrefs());
  }

  Future<void> _loadWindowsChromePrefs() async {
    if (!Platform.isWindows) {
      return;
    }
    try {
      final repo = getIt<IUserPreferencesRepository>();
      final value = await repo.getUseWindowsMicaBackdrop();
      if (mounted) {
        setState(() => _useWindowsMicaBackdrop = value);
      }
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao carregar preferência Mica', e, s);
    }
  }

  Future<void> _loadTempPath() async {
    if (!mounted) return;
    setState(() => _isLoadingTempPath = true);
    try {
      final dir = await _tempService.getDownloadsDirectory();
      if (mounted) {
        setState(() {
          _tempDownloadsPath = dir.path;
          _isLoadingTempPath = false;
        });
      }
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao carregar pasta temporária', e, s);
      if (mounted) {
        setState(() => _isLoadingTempPath = false);
      }
    }
  }

  Future<void> _changeTempPath() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: appLocaleString(
        context,
        'Selecionar pasta temporária de downloads',
        'Select temporary downloads folder',
      ),
    );
    if (result != null && mounted) {
      setState(() => _isLoadingTempPath = true);
      final success = await _tempService.setCustomTempPath(result);
      if (mounted) {
        setState(() => _isLoadingTempPath = false);
        if (!success) {
          unawaited(
            MessageModal.showError(
              context,
              message: appLocaleString(
                context,
                'Não foi possível definir a pasta temporária. Verifique se tem permissão de escrita.',
                'Could not set temporary folder. Check write permissions.',
              ),
            ),
          );
          return;
        }
        await _loadTempPath();
        if (!mounted) {
          return;
        }
        unawaited(
          FluentInfoBarFeedback.showSuccess(
            context,
            message: appLocaleString(
              context,
              'Pasta temporária alterada com sucesso!',
              'Temporary folder changed successfully!',
            ),
          ),
        );
      }
    }
  }

  Future<void> _resetTempPath() async {
    final confirmed = await MessageModal.showConfirm(
      context,
      title: appLocaleString(context, 'Confirmar', 'Confirm'),
      message: appLocaleString(
        context,
        'Deseja voltar a usar a pasta temporária padrão do sistema?',
        'Do you want to use the system default temporary folder again?',
      ),
      confirmLabel: appLocaleString(context, 'Confirmar', 'Confirm'),
      confirmIcon: FluentIcons.refresh,
    );
    if (confirmed && mounted) {
      await _tempService.clearCustomTempPath();
      await _loadTempPath();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAppearanceSection(context, themeProvider),
          if (currentAppMode == AppMode.client) ...[
            const SizedBox(height: 24),
            _buildClientDownloadsSection(context),
          ],
          const SizedBox(height: 24),
          const MachineStorageSettingsSection(),
        ],
      ),
    );
  }

  Widget _buildAppearanceSection(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    return AppSectionCard(
      title: appLocaleString(context, 'Aparência', 'Appearance'),
      description: appLocaleString(
        context,
        'Preferências visuais e de uso da interface.',
        'Visual and interaction preferences for the interface.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsToggleRow(
            title: appLocaleString(context, 'Tema escuro', 'Dark theme'),
            description: appLocaleString(
              context,
              'Alterna o tema principal da aplicação.',
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
                'Aplica o efeito de superfície do Windows na janela.',
                'Applies the Windows surface effect to the window.',
              ),
              value: _useWindowsMicaBackdrop,
              onChanged: (bool enabled) async {
                setState(() => _useWindowsMicaBackdrop = enabled);
                await getIt<IUserPreferencesRepository>()
                    .setUseWindowsMicaBackdrop(enabled);
                await WindowsNativeChromeBootstrap.setBackdrop(
                  micaEnabled: enabled,
                  isDark: themeProvider.isDarkMode,
                );
              },
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
          _buildDensityRow(context),
          const SizedBox(height: AppSpacing.lg),
          Consumer<SkeletonLoadingPreferenceProvider>(
            builder: (context, skeletonPrefs, _) {
              return SettingsToggleRow(
                title: appLocaleString(
                  context,
                  'Animações de carregamento',
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

  Widget _buildDensityRow(BuildContext context) {
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
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              appLocaleString(
                context,
                'Controla o espaçamento visual de listas e grades.',
                'Controls the visual spacing of lists and data grids.',
              ),
              style: FluentTheme.of(context).typography.caption,
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: 220,
              child: ComboBox<AppDensity>(
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
                      appLocaleString(context, 'Confortável', 'Comfortable'),
                    ),
                  ),
                  ComboBoxItem(
                    value: AppDensity.spacious,
                    child: Text(
                      appLocaleString(context, 'Espaçosa', 'Spacious'),
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

  Widget _buildClientDownloadsSection(BuildContext context) {
    return AppSectionCard(
      title: appLocaleString(
        context,
        'Pasta temporária de downloads',
        'Temporary downloads folder',
      ),
      description: appLocaleString(
        context,
        'Arquivos recebidos do servidor passam por esta pasta antes do envio final.',
        'Files received from the server pass through this folder before final delivery.',
      ),
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
                    Text(
                      appLocaleString(context, 'Pasta atual', 'Current folder'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    if (_isLoadingTempPath)
                      Text(
                        appLocaleString(context, 'Carregando...', 'Loading...'),
                      )
                    else
                      SelectableText(
                        _tempDownloadsPath ??
                            appLocaleString(context, 'Desconhecida', 'Unknown'),
                        style: FluentTheme.of(context).typography.caption
                            ?.copyWith(
                              fontFamily: 'Consolas',
                            ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  FilledButton(
                    onPressed: _isLoadingTempPath
                        ? null
                        : () => unawaited(_changeTempPath()),
                    child: Text(
                      appLocaleString(
                        context,
                        'Alterar pasta',
                        'Change folder',
                      ),
                    ),
                  ),
                  Button(
                    onPressed: _isLoadingTempPath
                        ? null
                        : () => unawaited(_resetTempPath()),
                    child: Text(
                      appLocaleString(
                        context,
                        'Usar padrão do sistema',
                        'Use system default',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(FluentIcons.refresh),
                    onPressed: _isLoadingTempPath
                        ? null
                        : () => unawaited(_loadTempPath()),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
