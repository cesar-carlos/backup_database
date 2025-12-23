import 'package:intl/intl.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../application/providers/license_provider.dart';
import '../../../domain/entities/license.dart';
import '../../widgets/common/common.dart';

class LicenseSettingsTab extends StatefulWidget {
  const LicenseSettingsTab({super.key});

  @override
  State<LicenseSettingsTab> createState() => _LicenseSettingsTabState();
}

class _LicenseSettingsTabState extends State<LicenseSettingsTab> {
  final _licenseKeyController = TextEditingController();
  final bool _isDeveloperMode = false;

  @override
  void dispose() {
    _licenseKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LicenseProvider>(
      builder: (context, licenseProvider, child) {
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
                      'Licenciamento',
                      style: FluentTheme.of(context).typography.subtitle,
                    ),
                    const SizedBox(height: 16),
                    InfoLabel(
                      label: 'Chave do Dispositivo',
                      child: TextBox(
                        readOnly: true,
                        controller: TextEditingController(
                          text: licenseProvider.deviceKey ?? 'Carregando...',
                        ),
                        suffix: IconButton(
                          icon: const Icon(FluentIcons.copy),
                          onPressed: licenseProvider.deviceKey != null
                              ? () {
                                  // TODO: Implementar cópia para clipboard
                                }
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    InfoLabel(
                      label: 'Chave de Licença',
                      child: TextBox(
                        controller: _licenseKeyController,
                        placeholder: 'Cole a chave de licença aqui',
                        enabled: !licenseProvider.isLoading,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Button(
                      onPressed: licenseProvider.isLoading
                          ? null
                          : () async {
                              final success = await licenseProvider
                                  .validateAndSaveLicense(
                                    _licenseKeyController.text.trim(),
                                  );
                              if (success && mounted) {
                                MessageModal.showSuccess(
                                  context,
                                  message:
                                      'Licença validada e salva com sucesso!',
                                );
                                _licenseKeyController.clear();
                              } else if (mounted) {
                                MessageModal.showError(
                                  context,
                                  message:
                                      licenseProvider.error ??
                                      'Erro ao validar licença',
                                );
                              }
                            },
                      child: licenseProvider.isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: ProgressRing(strokeWidth: 2),
                            )
                          : const Text('Validar Licença'),
                    ),
                    if (licenseProvider.error != null) ...[
                      const SizedBox(height: 16),
                      InfoLabel(
                        label: 'Erro',
                        child: Text(
                          licenseProvider.error!,
                          style: FluentTheme.of(context).typography.body
                              ?.copyWith(color: const Color(0xFFF44336)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    Text(
                      'Status da Licença',
                      style: FluentTheme.of(context).typography.subtitle,
                    ),
                    const SizedBox(height: 16),
                    _buildLicenseStatus(licenseProvider.currentLicense),
                    if (licenseProvider.currentLicense != null) ...[
                      const SizedBox(height: 16),
                      _buildLicenseDetails(licenseProvider.currentLicense!),
                    ],
                  ],
                ),
              ),
              if (_isDeveloperMode) ...[
                const SizedBox(height: 16),
                _buildDeveloperMode(context, licenseProvider),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildLicenseStatus(License? license) {
    if (license == null) {
      return ListTile(
        leading: const Icon(FluentIcons.cancel, color: Color(0xFFF44336)),
        title: const Text('Sem Licença'),
        subtitle: const Text('Nenhuma licença válida encontrada'),
      );
    }

    if (license.isExpired) {
      return ListTile(
        leading: const Icon(FluentIcons.warning, color: Color(0xFFFF9800)),
        title: const Text('Licença Expirada'),
        subtitle: Text(
          'Expirou em: ${DateFormat('dd/MM/yyyy HH:mm').format(license.expiresAt!)}',
        ),
      );
    }

    return ListTile(
      leading: const Icon(FluentIcons.accept, color: Color(0xFF4CAF50)),
      title: const Text('Licença Válida'),
      subtitle: Text(
        license.expiresAt != null
            ? 'Válida até: ${DateFormat('dd/MM/yyyy HH:mm').format(license.expiresAt!)}'
            : 'Licença permanente',
      ),
    );
  }

  Widget _buildLicenseDetails(License license) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recursos Permitidos',
          style: FluentTheme.of(context).typography.bodyStrong,
        ),
        const SizedBox(height: 8),
        ...license.allowedFeatures.map(
          (feature) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                const Icon(
                  FluentIcons.accept,
                  size: 16,
                  color: Color(0xFF4CAF50),
                ),
                const SizedBox(width: 8),
                Text(feature),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeveloperMode(
    BuildContext context,
    LicenseProvider licenseProvider,
  ) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Modo Desenvolvedor',
            style: FluentTheme.of(context).typography.subtitle,
          ),
          const SizedBox(height: 16),
          // TODO: Implementar gerador de licenças
          const Text('Gerador de licenças será implementado aqui'),
        ],
      ),
    );
  }
}
