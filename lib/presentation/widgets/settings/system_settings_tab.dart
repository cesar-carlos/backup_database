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
import 'package:backup_database/presentation/widgets/settings/system/system_about_section.dart';
import 'package:backup_database/presentation/widgets/settings/system/system_appearance_section.dart';
import 'package:backup_database/presentation/widgets/settings/system/system_startup_section.dart';
import 'package:backup_database/presentation/widgets/settings/system/system_tray_section.dart';
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
      padding: AppSpacing.paddingLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SystemAppearanceSection(
            themeProvider: themeProvider,
            useWindowsMicaBackdrop: _useWindowsMicaBackdrop,
            onMicaChanged: (bool enabled) async {
              setState(() => _useWindowsMicaBackdrop = enabled);
              await getIt<IUserPreferencesRepository>()
                  .setUseWindowsMicaBackdrop(enabled);
              await WindowsNativeChromeBootstrap.setBackdrop(
                micaEnabled: enabled,
                isDark: themeProvider.isDarkMode,
              );
            },
          ),
          AppSpacing.gapLg,
          SystemStartupSection(
            systemSettings: systemSettings,
            features: features,
          ),
          AppSpacing.gapLg,
          SystemTraySection(
            systemSettings: systemSettings,
            features: features,
          ),
          AppSpacing.gapLg,
          SystemAboutSection(
            versionLabel: _versionLabel(),
            modeLabel: _modeLabel(),
          ),
        ],
      ),
    );
  }
}
