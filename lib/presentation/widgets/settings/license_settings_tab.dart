import 'package:flutter/foundation.dart';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../application/providers/license_provider.dart';
import '../../../core/constants/license_features.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/clipboard_service.dart';
import '../../../domain/entities/license.dart';
import '../../widgets/common/common.dart';

class LicenseSettingsTab extends StatefulWidget {
  const LicenseSettingsTab({super.key});

  @override
  State<LicenseSettingsTab> createState() => _LicenseSettingsTabState();
}

class _LicenseSettingsTabState extends State<LicenseSettingsTab> {
  final _licenseKeyController = TextEditingController();
  late final ClipboardService _clipboardService;
  final ValueNotifier<bool> _isAuthenticatedNotifier = ValueNotifier<bool>(
    false,
  );

  @override
  void initState() {
    super.initState();
    _clipboardService = getIt<ClipboardService>();
  }

  @override
  void dispose() {
    _licenseKeyController.dispose();
    _isAuthenticatedNotifier.dispose();
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
                              ? () async {
                                  final success = await _clipboardService
                                      .copyToClipboard(
                                        licenseProvider.deviceKey!,
                                      );
                                  if (mounted) {
                                    if (success) {
                                      MessageModal.showSuccess(
                                        context,
                                        message:
                                            'Chave do dispositivo copiada para clipboard!',
                                      );
                                    } else {
                                      MessageModal.showError(
                                        context,
                                        message:
                                            'Erro ao copiar para clipboard',
                                      );
                                    }
                                  }
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
              if (kDebugMode) ...[
                const SizedBox(height: 16),
                _buildLicenseGenerator(context, licenseProvider),
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

  Widget _buildLicenseGenerator(
    BuildContext context,
    LicenseProvider licenseProvider,
  ) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Gerador de Licenças',
                style: FluentTheme.of(context).typography.subtitle,
              ),
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: _isAuthenticatedNotifier,
                builder: (context, isAuthenticated, child) {
                  if (!isAuthenticated)
                    return Button(
                      onPressed: () => _showAuthDialog(context),
                      child: const Text('Acessar Gerador'),
                    );
                  return Button(
                    onPressed: () =>
                        _showGeneratorDialog(context, licenseProvider),
                    child: const Text('Gerar Licença'),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showAuthDialog(BuildContext context) async {
    final passwordController = TextEditingController();
    String? errorMessage;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => ContentDialog(
          title: const Row(
            children: [
              Icon(FluentIcons.lock),
              SizedBox(width: 8),
              Text('Autenticação'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Digite a senha de administrador para acessar o gerador de licenças:',
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: passwordController,
                label: 'Senha',
                hint: 'Digite a senha',
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 16),
                InfoBar(
                  severity: InfoBarSeverity.error,
                  title: const Text('Erro'),
                  content: Text(errorMessage!),
                ),
              ],
            ],
          ),
          actions: [
            CancelButton(
              onPressed: () {
                passwordController.dispose();
                Navigator.pop(dialogContext);
              },
            ),
            Button(
              onPressed: () {
                final adminPassword =
                    dotenv.env['LICENSE_ADMIN_PASSWORD'] ?? '';
                final enteredPassword = passwordController.text.trim();

                if (enteredPassword.isEmpty) {
                  setState(() {
                    errorMessage = 'Senha não pode estar vazia';
                  });
                  return;
                }

                if (enteredPassword == adminPassword) {
                  passwordController.dispose();
                  Navigator.pop(dialogContext);
                  _isAuthenticatedNotifier.value = true;
                } else {
                  setState(() {
                    errorMessage = 'Senha incorreta';
                  });
                }
              },
              child: const Text('Entrar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showGeneratorDialog(
    BuildContext context,
    LicenseProvider licenseProvider,
  ) async {
    if (!mounted) return;

    final deviceKeyController = TextEditingController();
    final generatedLicenseController = TextEditingController();
    final expiresAtController = TextEditingController();
    DateTime? selectedExpiresAt;
    final selectedFeatures = <String>{};
    bool isLoading = false;
    String? errorMessage;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) => ContentDialog(
            title: const Row(
              children: [
                Icon(FluentIcons.certificate),
                SizedBox(width: 8),
                Text('Gerador de Licença'),
              ],
            ),
            content: SizedBox(
              width: 650,
              child: SingleChildScrollView(
                child: Form(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InfoLabel(
                        label: 'Chave do Dispositivo',
                        child: TextBox(
                          controller: deviceKeyController,
                          placeholder:
                              'Digite a chave do dispositivo para gerar a licença',
                          enabled: !isLoading,
                        ),
                      ),
                      if (licenseProvider.deviceKey != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Button(
                            onPressed: isLoading
                                ? null
                                : () {
                                    setDialogState(() {
                                      deviceKeyController.text =
                                          licenseProvider.deviceKey!;
                                    });
                                  },
                            child: const Text('Usar Chave Atual'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'Recursos Permitidos',
                        style: FluentTheme.of(ctx).typography.bodyStrong,
                      ),
                      const SizedBox(height: 8),
                      ...LicenseFeatures.allFeatures.map(
                        (feature) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Checkbox(
                            checked: selectedFeatures.contains(feature),
                            onChanged: isLoading
                                ? null
                                : (value) {
                                    setDialogState(() {
                                      if (value == true) {
                                        selectedFeatures.add(feature);
                                      } else {
                                        selectedFeatures.remove(feature);
                                      }
                                    });
                                  },
                            content: Text(feature),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      InfoLabel(
                        label: 'Data de Expiração (opcional)',
                        child: Row(
                          children: [
                            Expanded(
                              child: TextBox(
                                controller: expiresAtController,
                                placeholder:
                                    'DD/MM/YYYY ou deixe vazio para licença permanente',
                                enabled: !isLoading,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Button(
                              onPressed: isLoading
                                  ? null
                                  : () {
                                      final now = DateTime.now();
                                      final defaultDate =
                                          selectedExpiresAt ??
                                          DateTime(
                                            now.year,
                                            now.month,
                                            now.day,
                                          ).add(const Duration(days: 30));
                                      setDialogState(() {
                                        selectedExpiresAt = defaultDate;
                                        expiresAtController.text = DateFormat(
                                          'dd/MM/yyyy',
                                        ).format(defaultDate);
                                      });
                                    },
                              child: const Icon(FluentIcons.calendar),
                            ),
                          ],
                        ),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 16),
                        InfoBar(
                          severity: InfoBarSeverity.error,
                          title: const Text('Erro'),
                          content: Text(errorMessage!),
                        ),
                      ],
                      if (generatedLicenseController.text.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        InfoLabel(
                          label: 'Licença Gerada',
                          child: TextBox(
                            controller: generatedLicenseController,
                            maxLines: 5,
                            readOnly: true,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Button(
                          onPressed: () async {
                            final success = await _clipboardService
                                .copyToClipboard(
                                  generatedLicenseController.text,
                                );
                            if (success) {
                              setDialogState(() {
                                errorMessage = null;
                              });
                              MessageModal.showSuccess(
                                ctx,
                                message: 'Licença copiada para clipboard!',
                              );
                            } else {
                              setDialogState(() {
                                errorMessage = 'Erro ao copiar para clipboard';
                              });
                            }
                          },
                          child: const Text('Copiar Licença'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              CancelButton(
                onPressed: isLoading
                    ? null
                    : () {
                        Navigator.pop(dialogContext);
                        deviceKeyController.dispose();
                        generatedLicenseController.dispose();
                        expiresAtController.dispose();
                      },
              ),
              Button(
                onPressed: isLoading
                    ? null
                    : () async {
                        final deviceKey = deviceKeyController.text.trim();

                        if (deviceKey.isEmpty) {
                          setDialogState(() {
                            errorMessage = 'Chave do dispositivo é obrigatória';
                          });
                          return;
                        }

                        if (selectedFeatures.isEmpty) {
                          setDialogState(() {
                            errorMessage = 'Selecione pelo menos um recurso';
                          });
                          return;
                        }

                        setDialogState(() {
                          isLoading = true;
                          errorMessage = null;
                        });

                        final licenseKey = await licenseProvider
                            .generateLicense(
                              deviceKey: deviceKey,
                              expiresAt: selectedExpiresAt,
                              allowedFeatures: selectedFeatures.toList(),
                            );

                        setDialogState(() {
                          isLoading = false;
                          if (licenseKey != null) {
                            generatedLicenseController.text = licenseKey;
                            errorMessage = null;
                          } else {
                            errorMessage =
                                licenseProvider.error ??
                                'Erro ao gerar licença';
                          }
                        });
                      },
                child: isLoading
                    ? const ProgressRing(strokeWidth: 2)
                    : const Text('Gerar Licença'),
              ),
            ],
          ),
        );
      },
    );
  }
}
