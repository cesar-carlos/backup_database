import 'package:backup_database/core/compatibility/feature_disable_reason.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/presentation/utils/compatibility_reason_localizer.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — SMTP password vs OAuth provider authentication.
class NotificationSmtpAuthenticationSection extends StatelessWidget {
  const NotificationSmtpAuthenticationSection({
    required this.authMode,
    required this.isBusy,
    required this.oauthAccountEmail,
    required this.oauthConnectedAt,
    required this.oauthModesAvailable,
    required this.oauthUnavailableReason,
    required this.onAuthModeChanged,
    required this.onConnect,
    required this.onReconnect,
    required this.onDisconnect,
    super.key,
  });

  final SmtpAuthMode authMode;
  final bool isBusy;
  final String? oauthAccountEmail;
  final DateTime? oauthConnectedAt;
  final bool oauthModesAvailable;
  final FeatureDisableReason? oauthUnavailableReason;
  final ValueChanged<SmtpAuthMode> onAuthModeChanged;
  final Future<void> Function() onConnect;
  final Future<void> Function() onReconnect;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    final isOAuth = authMode.isOAuth;
    final isConnected = oauthAccountEmail?.trim().isNotEmpty ?? false;
    final connectedAt = oauthConnectedAt?.toLocal();
    final captionStyle = FluentTheme.of(context).typography.caption;
    final outline = context.colors.outline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!oauthModesAvailable) ...[
          InfoBar(
            title: Text(
              appLocaleString(
                context,
                'OAuth SMTP',
                'SMTP OAuth',
              ),
            ),
            content: Text(
              localizeCompatibilityReason(
                context,
                reason: oauthUnavailableReason,
                fallbackPt: 'Não disponível nesta versão do Windows.',
                fallbackEn: 'Not available on this Windows version.',
              ),
            ),
            severity: InfoBarSeverity.warning,
            isLong: true,
          ),
          const SizedBox(height: 12),
        ],
        AppDropdown<SmtpAuthMode>(
          label: appLocaleString(
            context,
            'Modo de autenticação',
            'Authentication mode',
          ),
          value: authMode,
          items: [
            ComboBoxItem(
              value: SmtpAuthMode.password,
              child: Text(
                appLocaleString(context, 'Senha SMTP', 'SMTP password'),
              ),
            ),
            if (oauthModesAvailable) ...[
              const ComboBoxItem(
                value: SmtpAuthMode.oauthGoogle,
                child: Text('Google OAuth2'),
              ),
              const ComboBoxItem(
                value: SmtpAuthMode.oauthMicrosoft,
                child: Text('Microsoft OAuth2'),
              ),
            ],
          ],
          onChanged: (value) {
            if (value != null) {
              onAuthModeChanged(value);
            }
          },
        ),
        if (isOAuth) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: outline.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: outline.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnected
                      ? appLocaleString(
                          context,
                          'Conta conectada: $oauthAccountEmail',
                          'Account connected: $oauthAccountEmail',
                        )
                      : appLocaleString(
                          context,
                          'Nenhuma conta OAuth conectada',
                          'No OAuth account connected',
                        ),
                ),
                if (connectedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    appLocaleString(
                      context,
                      'Conectado em: $connectedAt',
                      'Connected at: $connectedAt',
                    ),
                    style: captionStyle,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Button(
                onPressed: isBusy ? null : onConnect,
                child: Text(
                  isBusy
                      ? appLocaleString(
                          context,
                          'Conectando...',
                          'Connecting...',
                        )
                      : appLocaleString(context, 'Conectar', 'Connect'),
                ),
              ),
              Button(
                onPressed: isBusy ? null : onReconnect,
                child: Text(
                  appLocaleString(context, 'Reconectar', 'Reconnect'),
                ),
              ),
              Button(
                onPressed: isBusy ? null : onDisconnect,
                child: Text(
                  appLocaleString(context, 'Desconectar', 'Disconnect'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
