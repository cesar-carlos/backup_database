import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_provider.dart';
import '../providers/providers.dart';
import '../widgets/common/common.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final systemSettings = Provider.of<SystemSettingsProvider>(context);

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
                  Text('Sobre', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  const ListTile(
                    title: Text('Versão'),
                    subtitle: Text('1.0.0'),
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
