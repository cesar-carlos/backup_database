import 'package:backup_database/application/providers/windows_service_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ServiceUacWaitingBanner extends StatelessWidget {
  const ServiceUacWaitingBanner({required this.operation, super.key});

  final WindowsServiceOperation operation;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.08),
        borderRadius: AppRadius.circularMd,
        border: Border.all(
          color: colors.warning.withValues(alpha: 0.28),
        ),
      ),
      child: InfoBar(
        title: Text(
          appLocaleString(
            context,
            'Aguardando confirmação do Windows (UAC)...',
            'Waiting for Windows confirmation (UAC)...',
          ),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: ProgressRing(
                      strokeWidth: 2,
                      activeColor: colors.warning,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(_message(context))),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              appLocaleString(
                context,
                'Se nada acontecer, verifique se o prompt do Windows não ficou atrás desta janela. A operação pode levar até cerca de 90 segundos.',
                'If nothing happens, check whether the Windows prompt is hidden behind this window. The operation may take up to about 90 seconds.',
              ),
              style: FluentTheme.of(context).typography.caption,
            ),
          ],
        ),
        severity: InfoBarSeverity.warning,
        isLong: true,
      ),
    );
  }

  String _message(BuildContext context) {
    return switch (operation) {
      WindowsServiceOperation.install => appLocaleString(
        context,
        'Confirme o prompt do Windows para instalar o serviço.',
        'Confirm the Windows prompt to install the service.',
      ),
      WindowsServiceOperation.uninstall => appLocaleString(
        context,
        'Confirme o prompt do Windows para remover o serviço.',
        'Confirm the Windows prompt to remove the service.',
      ),
      WindowsServiceOperation.start => appLocaleString(
        context,
        'Confirme o prompt do Windows para iniciar o serviço.',
        'Confirm the Windows prompt to start the service.',
      ),
      WindowsServiceOperation.stop => appLocaleString(
        context,
        'Confirme o prompt do Windows para parar o serviço.',
        'Confirm the Windows prompt to stop the service.',
      ),
      WindowsServiceOperation.restart => appLocaleString(
        context,
        'Confirme o prompt do Windows para reiniciar o serviço.',
        'Confirm the Windows prompt to restart the service.',
      ),
      _ => appLocaleString(
        context,
        'Confirme o prompt do Windows para continuar.',
        'Confirm the Windows prompt to continue.',
      ),
    };
  }
}
