import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_labels.dart';
import 'package:fluent_ui/fluent_ui.dart';

enum FtpIntegrityPreset { quick, balanced, maximum }

FtpWhenResumeNotSupported parseFtpWhenResumeNotSupported(String? value) {
  if (value == null) return FtpWhenResumeNotSupported.fallback;
  return FtpWhenResumeNotSupported.values.firstWhere(
    (e) => e.name == value,
    orElse: () => FtpWhenResumeNotSupported.fallback,
  );
}

extension FtpIntegrityPresetX on FtpIntegrityPreset {
  static FtpIntegrityPreset fromFlags({
    required bool enableStrongIntegrityValidation,
    required bool enableReadBackValidation,
  }) {
    if (!enableStrongIntegrityValidation) {
      return FtpIntegrityPreset.quick;
    }
    if (enableReadBackValidation) {
      return FtpIntegrityPreset.maximum;
    }
    return FtpIntegrityPreset.balanced;
  }

  bool get enablesStrongIntegrityValidation => this != FtpIntegrityPreset.quick;

  bool get enablesReadBackValidation => this == FtpIntegrityPreset.maximum;

  Color impactColor(BuildContext context) {
    final colors = context.colors;
    return switch (this) {
      FtpIntegrityPreset.quick => colors.success,
      FtpIntegrityPreset.balanced => colors.info,
      FtpIntegrityPreset.maximum => colors.warning,
    };
  }

  String impactText(DestinationDialogLabelBuilder label) {
    return switch (this) {
      FtpIntegrityPreset.quick => label(
        'Impacto de performance: baixo. Menor confiança de integridade.',
        'Performance impact: low. Validates size and writes SHA-256 sidecar.',
      ),
      FtpIntegrityPreset.balanced => label(
        'Impacto de performance: médio. Bom equilíbrio para uso diário.',
        'Performance impact: medium. Good balance for daily usage.',
      ),
      FtpIntegrityPreset.maximum => label(
        'Impacto de performance: alto em arquivos grandes devido ao read-back.',
        'Performance impact: high on large files due to read-back.',
      ),
    };
  }

  String displayName(DestinationDialogLabelBuilder label) {
    return switch (this) {
      FtpIntegrityPreset.quick => label('Rapido', 'Quick'),
      FtpIntegrityPreset.balanced => label('Equilibrado', 'Balanced'),
      FtpIntegrityPreset.maximum => label(
        'Maxima integridade',
        'Maximum integrity',
      ),
    };
  }
}

