import 'dart:async';

import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/core/utils/clipboard_service.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/license/license_feature_labels.dart';
import 'package:backup_database/presentation/widgets/settings/settings_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

/// **Organism** — debug form to mint a signed license key.
class LicenseGeneratorDialog extends StatefulWidget {
  const LicenseGeneratorDialog({
    required this.licenseProvider,
    required this.clipboardService,
    super.key,
  });

  final LicenseProvider licenseProvider;
  final ClipboardService clipboardService;

  @override
  State<LicenseGeneratorDialog> createState() => _LicenseGeneratorDialogState();
}

class _LicenseGeneratorDialogState extends State<LicenseGeneratorDialog> {
  final TextEditingController _deviceKeyController = TextEditingController();
  final TextEditingController _generatedLicenseController =
      TextEditingController();
  final TextEditingController _expiresAtController = TextEditingController();
  final Set<String> _selectedFeatures = <String>{};
  DateTime? _selectedExpiresAt;
  bool _isLoading = false;
  String? _errorMessage;
  String? _dateError;

  @override
  void dispose() {
    _deviceKeyController.dispose();
    _generatedLicenseController.dispose();
    _expiresAtController.dispose();
    super.dispose();
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

  void _onExpiresAtChanged(String value) {
    if (value.isEmpty) {
      setState(() {
        _dateError = null;
      });
      return;
    }
    final parsedDate = _tryParseDate(value);
    if (parsedDate == null) {
      setState(() {
        _dateError = appLocaleString(
          context,
          'Data inválida. Use o formato DD/MM/YYYY',
          'Invalid date. Use format DD/MM/YYYY',
        );
      });
    } else {
      setState(() {
        _dateError = null;
        _selectedExpiresAt = parsedDate;
      });
    }
  }

  void _fillDefaultDate() {
    final now = DateTime.now();
    final defaultDate =
        _selectedExpiresAt ??
        DateTime(now.year, now.month, now.day).add(const Duration(days: 30));
    setState(() {
      _selectedExpiresAt = defaultDate;
      _expiresAtController.text = DateFormat('dd/MM/yyyy').format(defaultDate);
    });
  }

  Future<void> _copyGeneratedLicense() async {
    final success = await widget.clipboardService.copyToClipboard(
      _generatedLicenseController.text,
    );
    if (!mounted) return;
    if (success) {
      setState(() {
        _errorMessage = null;
      });
      unawaited(
        FluentInfoBarFeedback.showSuccess(
          context,
          message: appLocaleString(
            context,
            'Licença copiada para clipboard!',
            'License copied to clipboard!',
          ),
        ),
      );
    } else {
      setState(() {
        _errorMessage = appLocaleString(
          context,
          'Erro ao copiar para clipboard',
          'Error copying to clipboard',
        );
      });
    }
  }

  Future<void> _generate() async {
    final deviceKey = _deviceKeyController.text.trim();

    if (deviceKey.isEmpty) {
      setState(() {
        _errorMessage = appLocaleString(
          context,
          'Chave do dispositivo é obrigatória',
          'Device key is required',
        );
      });
      return;
    }

    if (_selectedFeatures.isEmpty) {
      setState(() {
        _errorMessage = appLocaleString(
          context,
          'Selecione pelo menos um recurso',
          'Select at least one feature',
        );
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final licenseKey = await widget.licenseProvider.generateLicense(
      deviceKey: deviceKey,
      expiresAt: _selectedExpiresAt,
      allowedFeatures: _selectedFeatures.toList(),
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (licenseKey != null) {
        _generatedLicenseController.text = licenseKey;
        _errorMessage = null;
      } else {
        _errorMessage =
            widget.licenseProvider.error ??
            appLocaleString(
              context,
              'Erro ao gerar licença',
              'Error generating license',
            );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
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
                    controller: _deviceKeyController,
                    placeholder: appLocaleString(
                      context,
                      'Digite a chave do dispositivo para gerar a licença',
                      'Enter device key to generate the license',
                    ),
                    enabled: !_isLoading,
                  ),
                ),
                if (widget.licenseProvider.deviceKey != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton(
                      label: appLocaleString(
                        context,
                        'Usar chave atual',
                        'Use current key',
                      ),
                      onPressed: _isLoading
                          ? null
                          : () {
                              setState(() {
                                _deviceKeyController.text =
                                    widget.licenseProvider.deviceKey!;
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
                  style: FluentTheme.of(context).typography.bodyStrong,
                ),
                const SizedBox(height: 8),
                ...LicenseFeatures.allFeatures.map(
                  (feature) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Checkbox(
                      checked: _selectedFeatures.contains(feature),
                      onChanged: _isLoading
                          ? null
                          : (value) {
                              setState(() {
                                if (value ?? false) {
                                  _selectedFeatures.add(feature);
                                } else {
                                  _selectedFeatures.remove(feature);
                                }
                              });
                            },
                      content: Text(licenseFeatureLabel(context, feature)),
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
                          controller: _expiresAtController,
                          placeholder: appLocaleString(
                            context,
                            'DD/MM/YYYY ou deixe vazio para licença permanente',
                            'DD/MM/YYYY or leave empty for permanent license',
                          ),
                          enabled: !_isLoading,
                          onChanged: _isLoading ? null : _onExpiresAtChanged,
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
                        onPressed: _isLoading ? null : _fillDefaultDate,
                      ),
                    ],
                  ),
                ),
                if (_dateError != null) ...[
                  const SizedBox(height: 16),
                  InfoBar(
                    severity: InfoBarSeverity.error,
                    title: Text(appLocaleString(context, 'Erro', 'Error')),
                    content: Text(_dateError!),
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  InfoBar(
                    severity: InfoBarSeverity.error,
                    title: Text(appLocaleString(context, 'Erro', 'Error')),
                    content: Text(_errorMessage!),
                  ),
                ],
                if (_generatedLicenseController.text.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  InfoLabel(
                    label: appLocaleString(
                      context,
                      'Licença gerada',
                      'Generated license',
                    ),
                    child: TextBox(
                      controller: _generatedLicenseController,
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
                    onPressed: () => unawaited(_copyGeneratedLicense()),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        CancelButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
        ),
        AppButton.primary(
          label: appLocaleString(context, 'Gerar licença', 'Generate license'),
          isLoading: _isLoading,
          onPressed: () => unawaited(_generate()),
        ),
      ],
    );
  }
}
