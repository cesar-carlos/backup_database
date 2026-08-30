import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_ftp_advanced.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_labels.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Organism** — FTPS, resume, connection test and advanced FTP options.
class FtpSecurityAndResumeSection extends StatelessWidget {
  const FtpSecurityAndResumeSection({
    required this.useFtps,
    required this.allowInvalidCertificates,
    required this.enableResume,
    required this.isTestingConnection,
    required this.labelBuilder,
    required this.onUseFtpsChanged,
    required this.onAllowInvalidCertificatesChanged,
    required this.onEnableResumeChanged,
    required this.onTestConnection,
    required this.advancedOptions,
    super.key,
  });

  final bool useFtps;
  final bool allowInvalidCertificates;
  final bool enableResume;
  final bool isTestingConnection;
  final DestinationDialogLabelBuilder labelBuilder;
  final ValueChanged<bool> onUseFtpsChanged;
  final ValueChanged<bool> onAllowInvalidCertificatesChanged;
  final ValueChanged<bool> onEnableResumeChanged;
  final VoidCallback onTestConnection;
  final Widget advancedOptions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LabeledToggle(
          title: labelBuilder('Usar FTPS', 'Use FTPS'),
          description: labelBuilder(
            'Conexão FTP segura (SSL/TLS)',
            'Secure FTP connection (SSL/TLS)',
          ),
          value: useFtps,
          onChanged: onUseFtpsChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        if (useFtps) ...[
          LabeledToggle(
            title: labelBuilder(
              'Permitir certificado FTPS invalido',
              'Allow invalid FTPS certificate',
            ),
            description: labelBuilder(
              'Compatibilidade com certificados autoassinados. Desative para validar certificados em producao.',
              'Compatibility with self-signed certificates. Turn off to validate production certificates.',
            ),
            value: allowInvalidCertificates,
            onChanged: onAllowInvalidCertificatesChanged,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        LabeledToggle(
          title: labelBuilder(
            'Retomada de upload (REST STREAM)',
            'Upload resume (REST STREAM)',
          ),
          description: labelBuilder(
            'Retomar envio do ponto de interrupção quando o servidor suportar',
            'Resume upload from interruption point when server supports it',
          ),
          value: enableResume,
          onChanged: onEnableResumeChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: labelBuilder('Testar conexão FTP', 'Test FTP connection'),
          icon: FluentIcons.network_tower,
          onPressed: onTestConnection,
          isLoading: isTestingConnection,
        ),
        const SizedBox(height: AppSpacing.md),
        advancedOptions,
      ],
    );
  }
}

/// **Molecule** — thin wiring of [FtpAdvancedOptionsSection] flags.
class FtpAdvancedOptionsSlot extends StatelessWidget {
  const FtpAdvancedOptionsSlot({
    required this.integrityPreset,
    required this.whenResumeNotSupported,
    required this.enableStrongIntegrityValidation,
    required this.enableReadBackValidation,
    required this.keepPartOnCancel,
    required this.enableVerboseLog,
    required this.maxAttemptsController,
    required this.connectionTimeoutSecondsController,
    required this.uploadTimeoutMinutesController,
    required this.labelBuilder,
    required this.onPresetChanged,
    required this.onEnableStrongIntegrityValidationChanged,
    required this.onKeepPartOnCancelChanged,
    required this.onWhenResumeNotSupportedChanged,
    required this.onEnableVerboseLogChanged,
    super.key,
    this.onEnableReadBackValidationChanged,
  });

  final FtpIntegrityPreset integrityPreset;
  final FtpWhenResumeNotSupported whenResumeNotSupported;
  final bool enableStrongIntegrityValidation;
  final bool enableReadBackValidation;
  final bool keepPartOnCancel;
  final bool enableVerboseLog;
  final TextEditingController maxAttemptsController;
  final TextEditingController connectionTimeoutSecondsController;
  final TextEditingController uploadTimeoutMinutesController;
  final DestinationDialogLabelBuilder labelBuilder;
  final ValueChanged<FtpIntegrityPreset> onPresetChanged;
  final ValueChanged<bool> onEnableStrongIntegrityValidationChanged;
  final ValueChanged<bool>? onEnableReadBackValidationChanged;
  final ValueChanged<bool> onKeepPartOnCancelChanged;
  final ValueChanged<FtpWhenResumeNotSupported> onWhenResumeNotSupportedChanged;
  final ValueChanged<bool> onEnableVerboseLogChanged;

  @override
  Widget build(BuildContext context) {
    return FtpAdvancedOptionsSection(
      integrityPreset: integrityPreset,
      whenResumeNotSupported: whenResumeNotSupported,
      enableStrongIntegrityValidation: enableStrongIntegrityValidation,
      enableReadBackValidation: enableReadBackValidation,
      keepPartOnCancel: keepPartOnCancel,
      enableVerboseLog: enableVerboseLog,
      maxAttemptsController: maxAttemptsController,
      connectionTimeoutSecondsController: connectionTimeoutSecondsController,
      uploadTimeoutMinutesController: uploadTimeoutMinutesController,
      impactColor: integrityPreset.impactColor(context),
      impactText: integrityPreset.impactText(labelBuilder),
      labelBuilder: labelBuilder,
      onPresetChanged: onPresetChanged,
      onEnableStrongIntegrityValidationChanged:
          onEnableStrongIntegrityValidationChanged,
      onEnableReadBackValidationChanged: onEnableReadBackValidationChanged,
      onKeepPartOnCancelChanged: onKeepPartOnCancelChanged,
      onWhenResumeNotSupportedChanged: onWhenResumeNotSupportedChanged,
      onEnableVerboseLogChanged: onEnableVerboseLogChanged,
    );
  }
}
