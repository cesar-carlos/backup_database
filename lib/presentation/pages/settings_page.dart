import 'package:intl/intl.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../application/providers/auto_update_provider.dart';
import '../widgets/common/common.dart';
import '../providers/providers.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  PackageInfo? _packageInfo;
  bool _isLoadingVersion = true;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingVersion = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final systemSettings = Provider.of<SystemSettingsProvider>(context);
    final autoUpdateProvider = Provider.of<AutoUpdateProvider>(context);

    return ScaffoldPage(
      header: const PageHeader(title: Text('Configurações Gerais')),
      content: SingleChildScrollView(
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
                      onChanged: (value) {
                        themeProvider.setDarkMode(value);
                      },
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
                      onChanged: (value) {
                        systemSettings.setStartWithWindows(value);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  InfoLabel(
                    label: 'Iniciar Minimizado',
                    child: ToggleSwitch(
                      checked: systemSettings.startMinimized,
                      onChanged: (value) {
                        systemSettings.setStartMinimized(value);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  InfoLabel(
                    label: 'Minimizar para bandeja',
                    child: ToggleSwitch(
                      checked: systemSettings.minimizeToTray,
                      onChanged: (value) {
                        systemSettings.setMinimizeToTray(value);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  InfoLabel(
                    label: 'Fechar para bandeja',
                    child: ToggleSwitch(
                      checked: systemSettings.closeToTray,
                      onChanged: (value) {
                        systemSettings.setCloseToTray(value);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    'Atualizações',
                    style: FluentTheme.of(context).typography.subtitle,
                  ),
                  const SizedBox(height: 16),
                  if (!autoUpdateProvider.isInitialized)
                    ListTile(
                      title: const Text('Atualizações Automáticas'),
                      subtitle: const Text(
                        'Configure AUTO_UPDATE_FEED_URL no arquivo .env',
                      ),
                      trailing: const Icon(FluentIcons.info),
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
                                  : () => autoUpdateProvider.checkForUpdates(),
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
                          onPressed: () => autoUpdateProvider.clearError(),
                        ),
                      ),
                    if (autoUpdateProvider.updateAvailable)
                      ListTile(
                        title: const Text('Atualização Disponível'),
                        subtitle: const Text(
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
      ),
    );
  }
}
