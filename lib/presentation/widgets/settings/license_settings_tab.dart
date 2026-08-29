import 'dart:async';

import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/application/services/admin_password_verifier.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/core/utils/clipboard_service.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/settings_ui.dart';
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

  /// Verificador de senha admin com hash + lockout. Mantido no `State`
  /// para que o contador de falhas e o lockout persistam entre
  /// reaberturas do diálogo (sem reset trivial).
  final AdminPasswordVerifier _adminVerifier = AdminPasswordVerifier();

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

  Future<void> _copyDeviceKey(String deviceKey) async {
    final success = await _clipboardService.copyToClipboard(deviceKey);
    if (!mounted) {
      return;
    }
    if (success) {
      unawaited(
        FluentInfoBarFeedback.showSuccess(
          context,
          message: appLocaleString(
            context,
            'Chave do dispositivo copiada para clipboard!',
            'Device key copied to clipboard!',
          ),
        ),
      );
      return;
    }
    unawaited(
      MessageModal.showError(
        context,
        message: appLocaleString(
          context,
          'Erro ao copiar para clipboard',
          'Error copying to clipboard',
        ),
      ),
    );
  }

  Future<void> _validateLicense(LicenseProvider licenseProvider) async {
    final success = await licenseProvider.validateAndSaveLicense(
      _licenseKeyController.text.trim(),
    );
    if (!mounted) {
      return;
    }
    if (success) {
      unawaited(
        FluentInfoBarFeedback.showSuccess(
          context,
          message: appLocaleString(
            context,
            'Licença validada e salva com sucesso!',
            'License validated and saved successfully!',
          ),
        ),
      );
      _licenseKeyController.clear();
      return;
    }
    unawaited(
      MessageModal.showError(
        context,
        message:
            licenseProvider.error ??
            appLocaleString(
              context,
              'Erro ao validar licença',
              'Error validating license',
            ),
      ),
    );
  }

  /// Devolve `null` quando `result` é sucesso, ou a mensagem localizada
  /// para exibir como erro caso contrário.
  String? _localizeAdminVerification(VerificationResult result) {
    if (result.isSuccess) return null;
    if (result.isNotConfigured) {
      return appLocaleString(
        context,
        'Gerador desabilitado: LICENSE_ADMIN_PASSWORD_HASH não configurada '
            'no .env externo.',
        'Generator disabled: LICENSE_ADMIN_PASSWORD_HASH not configured '
            'in external .env.',
      );
    }
    if (result.isLockedOut) {
      return appLocaleString(
        context,
        'Bloqueado por excesso de tentativas. Aguarde alguns segundos.',
        'Locked out due to repeated failures. Wait a few seconds.',
      );
    }
    return appLocaleString(context, 'Senha incorreta', 'Incorrect password');
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
          padding: AppSpacing.paddingLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSectionCard(
                title: appLocaleString(context, 'Licenciamento', 'Licensing'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SettingsTechnicalItem(
                      title: appLocaleString(
                        context,
                        'Chave do dispositivo',
                        'Device key',
                      ),
                      value:
                          licenseProvider.deviceKey ??
                          appLocaleString(
                            context,
                            'Carregando...',
                            'Loading...',
                          ),
                      onCopy: licenseProvider.deviceKey == null
                          ? null
                          : () => unawaited(
                              _copyDeviceKey(licenseProvider.deviceKey!),
                            ),
                    ),
                    AppSpacing.gapMd,
                    AppTextField(
                      label: appLocaleString(
                        context,
                        'Chave de licença',
                        'License key',
                      ),
                      controller: _licenseKeyController,
                      hint: appLocaleString(
                        context,
                        'Cole a chave de licença aqui',
                        'Paste the license key here',
                      ),
                      enabled: !licenseProvider.isLoading,
                    ),
                    AppSpacing.gapMd,
                    AppButton.primary(
                      label: appLocaleString(
                        context,
                        'Validar licença',
                        'Validate license',
                      ),
                      isLoading: licenseProvider.isLoading,
                      onPressed: () => unawaited(
                        _validateLicense(licenseProvider),
                      ),
                    ),
                    if (licenseProvider.error != null) ...[
                      AppSpacing.gapMd,
                      InfoLabel(
                        label: appLocaleString(context, 'Erro', 'Error'),
                        child: Text(
                          licenseProvider.error!,
                          style: FluentTheme.of(context).typography.body
                              ?.copyWith(color: context.colors.danger),
                        ),
                      ),
                    ],
                    AppSpacing.gapLg,
                    const Divider(),
                    AppSpacing.gapMd,
                    Text(
                      appLocaleString(
                        context,
                        'Status da licença',
                        'License status',
                      ),
                      style: FluentTheme.of(context).typography.subtitle,
                    ),
                    AppSpacing.gapMd,
                    _buildLicenseStatus(licenseProvider.currentLicense),
                    if (licenseProvider.currentLicense != null) ...[
                      AppSpacing.gapMd,
                      _buildLicenseDetails(licenseProvider.currentLicense!),
                    ],
                  ],
                ),
              ),
              if (kDebugMode) ...[
                AppSpacing.gapMd,
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
        leading: Icon(FluentIcons.cancel, color: context.colors.danger),
        title: Text(appLocaleString(context, 'Sem licença', 'No license')),
        subtitle: Text(
          appLocaleString(
            context,
            'Nenhuma licença válida encontrada',
            'No valid license found',
          ),
        ),
      );
    }

    if (license.isExpired) {
      final expiresAt = license.expiresAt;
      return ListTile(
        leading: Icon(FluentIcons.warning, color: context.colors.warning),
        title: Text(
          appLocaleString(context, 'Licença expirada', 'Expired license'),
        ),
        subtitle: Text(
          expiresAt != null
              ? appLocaleString(
                  context,
                  'Expirou em: ${DateFormat('dd/MM/yyyy HH:mm').format(expiresAt)}',
                  'Expired on: ${DateFormat('dd/MM/yyyy HH:mm').format(expiresAt)}',
                )
              : appLocaleString(
                  context,
                  'Sem data de expiração registrada',
                  'No expiration date recorded',
                ),
        ),
      );
    }

    if (license.isNotYetValid) {
      final notBefore = license.notBefore!;
      return ListTile(
        leading: Icon(FluentIcons.warning, color: context.colors.warning),
        title: Text(
          appLocaleString(
            context,
            'Licença ainda não em vigor',
            'License not yet active',
          ),
        ),
        subtitle: Text(
          appLocaleString(
            context,
            'Válida a partir de: ${DateFormat('dd/MM/yyyy HH:mm').format(notBefore)}',
            'Valid from: ${DateFormat('dd/MM/yyyy HH:mm').format(notBefore)}',
          ),
        ),
      );
    }

    return ListTile(
      leading: Icon(FluentIcons.accept, color: context.colors.success),
      title: Text(appLocaleString(context, 'Licença válida', 'Valid license')),
      subtitle: Text(
        license.expiresAt != null
            ? appLocaleString(
                context,
                'Válida até: ${DateFormat('dd/MM/yyyy HH:mm').format(license.expiresAt!)}',
                'Valid until: ${DateFormat('dd/MM/yyyy HH:mm').format(license.expiresAt!)}',
              )
            : appLocaleString(
                context,
                'Licença permanente',
                'Permanent license',
              ),
      ),
    );
  }

  Widget _buildLicenseDetails(License license) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appLocaleString(context, 'Recursos permitidos', 'Allowed features'),
          style: FluentTheme.of(context).typography.bodyStrong,
        ),
        const SizedBox(height: AppSpacing.sm),
        ...license.allowedFeatures.map(
          (feature) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                Icon(
                  FluentIcons.accept,
                  size: 16,
                  color: context.colors.success,
                ),
                const SizedBox(width: AppSpacing.sm),
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
    return AppSectionCard(
      title: appLocaleString(
        context,
        'Gerador de licenças',
        'License generator',
      ),
      trailing: !licenseProvider.canGenerateLicenses
          ? Text(
              appLocaleString(
                context,
                'Indisponível neste ambiente',
                'Unavailable in this environment',
              ),
              style: FluentTheme.of(context).typography.body,
            )
          : ValueListenableBuilder<bool>(
              valueListenable: _isAuthenticatedNotifier,
              builder: (context, isAuthenticated, child) {
                if (!isAuthenticated) {
                  return AppButton(
                    label: appLocaleString(
                      context,
                      'Acessar gerador',
                      'Open generator',
                    ),
                    onPressed: () => unawaited(_showAuthDialog(context)),
                  );
                }
                return AppButton(
                  label: appLocaleString(
                    context,
                    'Gerar licença',
                    'Generate license',
                  ),
                  onPressed: () => unawaited(
                    _showGeneratorDialog(context, licenseProvider),
                  ),
                );
              },
            ),
      banner: InfoBar(
        severity: InfoBarSeverity.warning,
        title: Text(
          appLocaleString(
            context,
            'Modo de desenvolvedor',
            'Developer mode',
          ),
        ),
        content: Text(
          appLocaleString(
            context,
            'Este gerador requer chave privada Ed25519 (BACKUP_DATABASE_LICENSE_PRIVATE_KEY). '
                'NUNCA distribua a chave privada para clientes. '
                'Use este gerador apenas em ambiente controlado.',
            'This generator requires Ed25519 private key (BACKUP_DATABASE_LICENSE_PRIVATE_KEY). '
                'NEVER distribute the private key to clients. '
                'Use this generator only in controlled environment.',
          ),
        ),
      ),
      child: const SizedBox.shrink(),
    );
  }

  Future<void> _showAuthDialog(BuildContext context) async {
    final passwordController = TextEditingController();
    String? errorMessage;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => ContentDialog(
            title: Row(
              children: [
                const Icon(FluentIcons.lock),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  appLocaleString(context, 'Autenticação', 'Authentication'),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appLocaleString(
                    context,
                    'Digite a senha de administrador para acessar o gerador de licenças:',
                    'Enter admin password to access license generator:',
                  ),
                ),
                AppSpacing.gapMd,
                PasswordField(
                  controller: passwordController,
                  hint: appLocaleString(
                    context,
                    'Digite a senha',
                    'Enter password',
                  ),
                ),
                if (errorMessage != null) ...[
                  AppSpacing.gapMd,
                  InfoBar(
                    severity: InfoBarSeverity.error,
                    title: Text(appLocaleString(context, 'Erro', 'Error')),
                    content: Text(errorMessage!),
                  ),
                ],
              ],
            ),
            actions: [
              CancelButton(
                onPressed: () => Navigator.pop(dialogContext),
              ),
              AppButton.primary(
                label: appLocaleString(context, 'Entrar', 'Sign in'),
                onPressed: () {
                  final enteredPassword = passwordController.text.trim();
                  if (enteredPassword.isEmpty) {
                    setState(() {
                      errorMessage = appLocaleString(
                        context,
                        'Senha não pode estar vazia',
                        'Password cannot be empty',
                      );
                    });
                    return;
                  }

                  final storedHash =
                      dotenv.env['LICENSE_ADMIN_PASSWORD_HASH'] ?? '';
                  final result = _adminVerifier.verify(
                    enteredPassword: enteredPassword,
                    storedHash: storedHash,
                  );
                  final localizedError = _localizeAdminVerification(result);
                  if (localizedError == null) {
                    Navigator.pop(dialogContext);
                    _isAuthenticatedNotifier.value = true;
                    return;
                  }
                  setState(() => errorMessage = localizedError);
                },
              ),
            ],
          ),
        ),
      );
    } finally {
      passwordController.dispose();
    }
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
                const SizedBox(width: AppSpacing.sm),
                Text(
                  appLocaleString(
                    context,
                    'Gerador de licença',
                    'License generator',
                  ),
                ),
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
                        label: appLocaleString(
                          context,
                          'Chave do dispositivo',
                          'Device key',
                        ),
                        child: TextBox(
                          controller: deviceKeyController,
                          placeholder: appLocaleString(
                            context,
                            'Digite a chave do dispositivo para gerar a licença',
                            'Enter device key to generate the license',
                          ),
                          enabled: !isLoading,
                        ),
                      ),
                      if (licenseProvider.deviceKey != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AppButton(
                            label: appLocaleString(
                              context,
                              'Usar chave atual',
                              'Use current key',
                            ),
                            onPressed: isLoading
                                ? null
                                : () {
                                    setDialogState(() {
                                      deviceKeyController.text =
                                          licenseProvider.deviceKey!;
                                    });
                                  },
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        appLocaleString(
                          context,
                          'Recursos permitidos',
                          'Allowed features',
                        ),
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
                        label: appLocaleString(
                          context,
                          'Data de expiração (opcional)',
                          'Expiration date (optional)',
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextBox(
                                controller: expiresAtController,
                                placeholder: appLocaleString(
                                  context,
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
                                            dateError = appLocaleString(
                                              context,
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
                            const SizedBox(width: AppSpacing.sm),
                            SettingsIconAction(
                              label: appLocaleString(
                                context,
                                'Preencher data padrão',
                                'Fill default date',
                              ),
                              icon: FluentIcons.calendar,
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
                            ),
                          ],
                        ),
                      ),
                      if (dateError != null) ...[
                        const SizedBox(height: 16),
                        InfoBar(
                          severity: InfoBarSeverity.error,
                          title: Text(
                            appLocaleString(context, 'Erro', 'Error'),
                          ),
                          content: Text(dateError!),
                        ),
                      ],
                      if (errorMessage != null) ...[
                        const SizedBox(height: 16),
                        InfoBar(
                          severity: InfoBarSeverity.error,
                          title: Text(
                            appLocaleString(context, 'Erro', 'Error'),
                          ),
                          content: Text(errorMessage!),
                        ),
                      ],
                      if (generatedLicenseController.text.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        InfoLabel(
                          label: appLocaleString(
                            context,
                            'Licença gerada',
                            'Generated license',
                          ),
                          child: TextBox(
                            controller: generatedLicenseController,
                            maxLines: 5,
                            readOnly: true,
                          ),
                        ),
                        const SizedBox(height: 16),
                        AppButton(
                          label: appLocaleString(
                            context,
                            'Copiar licença',
                            'Copy license',
                          ),
                          onPressed: () async {
                            final success = await _clipboardService
                                .copyToClipboard(
                                  generatedLicenseController.text,
                                );
                            if (!ctx.mounted) return;
                            if (success) {
                              setDialogState(() {
                                errorMessage = null;
                              });
                              unawaited(
                                FluentInfoBarFeedback.showSuccess(
                                  ctx,
                                  message: appLocaleString(
                                    ctx,
                                    'Licença copiada para clipboard!',
                                    'License copied to clipboard!',
                                  ),
                                ),
                              );
                            } else {
                              setDialogState(() {
                                errorMessage = appLocaleString(
                                  ctx,
                                  'Erro ao copiar para clipboard',
                                  'Error copying to clipboard',
                                );
                              });
                            }
                          },
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
              AppButton.primary(
                label: appLocaleString(
                  context,
                  'Gerar licença',
                  'Generate license',
                ),
                isLoading: isLoading,
                onPressed: () async {
                  final deviceKey = deviceKeyController.text.trim();

                  if (deviceKey.isEmpty) {
                    setDialogState(() {
                      errorMessage = appLocaleString(
                        context,
                        'Chave do dispositivo é obrigatória',
                        'Device key is required',
                      );
                    });
                    return;
                  }

                  if (selectedFeatures.isEmpty) {
                    setDialogState(() {
                      errorMessage = appLocaleString(
                        context,
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

                  final licenseKey = await licenseProvider.generateLicense(
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
                          appLocaleString(
                            context,
                            'Erro ao gerar licença',
                            'Error generating license',
                          );
                    }
                  });
                },
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
