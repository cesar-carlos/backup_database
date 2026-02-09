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
      dialogTitle: 'Selecionar Pasta Temporária de Downloads',
    );
    if (result != null && mounted) {
      setState(() => _isLoadingTempPath = true);
      final success = await _tempService.setCustomTempPath(result);
      if (mounted) {
        setState(() => _isLoadingTempPath = false);
        if (!success) {
          MessageModal.showError(
            context,
            message:
                'Não foi possível definir a pasta temporária. '
                'Verifique se tem permissão de escrita.',
          );
          return;
        }
        await _loadTempPath();
        MessageModal.showSuccess(
          context,
          message: 'Pasta temporária alterada com sucesso!',
        );
      }
    }
  }

  Future<void> _resetTempPath() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Confirmar'),
        content: const Text(
          'Deseja voltar a usar a pasta temporária padrão do sistema?',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
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
                  'Aparência',
                  style: FluentTheme.of(context).typography.subtitle,
                ),
                const SizedBox(height: 16),
                InfoLabel(
                  label: 'Tema Escuro',
                  child: ToggleSwitch(
                    checked: themeProvider.isDarkMode,
                    onChanged: themeProvider.setDarkMode,
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  'Sistema',
                  style: FluentTheme.of(context).typography.subtitle,
                ),
                const SizedBox(height: 16),
                InfoLabel(
                  label: 'Iniciar com o Windows',
                  child: ToggleSwitch(
                    checked: systemSettings.startWithWindows,
                    onChanged: systemSettings.setStartWithWindows,
                  ),
                ),
                const SizedBox(height: 16),
                InfoLabel(
                  label: 'Iniciar Minimizado',
                  child: ToggleSwitch(
                    checked: systemSettings.startMinimized,
                    onChanged: systemSettings.setStartMinimized,
                  ),
                ),
                const SizedBox(height: 16),
                InfoLabel(
                  label: 'Minimizar para bandeja',
                  child: ToggleSwitch(
                    checked: systemSettings.minimizeToTray,
                    onChanged: systemSettings.setMinimizeToTray,
                  ),
                ),
                const SizedBox(height: 16),
                InfoLabel(
                  label: 'Fechar para bandeja',
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
                    'Pasta Temporária de Downloads (Cliente)',
                    style: FluentTheme.of(context).typography.subtitle,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Arquivos baixados do servidor são salvos temporariamente aqui '
                    'antes de serem enviados para os destinos finais.',
                    style: FluentTheme.of(context).typography.caption,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('Pasta Atual'),
                    subtitle: _isLoadingTempPath
                        ? const Text('Carregando...')
                        : Text(_tempDownloadsPath ?? 'Desconhecida'),
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
                    child: const Text('Alterar Pasta'),
                  ),
                  const SizedBox(height: 8),
                  Button(
                    onPressed: _resetTempPath,
                    child: const Text('Usar Padrão do Sistema'),
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  'Atualizações',
                  style: FluentTheme.of(context).typography.subtitle,
                ),
                const SizedBox(height: 16),
                if (!autoUpdateProvider.isInitialized)
                  const ListTile(
                    title: Text('Atualizações Automáticas'),
                    subtitle: Text(
                      'Configure AUTO_UPDATE_FEED_URL no arquivo .env',
                    ),
                    trailing: Icon(FluentIcons.info),
                  )
                else ...[
                  ListTile(
                    title: const Text('Verificar Atualizações'),
                    subtitle: Text(
                      autoUpdateProvider.lastCheckDate != null
                          ? 'Última verificação: ${DateFormat('dd/MM/yyyy HH:mm').format(autoUpdateProvider.lastCheckDate!)}'
                          : 'Nunca verificado',
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
                      title: const Text('Erro'),
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
                    const ListTile(
                      title: Text('Atualização Disponível'),
                      subtitle: Text(
                        'Uma nova versão está disponível para download',
                      ),
                      leading: Icon(
                        FluentIcons.update_restore,
                        color: AppColors.primary,
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  'Sobre',
                  style: FluentTheme.of(context).typography.subtitle,
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Versão'),
                  subtitle: _isLoadingVersion
                      ? const Text('Carregando...')
                      : Text(
                          _packageInfo != null
                              ? '${_packageInfo!.version}+${_packageInfo!.buildNumber}'
                              : 'Desconhecida',
                        ),
                ),
                const ListTile(
                  title: Text('Licença'),
                  subtitle: Text('MIT License'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
