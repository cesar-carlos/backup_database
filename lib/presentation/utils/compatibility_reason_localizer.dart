import 'package:backup_database/core/compatibility/feature_disable_reason.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:flutter/widgets.dart';

String localizeCompatibilityReason(
  BuildContext context, {
  required FeatureDisableReason? reason,
  required String fallbackPt,
  required String fallbackEn,
}) {
  switch (reason) {
    case FeatureDisableReason.notWindows:
      return appLocaleString(
        context,
        'Disponível apenas no Windows.',
        'Available only on Windows.',
      );
    case FeatureDisableReason.osVersionUnresolved:
      return appLocaleString(
        context,
        'Não foi possível identificar a versão do Windows com segurança.',
        'Could not determine Windows version safely.',
      );
    case FeatureDisableReason.osBelowMinimum:
      return appLocaleString(
        context,
        'Requer Windows 8 / Server 2012 ou superior.',
        'Requires Windows 8 / Server 2012 or newer.',
      );
    case FeatureDisableReason.autoUpdateUnsupportedLegacyServer:
      return appLocaleString(
        context,
        'Atualização automática desabilitada para Windows Server anterior '
            'ao 2016.',
        'Automatic update is disabled for Windows Server before 2016.',
      );
    case FeatureDisableReason.oauthExternalUnsupportedOs:
      return appLocaleString(
        context,
        'OAuth requer uma versão suportada do Windows.',
        'OAuth requires a supported Windows version.',
      );
    case FeatureDisableReason.webviewRuntimeUnavailable:
      return appLocaleString(
        context,
        'Runtime WebView2 não está disponível.',
        'WebView2 runtime is not available.',
      );
    case FeatureDisableReason.webviewProbeTimedOut:
      return appLocaleString(
        context,
        'A verificação do WebView2 expirou. Tente novamente com o sistema '
            'menos sobrecarregado.',
        'The WebView2 probe timed out. Try again when the system is less busy.',
      );
    case FeatureDisableReason.embeddedWebviewUnsupportedLegacyServer:
      return appLocaleString(
        context,
        'OAuth embutido por WebView não é suportado em Windows Server '
            '2012/2012 R2.',
        'Embedded WebView OAuth is not supported on Windows Server '
            '2012/2012 R2.',
      );
    case FeatureDisableReason.nonInteractiveSession:
      return appLocaleString(
        context,
        'Disponível apenas em sessão interativa de usuário.',
        'Available only in an interactive user session.',
      );
    case FeatureDisableReason.trayRequiresInteractiveSession:
      return appLocaleString(
        context,
        'A bandeja do sistema requer sessão interativa (Desktop/RDP).',
        'System tray requires an interactive session (Desktop/RDP).',
      );
    case FeatureDisableReason.windowManagementRequiresInteractiveSession:
      return appLocaleString(
        context,
        'O gerenciamento de janela requer sessão interativa (Desktop/RDP).',
        'Window management requires an interactive session (Desktop/RDP).',
      );
    case null:
      return appLocaleString(context, fallbackPt, fallbackEn);
  }
}
