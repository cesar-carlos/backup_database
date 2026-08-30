import 'dart:async';

import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/application/services/admin_password_verifier.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/core/utils/clipboard_service.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/license/license_auth_dialog.dart';
import 'package:backup_database/presentation/widgets/settings/license/license_features_list.dart';
import 'package:backup_database/presentation/widgets/settings/license/license_generator_dialog.dart';
import 'package:backup_database/presentation/widgets/settings/license/license_generator_panel.dart';
import 'package:backup_database/presentation/widgets/settings/license/license_status_panel.dart';
import 'package:backup_database/presentation/widgets/settings/settings_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
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

  Future<void> _showAuthDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => LicenseAuthDialog(
        adminVerifier: _adminVerifier,
        onAuthenticated: () {
          _isAuthenticatedNotifier.value = true;
        },
      ),
    );
  }

  Future<void> _showGeneratorDialog(
    BuildContext context,
    LicenseProvider licenseProvider,
  ) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => LicenseGeneratorDialog(
        licenseProvider: licenseProvider,
        clipboardService: _clipboardService,
      ),
    );
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
                    if (licenseProvider.isDecoderDegraded) ...[
                      AppSpacing.gapMd,
                      InfoBar(
                        severity: InfoBarSeverity.warning,
                        isLong: true,
                        title: Text(
                          appLocaleString(
                            context,
                            'Decoder de licença indisponível',
                            'License decoder unavailable',
                          ),
                        ),
                        content: Text(
                          appLocaleString(
                            context,
                            'Não é possível validar uma chave colada neste '
                                'aparelho. O período de avaliação não depende '
                                'disso. Configure BACKUP_DATABASE_LICENSE_PUBLIC_KEY '
                                r'em C:\ProgramData\BackupDatabase\config\.env.',
                            'A pasted license key cannot be validated on this '
                                'device. The evaluation period does not depend on '
                                'this. Configure BACKUP_DATABASE_LICENSE_PUBLIC_KEY '
                                r'in C:\ProgramData\BackupDatabase\config\.env.',
                          ),
                        ),
                      ),
                    ],
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
                    LicenseStatusPanel(licenseProvider: licenseProvider),
                    if (licenseProvider.showTrialReminder) ...[
                      AppSpacing.gapMd,
                      const LicenseTrialReminderInfoBar(),
                    ],
                    if (licenseProvider.effectiveLicense != null) ...[
                      AppSpacing.gapMd,
                      LicenseFeaturesList(
                        license: licenseProvider.effectiveLicense!,
                      ),
                    ],
                  ],
                ),
              ),
              if (kDebugMode) ...[
                AppSpacing.gapMd,
                LicenseGeneratorPanel(
                  canGenerateLicenses: licenseProvider.canGenerateLicenses,
                  isAuthenticatedListenable: _isAuthenticatedNotifier,
                  onOpenAuth: () => unawaited(_showAuthDialog(context)),
                  onOpenGenerator: () => unawaited(
                    _showGeneratorDialog(context, licenseProvider),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
