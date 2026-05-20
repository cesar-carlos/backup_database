import 'dart:async';
import 'dart:io' show Platform;

import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:backup_database/presentation/boot/windows_native_chrome_bootstrap.dart';
import 'package:backup_database/presentation/providers/providers.dart';
import 'package:backup_database/presentation/utils/compatibility_reason_localizer.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/settings_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

class SystemSettingsTab extends StatefulWidget {
  const SystemSettingsTab({super.key});

  @override
  State<SystemSettingsTab> createState() => _SystemSettingsTabState();
}

class _SystemSettingsTabState extends State<SystemSettingsTab> {
  PackageInfo? _packageInfo;
  bool _isLoadingVersion = true;
  bool _useWindowsMicaBackdrop = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPackageInfo());
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
      LoggerService.warning('Erro ao carregar preferencia Mica', e, s);
    }
  }

  Future<void> _loadPackageInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _packageInfo = packageInfo;
          _isLoadingVersion = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _isLoadingVersion = false;
        });
      }
    }
  }

  String _modeLabel() {
    return switch (currentAppMode) {
      AppMode.client => appLocaleString(context, 'Cliente', 'Client'),
      AppMode.server => appLocaleString(context, 'Servidor', 'Server'),
      AppMode.unified => appLocaleString(context, 'Unificado', 'Unified'),
    };
  }

  String _versionLabel() {
    if (_isLoadingVersion) {
      return appLocaleString(context, 'Carregando...', 'Loading...');
    }
    if (_packageInfo == null) {
      return appLocaleString(context, 'Desconhecida', 'Unknown');
    }
    if (_packageInfo!.buildNumber.isNotEmpty) {
      return '${_packageInfo!.version}+${_packageInfo!.buildNumber}';
    }
    return _packageInfo!.version;
  }

  @override
  Widget build(BuildContext context) {
    final systemSettings = Provider.of<SystemSettingsProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final features = getIt<FeatureAvailabilityService>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAppearanceSection(context, themeProvider),
          const SizedBox(height: 24),
          _buildStartupSection(context, systemSettings, features),
          const SizedBox(height: 24),
          _buildTraySection(context, systemSettings, features),
          const SizedBox(height: 24),
          _buildAboutSection(context),
        ],
      ),
    );
  }

  Widget _buildAppearanceSection(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
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
                'Controla o espacamento visual de listas e grades.',
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

  Widget _buildStartupSection(
    BuildContext context,
    SystemSettingsProvider systemSettings,
    FeatureAvailabilityService features,
  ) {
    final startupDisabledReason = !features.isStartupAtLogonTaskEnabled
        ? localizeCompatibilityReason(
            context,
            reason: features.startupAtLogonTaskDisabledReason,
            fallbackPt:
                'A tarefa de inicio no logon nao esta disponivel nesta versao do Windows.',
            fallbackEn:
                'Logon startup task is not available on this Windows version.',
          )
        : null;

    return AppSectionCard(
      title: appLocaleString(context, 'Inicializacao', 'Startup'),
      description: appLocaleString(
        context,
        'Preferencias de arranque da aplicacao na maquina atual.',
        'Startup preferences for the current machine.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsToggleRow(
            title: appLocaleString(
              context,
              'Iniciar com o Windows',
              'Start with Windows',
            ),
            description: currentAppMode == AppMode.server
                ? appLocaleString(
                    context,
                    'No modo servidor, o arranque automatico real e controlado pela aba Servico Windows.',
                    'In server mode, real automatic startup is controlled from the Windows Service tab.',
                  )
                : appLocaleString(
                    context,
                    'Cria ou remove a tarefa de arranque para esta instalacao.',
                    'Creates or removes the startup task for this installation.',
                  ),
            value: systemSettings.startWithWindows,
            onChanged: features.isStartupAtLogonTaskEnabled
                ? systemSettings.setStartWithWindows
                : null,
            disabledReason: startupDisabledReason,
          ),
          const SizedBox(height: AppSpacing.lg),
          SettingsToggleRow(
            title: appLocaleString(
              context,
              'Iniciar minimizado',
              'Start minimized',
            ),
            description: appLocaleString(
              context,
              'Abre a aplicacao ja minimizada na proxima inicializacao.',
              'Opens the application minimized on the next startup.',
            ),
            value: systemSettings.startMinimized,
            onChanged: systemSettings.setStartMinimized,
          ),
        ],
      ),
    );
  }

  Widget _buildTraySection(
    BuildContext context,
    SystemSettingsProvider systemSettings,
    FeatureAvailabilityService features,
  ) {
    final trayDisabledReason = !features.isTrayEnabled
        ? localizeCompatibilityReason(
            context,
            reason: features.trayDisabledReason,
            fallbackPt:
                'A bandeja do sistema nao esta disponivel nesta versao do Windows.',
            fallbackEn: 'System tray is not available on this Windows version.',
          )
        : null;

    return AppSectionCard(
      title: appLocaleString(context, 'Bandeja', 'Tray'),
      description: appLocaleString(
        context,
        'Define como a janela se comporta ao minimizar ou fechar.',
        'Defines how the window behaves when minimizing or closing.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsToggleRow(
            title: appLocaleString(
              context,
              'Minimizar para bandeja',
              'Minimize to tray',
            ),
            description: appLocaleString(
              context,
              'Mantem o app em segundo plano ao minimizar a janela.',
              'Keeps the app running in the background when the window is minimized.',
            ),
            value: systemSettings.minimizeToTray,
            onChanged: features.isTrayEnabled
                ? systemSettings.setMinimizeToTray
                : null,
            disabledReason: trayDisabledReason,
          ),
          const SizedBox(height: AppSpacing.lg),
          SettingsToggleRow(
            title: appLocaleString(
              context,
              'Fechar para bandeja',
              'Close to tray',
            ),
            description: appLocaleString(
              context,
              'Fecha a janela principal, mas mantem o processo na bandeja.',
              'Closes the main window while keeping the process in the system tray.',
            ),
            value: systemSettings.closeToTray,
            onChanged: features.isTrayEnabled
                ? systemSettings.setCloseToTray
                : null,
            disabledReason: trayDisabledReason,
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    final cards = [
      SettingsFactTile(
        label: appLocaleString(context, 'Versao', 'Version'),
        value: _versionLabel(),
        expandToFit: true,
        caption: appLocaleString(
          context,
          'Versao instalada nesta maquina.',
          'Version installed on this machine.',
        ),
      ),
      SettingsFactTile(
        label: appLocaleString(context, 'Modo atual', 'Current mode'),
        value: _modeLabel(),
        expandToFit: true,
        caption: appLocaleString(
          context,
          'Contexto de operacao ativo na inicializacao.',
          'Operation context active at startup.',
        ),
      ),
      SettingsFactTile(
        label: appLocaleString(context, 'Licenca', 'License'),
        value: 'MIT License',
        expandToFit: true,
        caption: appLocaleString(
          context,
          'Termo de distribuicao do aplicativo.',
          'Application distribution terms.',
        ),
      ),
    ];

    return AppSectionCard(
      title: appLocaleString(context, 'Sobre', 'About'),
      description: appLocaleString(
        context,
        'Metadados principais da instalacao local.',
        'Main metadata for the local installation.',
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 860) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: cards[1]),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: cards[2]),
                ],
              ),
            );
          }

          return Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: cards,
          );
        },
      ),
    );
  }
}
