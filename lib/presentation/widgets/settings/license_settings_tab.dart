import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/utils/clipboard_service.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

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

  String _t(String pt, String en) {
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
    return isPt ? pt : en;
  }

  String _getFeatureLabel(String feature) {
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
    if (!isPt) return feature;

    final labels = {
      LicenseFeatures.differentialBackup: 'Backup diferencial',
      LicenseFeatures.logBackup: 'Backup de logs',
      LicenseFeatures.intervalSchedule: 'Agendamento por interval',
      LicenseFeatures.remoteControl: 'Controle remoto',
      LicenseFeatures.serverConnection: 'Conexão ao servidor',
      LicenseFeatures.googleDrive: 'Google Drive',
      LicenseFeatures.dropbox: 'Dropbox',
      LicenseFeatures.nextcloud: 'Nextcloud',
      LicenseFeatures.verifyIntegrity: 'Verificação de integridade',
      LicenseFeatures.checksum: 'Verificação de checksum',
      LicenseFeatures.postBackupScript: 'Script pós-backup',
      LicenseFeatures.emailNotification: 'Notificação por e-mail',
    };
    return labels[feature] ?? feature;
  }

  DateTime? _tryParseDate(String value) {
    if (value.isEmpty) return null;

    final parts = value.split('/');
    if (parts.length != 3) return null;

    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);

    if (day == null || month == null || year == null) return null;
    if (day < 1 || day > 31) return null;
    if (month < 1 || month > 12) return null;
    if (year < 2024 || year > 2100) return null;

    try {
      return DateTime(year, month, day);
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LicenseProvider>(
      builder: (_, licenseProvider, child) {
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
                      _t('Licenciamento', 'Licensing'),
                      style: FluentTheme.of(context).typography.subtitle,
                    ),
                    const SizedBox(height: 16),
                    InfoLabel(
                      label: _t('Chave do dispositivo', 'Device key'),
                      child: TextBox(
                        readOnly: true,
                        controller: TextEditingController(
                          text:
                              licenseProvider.deviceKey ??
                              _t('Carregando...', 'Loading...'),
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
                                      if (mounted) {
                                        MessageModal.showSuccess(
                                          this.context,
                                          message: _t(
                                            'Chave do dispositivo copiada para clipboard!',
                                            'Device key copied to clipboard!',
                                          ),
                                        );
                                      }
                                    } else {
                                      if (mounted) {
                                        MessageModal.showError(
                                          this.context,
                                          message: _t(
                                            'Erro ao copiar para clipboard',
                                            'Error copying to clipboard',
                                          ),
                                        );
                                      }
                                    }
                                  }
                                }
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    InfoLabel(
                      label: _t('Chave de licença', 'License key'),
                      child: TextBox(
                        controller: _licenseKeyController,
                        placeholder: _t(
                          'Cole a chave de licença aqui',
                          'Paste the license key here',
                        ),
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
                                  this.context,
                                  message: _t(
                                    'Licença validada e salva com sucesso!',
                                    'License validated and saved successfully!',
                                  ),
                                );
                                _licenseKeyController.clear();
                              } else if (mounted) {
                                MessageModal.showError(
                                  this.context,
                                  message:
                                      licenseProvider.error ??
                                      _t(
                                        'Erro ao validar licença',
                                        'Error validating license',
                                      ),
                                );
                              }
                            },
                      child: licenseProvider.isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: ProgressRing(strokeWidth: 2),
                            )
                          : Text(_t('Validar licenca', 'Validate license')),
                    ),
                    if (licenseProvider.error != null) ...[
                      const SizedBox(height: 16),
                      InfoLabel(
                        label: _t('Erro', 'Error'),
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
                      _t('Status da licença', 'License status'),
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
        title: Text(_t('Sem licença', 'No license')),
        subtitle: Text(
          _t('Nenhuma licença válida encontrada', 'No valid license found'),
        ),
      );
    }

    if (license.isExpired) {
      return ListTile(
        leading: const Icon(FluentIcons.warning, color: Color(0xFFFF9800)),
        title: Text(_t('Licença expirada', 'Expired license')),
        subtitle: Text(
          _t(
            'Expirou em: ${DateFormat('dd/MM/yyyy HH:mm').format(license.expiresAt!)}',
            'Expired on: ${DateFormat('dd/MM/yyyy HH:mm').format(license.expiresAt!)}',
          ),
        ),
      );
    }

    return ListTile(
      leading: const Icon(FluentIcons.accept, color: Color(0xFF4CAF50)),
      title: Text(_t('Licença válida', 'Valid license')),
      subtitle: Text(
        license.expiresAt != null
            ? _t(
                'Válida até: ${DateFormat('dd/MM/yyyy HH:mm').format(license.expiresAt!)}',
                'Valid until: ${DateFormat('dd/MM/yyyy HH:mm').format(license.expiresAt!)}',
              )
            : _t('Licença permanente', 'Permanent license'),
      ),
    );
  }

  Widget _buildLicenseDetails(License license) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('Recursos permitidos', 'Allowed features'),
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
                _t('Gerador de licenças', 'License generator'),
                style: FluentTheme.of(context).typography.subtitle,
              ),
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: _isAuthenticatedNotifier,
                builder: (context, isAuthenticated, child) {
                  if (!isAuthenticated) {
                    return Button(
                      onPressed: () => _showAuthDialog(context),
                      child: Text(_t('Acessar gerador', 'Open generator')),
                    );
                  }
                  return Button(
                    onPressed: () =>
                        _showGeneratorDialog(context, licenseProvider),
                    child: Text(_t('Gerar licença', 'Generate license')),
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
          title: Row(
            children: [
              const Icon(FluentIcons.lock),
              const SizedBox(width: 8),
              Text(_t('Autenticação', 'Authentication')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(
                  'Digite a senha de administrador para acessar o gerador de licenças:',
                  'Enter admin password to access license generator:',
                ),
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: passwordController,
                hint: _t('Digite a senha', 'Enter password'),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 16),
                InfoBar(
                  severity: InfoBarSeverity.error,
                  title: Text(_t('Erro', 'Error')),
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
                    errorMessage = _t(
                      'Senha não pode estar vazia',
                      'Password cannot be empty',
                    );
                  });
                  return;
                }

                if (enteredPassword == adminPassword) {
                  passwordController.dispose();
                  Navigator.pop(dialogContext);
                  _isAuthenticatedNotifier.value = true;
                } else {
                  setState(() {
                    errorMessage = _t('Senha incorreta', 'Incorrect password');
                  });
                }
              },
              child: Text(_t('Entrar', 'Sign in')),
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
    var isLoading = false;
    String? errorMessage;
    String? dateError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) => ContentDialog(
            title: Row(
              children: [
                const Icon(FluentIcons.certificate),
                const SizedBox(width: 8),
                Text(_t('Gerador de licença', 'License generator')),
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
                        label: _t('Chave do dispositivo', 'Device key'),
                        child: TextBox(
                          controller: deviceKeyController,
                          placeholder: _t(
                            'Digite a chave do dispositivo para gerar a licença',
                            'Enter device key to generate the license',
                          ),
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
                            child: Text(
                              _t('Usar chave atual', 'Use current key'),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        _t('Recursos permitidos', 'Allowed features'),
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
                                      if (value ?? false) {
                                        selectedFeatures.add(feature);
                                      } else {
                                        selectedFeatures.remove(feature);
                                      }
                                    });
                                  },
                            content: Text(_getFeatureLabel(feature)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      InfoLabel(
                        label: _t(
                          'Data de expiração (opcional)',
                          'Expiration date (optional)',
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextBox(
                                controller: expiresAtController,
                                placeholder: _t(
                                  'DD/MM/YYYY ou deixe vazio para licença permanente',
                                  'DD/MM/YYYY or leave empty for permanent license',
                                ),
                                enabled: !isLoading,
                                onChanged: isLoading
                                    ? null
                                    : (value) {
                                        if (value.isEmpty) {
                                          setDialogState(() {
                                            dateError = null;
                                          });
                                          return;
                                        }
                                        final parsedDate = _tryParseDate(value);
                                        if (parsedDate == null) {
                                          setDialogState(() {
                                            dateError = _t(
                                              'Data inválida. Use o formato DD/MM/YYYY',
                                              'Invalid date. Use format DD/MM/YYYY',
                                            );
                                          });
                                        } else {
                                          setDialogState(() {
                                            dateError = null;
                                            selectedExpiresAt = parsedDate;
                                          });
                                        }
                                      },
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
                      if (dateError != null) ...[
                        const SizedBox(height: 16),
                        InfoBar(
                          severity: InfoBarSeverity.error,
                          title: Text(_t('Erro', 'Error')),
                          content: Text(dateError!),
                        ),
                      ],
                      if (errorMessage != null) ...[
                        const SizedBox(height: 16),
                        InfoBar(
                          severity: InfoBarSeverity.error,
                          title: Text(_t('Erro', 'Error')),
                          content: Text(errorMessage!),
                        ),
                      ],
                      if (generatedLicenseController.text.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        InfoLabel(
                          label: _t('Licença gerada', 'Generated license'),
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
                            if (!mounted) return;
                            if (success) {
                              setDialogState(() {
                                errorMessage = null;
                              });
                              MessageModal.showSuccess(
                                this.context,
                                message: _t(
                                  'Licença copiada para clipboard!',
                                  'License copied to clipboard!',
                                ),
                              );
                            } else {
                              setDialogState(() {
                                errorMessage = _t(
                                  'Erro ao copiar para clipboard',
                                  'Error copying to clipboard',
                                );
                              });
                            }
                          },
                          child: Text(_t('Copiar licença', 'Copy license')),
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
                    : () => Navigator.pop(dialogContext),
              ),
              Button(
                onPressed: isLoading
                    ? null
                    : () async {
                        final deviceKey = deviceKeyController.text.trim();

                        if (deviceKey.isEmpty) {
                          setDialogState(() {
                            errorMessage = _t(
                              'Chave do dispositivo é obrigatória',
                              'Device key is required',
                            );
                          });
                          return;
                        }

                        if (selectedFeatures.isEmpty) {
                          setDialogState(() {
                            errorMessage = _t(
                              'Selecione pelo menos um recurso',
                              'Select at least one feature',
                            );
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
                                _t(
                                  'Erro ao gerar licença',
                                  'Error generating license',
                                );
                          }
                        });
                      },
                child: isLoading
                    ? const ProgressRing(strokeWidth: 2)
                    : Text(_t('Gerar licença', 'Generate license')),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      deviceKeyController.dispose();
      generatedLicenseController.dispose();
      expiresAtController.dispose();
    });
  }
}