/// **Organism** — FTP integrity, resume and timeout options.
class FtpAdvancedOptionsSection extends StatelessWidget {
  const FtpAdvancedOptionsSection({
    required this.integrityPreset,
    required this.whenResumeNotSupported,
    required this.enableStrongIntegrityValidation,
    required this.enableReadBackValidation,
    required this.keepPartOnCancel,
    required this.enableVerboseLog,
    required this.maxAttemptsController,
    required this.connectionTimeoutSecondsController,
    required this.uploadTimeoutMinutesController,
    required this.impactColor,
    required this.impactText,
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
  final Color impactColor;
  final String impactText;
  final DestinationDialogLabelBuilder labelBuilder;
  final ValueChanged<FtpIntegrityPreset> onPresetChanged;
  final ValueChanged<bool> onEnableStrongIntegrityValidationChanged;
  final ValueChanged<bool>? onEnableReadBackValidationChanged;
  final ValueChanged<bool> onKeepPartOnCancelChanged;
  final ValueChanged<FtpWhenResumeNotSupported> onWhenResumeNotSupportedChanged;
  final ValueChanged<bool> onEnableVerboseLogChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelBuilder('Opções avançadas', 'Advanced options'),
          style: FluentTheme.of(context).typography.bodyStrong,
        ),
        const SizedBox(height: AppSpacing.md),
        AppDropdown<FtpIntegrityPreset>(
          label: labelBuilder('Preset de integridade', 'Integrity preset'),
          value: integrityPreset,
          placeholder: Text(
            labelBuilder('Maxima integridade', 'Maximum integrity'),
          ),
          items: FtpIntegrityPreset.values
              .map(
                (preset) => ComboBoxItem<FtpIntegrityPreset>(
                  value: preset,
                  child: Text(preset.displayName(labelBuilder)),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              onPresetChanged(value);
            }
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          labelBuilder(
            'Rapido: so tamanho. Equilibrado: hash remoto. Maxima: hash remoto + read-back quando necessario.',
            'Quick: size + SHA-256 sidecar. Balanced: remote hash. Maximum: remote hash + read-back when needed.',
          ),
          style: FluentTheme.of(context).typography.caption,
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: impactColor.withValues(alpha: 0.08),
            borderRadius: AppRadius.circularMd,
            border: Border.all(color: impactColor.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Icon(FluentIcons.info, size: 16, color: impactColor),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  impactText,
                  style: FluentTheme.of(context).typography.caption?.copyWith(
                    color: impactColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        LabeledToggle(
          title: labelBuilder(
            'Validacao forte de integridade',
            'Strong integrity validation',
          ),
          description: labelBuilder(
            'Alem do tamanho, valida com hash do arquivo remoto para reduzir falsos positivos.',
            'In addition to file size, validates using remote file hash to reduce false positives.',
          ),
          value: enableStrongIntegrityValidation,
          onChanged: onEnableStrongIntegrityValidationChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        LabeledToggle(
          title: labelBuilder(
            'Read-back quando hash remoto indisponível',
            'Read-back when remote hash unavailable',
          ),
          description: labelBuilder(
            'Baixa o arquivo do FTP e compara SHA-256 com o local. Mais confiavel, porem mais lento para arquivos grandes.',
            'Downloads the file from FTP and compares SHA-256 with local. More reliable, but slower for large files.',
          ),
          value: enableReadBackValidation,
          onChanged: onEnableReadBackValidationChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        LabeledToggle(
          title: labelBuilder(
            'Manter parcial ao cancelar',
            'Keep partial on cancel',
          ),
          description: labelBuilder(
            'Manter arquivo .part no servidor para retomar depois',
            'Keep .part file on server to resume later',
          ),
          value: keepPartOnCancel,
          onChanged: onKeepPartOnCancelChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        AppDropdown<FtpWhenResumeNotSupported>(
          label: labelBuilder(
            'Quando servidor não suporta retomada',
            'When server does not support resume',
          ),
          value: whenResumeNotSupported,
          placeholder: Text(
            labelBuilder(
              'Fallback (upload completo)',
              'Fallback (full upload)',
            ),
          ),
          items: FtpWhenResumeNotSupported.values
              .map(
                (e) => ComboBoxItem<FtpWhenResumeNotSupported>(
                  value: e,
                  child: Text(
                    e == FtpWhenResumeNotSupported.fallback
                        ? labelBuilder(
                            'Fallback (upload completo)',
                            'Fallback (full upload)',
                          )
                        : labelBuilder('Falhar', 'Fail'),
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              onWhenResumeNotSupportedChanged(value);
            }
          },
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: labelBuilder('Max. tentativas', 'Max attempts'),
          controller: maxAttemptsController,
          hint: labelBuilder('Padrao: 3', 'Default: 3'),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          labelBuilder(
            'Numero maximo de tentativas por upload',
            'Maximum number of attempts per upload',
          ),
          style: FluentTheme.of(context).typography.caption,
        ),
        const SizedBox(height: AppSpacing.md),
        LabeledToggle(
          title: labelBuilder('Log detalhado FTP', 'Verbose FTP log'),
          description: labelBuilder(
            'Registrar comandos e respostas do protocolo FTP (util para diagnostico)',
            'Log FTP protocol commands and responses (useful for troubleshooting)',
          ),
          value: enableVerboseLog,
          onChanged: onEnableVerboseLogChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: labelBuilder(
            'Timeout de conexao (s)',
            'Connection timeout (s)',
          ),
          controller: connectionTimeoutSecondsController,
          hint: labelBuilder('Padrao: 15', 'Default: 15'),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          labelBuilder(
            'Tempo limite para conectar e autenticar no servidor FTP',
            'Time limit to connect and authenticate to FTP server',
          ),
          style: FluentTheme.of(context).typography.caption,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: labelBuilder(
            'Timeout de upload (min)',
            'Upload timeout (min)',
          ),
          controller: uploadTimeoutMinutesController,
          hint: labelBuilder('Padrao: 60', 'Default: 60'),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          labelBuilder(
            'Tempo limite para sessao de upload (arquivos grandes podem precisar de mais)',
            'Time limit for upload session (large files may need more)',
          ),
          style: FluentTheme.of(context).typography.caption,
        ),
      ],
    );
  }
}
