import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_provider.dart';
import '../../application/providers/auto_update_provider.dart';
import '../providers/providers.dart';
import '../widgets/common/common.dart';

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

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configurações Gerais',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aparência',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Tema Escuro'),
                    subtitle: const Text('Ativar modo escuro'),
                    value: themeProvider.isDarkMode,
                    onChanged: (value) {
                      themeProvider.setDarkMode(value);
                    },
                  ),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    'Sistema',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Iniciar com o Windows'),
                    subtitle: const Text(
                      'Iniciar aplicativo ao ligar o computador',
                    ),
                    value: systemSettings.startWithWindows,
                    onChanged: (value) {
                      systemSettings.setStartWithWindows(value);
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Iniciar Minimizado'),
                    subtitle: const Text(
                      'Iniciar aplicativo minimizado na bandeja',
                    ),
                    value: systemSettings.startMinimized,
                    onChanged: (value) {
                      systemSettings.setStartMinimized(value);
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Minimizar para bandeja'),
                    subtitle: const Text(
                      'Minimizar para a bandeja ao invés da barra de tarefas',
                    ),
                    value: systemSettings.minimizeToTray,
                    onChanged: (value) {
                      systemSettings.setMinimizeToTray(value);
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Fechar para bandeja'),
                    subtitle: const Text(
                      'Fechar para a bandeja ao invés de sair',
                    ),
                    value: systemSettings.closeToTray,
                    onChanged: (value) {
                      systemSettings.setCloseToTray(value);
                    },
                  ),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    'Atualizações',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  if (!autoUpdateProvider.isInitialized)
                    ListTile(
                      title: const Text('Atualizações Automáticas'),
                      subtitle: const Text(
                        'Configure AUTO_UPDATE_FEED_URL no arquivo .env',
                      ),
                      trailing: const Icon(Icons.info_outline),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: autoUpdateProvider.isChecking
                                  ? null
                                  : () => autoUpdateProvider.checkForUpdates(),
                              tooltip: 'Verificar atualizações',
                            ),
                    ),
                    if (autoUpdateProvider.error != null)
                      ListTile(
                        title: const Text('Erro'),
                        subtitle: Text(
                          autoUpdateProvider.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
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
                          Icons.system_update,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                  ],
                  const Divider(),
                  const SizedBox(height: 16),
                  Text('Sobre', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('Versão'),
                    subtitle: _isLoadingVersion
                        ? const Text('Carregando...')
                        : Text(
                            _packageInfo?.version ?? 'Desconhecida',
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
