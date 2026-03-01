import 'package:backup_database/application/providers/auto_update_provider.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/services/temp_directory_service.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/core/theme/theme_provider.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/presentation/providers/providers.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
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

  String _t(String pt, String en) {
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
    return isPt ? pt : en;
  }

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
      LoggerService.warning('Erro ao carregar informacoes do pacote', e, s);
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
      LoggerService.warning('Erro ao carregar pasta temporaria', e, s);
      if (mounted) {
        setState(() => _isLoadingTempPath = false);
      }
    }
  }

  Future<void> _changeTempPath() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: _t(
        'Selecionar pasta temporaria de downloads',
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
            message: _t(
              'Nao foi possivel definir a pasta temporaria. Verifique se tem permissao de escrita.',
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
          message: _t(
            'Pasta temporaria alterada com sucesso!',
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
        title: Text(_t('Confirmar', 'Confirm')),
        content: Text(
          _t(
            'Deseja voltar a usar a pasta temporaria padrao do sistema?',
            'Do you want to use the system default temporary folder again?',
          ),
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('Cancelar', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('Confirmar', 'Confirm')),
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
                  _t('Aparencia', 'Appearance'),
                  style: FluentTheme.of(context).typography.subtitle,
                ),
                const SizedBox(height: 16),
                InfoLabel(
                  label: _t('Tema escuro', 'Dark theme'),
                  child: ToggleSwitch(
                    checked: themeProvider.isDarkMode,
                    onChanged: themeProvider.setDarkMode,
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  _t('Sistema', 'System'),
                  style: FluentTheme.of(context).typography.subtitle,
                ),
                const SizedBox(height: 16),
                InfoLabel(
                  label: _t('Iniciar com o Windows', 'Start with Windows'),
                  child: ToggleSwitch(
                    checked: systemSettings.startWithWindows,
                    onChanged: systemSettings.setStartWithWindows,
                  ),
                ),
                const SizedBox(height: 16),
                InfoLabel(
                  label: _t('Iniciar minimizado', 'Start minimized'),
                  child: ToggleSwitch(
                    checked: systemSettings.startMinimized,
                    onChanged: systemSettings.setStartMinimized,
                  ),
                ),
                const SizedBox(height: 16),
                InfoLabel(
                  label: _t('Minimizar para bandeja', 'Minimize to tray'),
                  child: ToggleSwitch(
                    checked: systemSettings.minimizeToTray,
                    onChanged: systemSettings.setMinimizeToTray,
                  ),
                ),
                const SizedBox(height: 16),
                InfoLabel(
                  label: _t('Fechar para bandeja', 'Close to tray'),
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
                    _t(
                      'Pasta temporaria de downloads (cliente)',
                      'Temporary downloads folder (client)',
                    ),
                    style: FluentTheme.of(context).typography.subtitle,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _t(
                      'Arquivos baixados do servidor sao salvos temporariamente aqui antes de serem enviados para os destinos finais.',
                      'Files downloaded from server are saved here temporarily before being sent to final destinations.',
                    ),
                    style: FluentTheme.of(context).typography.caption,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: Text(_t('Pasta atual', 'Current folder')),
                    subtitle: _isLoadingTempPath
                        ? Text(_t('Carregando...', 'Loading...'))
                        : Text(
                            _tempDownloadsPath ?? _t('Desconhecida', 'Unknown'),
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
                    child: Text(_t('Alterar pasta', 'Change folder')),
                  ),
                  const SizedBox(height: 8),
                  Button(
                    onPressed: _resetTempPath,
                    child: Text(
                      _t(
                        'Usar padrao do sistema',
                        'Use system default',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  _t('Atualizacoes', 'Updates'),
                  style: FluentTheme.of(context).typography.subtitle,
                ),
                const SizedBox(height: 16),
                if (!autoUpdateProvider.isInitialized)
                  ListTile(
                    title: Text(
                      _t('Atualizacoes automaticas', 'Automatic updates'),
                    ),
                    subtitle: Text(
                      _t(
                        'Configure AUTO_UPDATE_FEED_URL no arquivo .env',
                        'Configure AUTO_UPDATE_FEED_URL in .env file',
                      ),
                    ),
                    trailing: const Icon(FluentIcons.info),
                  )
                else ...[
                  ListTile(
                    title: Text(
                      _t('Verificar atualizacoes', 'Check for updates'),
                    ),
                    subtitle: Text(
                      autoUpdateProvider.lastCheckDate != null
                          ? _t(
                              'Última verificação: ${DateFormat('dd/MM/yyyy HH:mm').format(autoUpdateProvider.lastCheckDate!)}',
                              'Last check: ${DateFormat('dd/MM/yyyy HH:mm').format(autoUpdateProvider.lastCheckDate!)}',
                            )
                          : _t('Nunca verificado', 'Never checked'),
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
                      title: Text(_t('Erro', 'Error')),
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
                        _t('Atualizacao disponivel', 'Update available'),
                      ),
                      subtitle: Text(
                        _t(
                          'Uma nova versao esta disponivel para download',
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
                  _t('Sobre', 'About'),
                  style: FluentTheme.of(context).typography.subtitle,
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: Text(_t('Versao', 'Version')),
                  subtitle: _isLoadingVersion
                      ? Text(_t('Carregando...', 'Loading...'))
                      : Text(
                          _packageInfo != null
                              ? (_packageInfo!.buildNumber.isNotEmpty
                                    ? '${_packageInfo!.version}+${_packageInfo!.buildNumber}'
                                    : _packageInfo!.version)
                              : _t('Desconhecida', 'Unknown'),
                        ),
                ),
                ListTile(
                  title: Text(_t('Licença', 'License')),
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
