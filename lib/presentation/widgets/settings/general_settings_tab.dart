import 'package:backup_database/application/providers/auto_update_provider.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/services/temp_directory_service.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/presentation/providers/providers.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/machine_storage_settings_section.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

class GeneralSettingsTab extends StatefulWidget {
  const GeneralSettingsTab({super.key});

  @override
  State<GeneralSettingsTab> createState() => _GeneralSettingsTabState();
}

class _GeneralSettingsTabState extends State<GeneralSettingsTab> {
  PackageInfo? _packageInfo;
  bool _isLoadingVersion = true;
  String? _tempDownloadsPath;
  bool _isLoadingTempPath = false;

  final TempDirectoryService _tempService = getIt<TempDirectoryService>();

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _loadTempPath();
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
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao carregar informações do pacote', e, s);
      if (mounted) {
        setState(() {
          _isLoadingVersion = false;
        });
      }
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
          MessageModal.showError(
            context,
            message: appLocaleString(
              context,
              'Não foi possível definir a pasta temporária. Verifique se tem '
                  'permissão de escrita.',
              'Could not set temporary folder. Check write permissions.',
            ),
          );
          return;
        }
        await _loadTempPath();
        if (!mounted) {
          return;
        }
        MessageModal.showSuccess(
          context,
          message: appLocaleString(
            context,
            'Pasta temporária alterada com sucesso!',
            'Temporary folder changed successfully!',
          ),
        );
      }
    }
  }

  Future<void> _resetTempPath() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(appLocaleString(context, 'Confirmar', 'Confirm')),
        content: Text(
          appLocaleString(
            context,
            'Deseja voltar a usar a pasta temporária padrão do sistema?',
            'Do you want to use the system default temporary folder again?',
          ),
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(context, false),
            child: Text(appLocaleString(context, 'Cancelar', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(appLocaleString(context, 'Confirmar', 'Confirm')),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && mounted) {
      await _tempService.clearCustomTempPath();
      await _loadTempPath();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final systemSettings = Provider.of<SystemSettingsProvider>(context);
    final autoUpdateProvider = Provider.of<AutoUpdateProvider>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appLocaleString(context, 'Aparência', 'Appearance'),
                  style: FluentTheme.of(context).typography.subtitle,
                ),
                const SizedBox(height: 16),
                InfoLabel(
                  label: appLocaleString(context, 'Tema escuro', 'Dark theme'),
                  child: ToggleSwitch(
                    checked: themeProvider.isDarkMode,
                    onChanged: themeProvider.setDarkMode,
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  appLocaleString(context, 'Sistema', 'System'),
                  style: FluentTheme.of(context).typography.subtitle,
                ),
                const SizedBox(height: 16),
                InfoLabel(
                  label: appLocaleString(
                    context,
                    'Iniciar com o Windows',
                    'Start with Windows',
                  ),
                  child: ToggleSwitch(
                    checked: systemSettings.startWithWindows,
                    onChanged: systemSettings.setStartWithWindows,
                  ),
                ),
                if (currentAppMode == AppMode.server) ...[
                  const SizedBox(height: 8),
                  Text(
                    appLocaleString(
                      context,
                      'No modo servidor o arranque automático é feito pelo '
                          'Windows Service (aba Serviço). Esta opção apenas '
                          'guarda a preferência na máquina.',
                      'In server mode, automatic startup is handled by the '
                          'Windows Service (Service tab). This option only '
                          'stores the preference for this machine.',
                    ),
                    style: FluentTheme.of(context).typography.caption,
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    appLocaleString(
                      context,
                      'A tarefa de início aplica-se a todos os utilizadores '
                          'deste PC. Pode ser necessário executar a aplicação '
                          'como administrador para criar ou remover a tarefa.',
                      'The startup task applies to all users on this PC. '
                          'You may need to run the app as administrator to '
                          'create or remove the task.',
                    ),
                    style: FluentTheme.of(context).typography.caption,
                  ),
                ],
                const SizedBox(height: 16),
                InfoLabel(
                  label: appLocaleString(
                    context,
                    'Iniciar minimizado',
                    'Start minimized',
                  ),
                  child: ToggleSwitch(
                    checked: systemSettings.startMinimized,
                    onChanged: systemSettings.setStartMinimized,
                  ),
                ),
                const SizedBox(height: 16),
                InfoLabel(
                  label: appLocaleString(
                    context,
                    'Minimizar para bandeja',
                    'Minimize to tray',
                  ),
                  child: ToggleSwitch(
                    checked: systemSettings.minimizeToTray,
                    onChanged: systemSettings.setMinimizeToTray,
                  ),
                ),
                const SizedBox(height: 16),
                InfoLabel(
                  label: appLocaleString(
                    context,
                    'Fechar para bandeja',
                    'Close to tray',
                  ),
                  child: ToggleSwitch(
                    checked: systemSettings.closeToTray,
                    onChanged: systemSettings.setCloseToTray,
                  ),
                ),
                if (currentAppMode == AppMode.client) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    appLocaleString(
                      context,
                      'Pasta temporária de downloads (cliente)',
                      'Temporary downloads folder (client)',
                    ),
                    style: FluentTheme.of(context).typography.subtitle,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    appLocaleString(
                      context,
                      'Arquivos baixados do servidor são salvos temporariamente '
                          'aqui antes de serem enviados para os destinos finais.',
                      'Files downloaded from server are saved here temporarily '
                          'before being sent to final destinations.',
                    ),
                    style: FluentTheme.of(context).typography.caption,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: Text(
                      appLocaleString(context, 'Pasta atual', 'Current folder'),
                    ),
                    subtitle: _isLoadingTempPath
                        ? Text(
                            appLocaleString(
                              context,
                              'Carregando...',
                              'Loading...',
                            ),
                          )
                        : Text(
                            _tempDownloadsPath ??
                                appLocaleString(
                                  context,
                                  'Desconhecida',
                                  'Unknown',
                                ),
                          ),
                    trailing: _isLoadingTempPath
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: ProgressRing(strokeWidth: 2),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(FluentIcons.folder_open),
                                onPressed: _changeTempPath,
                              ),
                              IconButton(
                                icon: const Icon(FluentIcons.refresh),
                                onPressed: _loadTempPath,
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _changeTempPath,
                    child: Text(
                      appLocaleString(
                        context,
                        'Alterar pasta',
                        'Change folder',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Button(
                    onPressed: _resetTempPath,
                    child: Text(
                      appLocaleString(
                        context,
                        'Usar padrao do sistema',
                        'Use system default',
                      ),
                    ),
                  ),
                ],
                const MachineStorageSettingsSection(),
                Text(
                  appLocaleString(context, 'Atualizações', 'Updates'),
                  style: FluentTheme.of(context).typography.subtitle,
                ),
                const SizedBox(height: 16),
                if (!autoUpdateProvider.isInitialized)
                  ListTile(
                    title: Text(
                      appLocaleString(
                        context,
                        'Atualizações automáticas',
                        'Automatic updates',
                      ),
                    ),
                    subtitle: Text(
                      appLocaleString(
                        context,
                        'Configure AUTO_UPDATE_FEED_URL no arquivo .env',
                        'Configure AUTO_UPDATE_FEED_URL in .env file',
                      ),
                    ),
                    trailing: const Icon(FluentIcons.info),
                  )
                else ...[
                  ListTile(
                    title: Text(
                      appLocaleString(
                        context,
                        'Verificar atualizações',
                        'Check for updates',
                      ),
                    ),
                    subtitle: Text(
                      autoUpdateProvider.lastCheckDate != null
                          ? appLocaleLastUpdateCheckSubtitle(
                              context,
                              autoUpdateProvider.lastCheckDate!,
                            )
                          : appLocaleString(
                              context,
                              'Nunca verificado',
                              'Never checked',
                            ),
                    ),
                    trailing: autoUpdateProvider.isChecking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: ProgressRing(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(FluentIcons.refresh),
                            onPressed: autoUpdateProvider.isChecking
                                ? null
                                : autoUpdateProvider.checkForUpdates,
                          ),
                  ),
                  if (autoUpdateProvider.error != null)
                    ListTile(
                      title: Text(
                        appLocaleString(context, 'Erro', 'Error'),
                      ),
                      subtitle: Text(
                        autoUpdateProvider.error!,
                        style: FluentTheme.of(context).typography.body
                            ?.copyWith(color: const Color(0xFFF44336)),
                      ),
                      trailing: IconButton(
                        icon: const Icon(FluentIcons.cancel),
                        onPressed: autoUpdateProvider.clearError,
                      ),
                    ),
                  if (autoUpdateProvider.updateAvailable)
                    ListTile(
                      title: Text(
                        appLocaleString(
                          context,
                          'Atualização disponível',
                          'Update available',
                        ),
                      ),
                      subtitle: Text(
                        appLocaleString(
                          context,
                          'Uma nova versão está disponível para download',
                          'A new version is available for download',
                        ),
                      ),
                      leading: const Icon(
                        FluentIcons.update_restore,
                        color: AppColors.primary,
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  appLocaleString(context, 'Sobre', 'About'),
                  style: FluentTheme.of(context).typography.subtitle,
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: Text(
                    appLocaleString(context, 'Versão', 'Version'),
                  ),
                  subtitle: _isLoadingVersion
                      ? Text(
                          appLocaleString(
                            context,
                            'Carregando...',
                            'Loading...',
                          ),
                        )
                      : Text(
                          _packageInfo != null
                              ? (_packageInfo!.buildNumber.isNotEmpty
                                    ? '${_packageInfo!.version}+${_packageInfo!.buildNumber}'
                                    : _packageInfo!.version)
                              : appLocaleString(
                                  context,
                                  'Desconhecida',
                                  'Unknown',
                                ),
                        ),
                ),
                ListTile(
                  title: Text(
                    appLocaleString(context, 'Licença', 'License'),
                  ),
                  subtitle: const Text('MIT License'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
