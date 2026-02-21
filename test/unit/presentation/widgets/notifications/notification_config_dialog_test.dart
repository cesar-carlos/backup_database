import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/presentation/widgets/notifications/notification_config_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildDialog({
    EmailConfig? initialConfig,
    Future<EmailConfig?> Function(
      EmailConfig config,
      SmtpOAuthProvider provider,
    )?
    onConnectOAuth,
    Future<EmailConfig?> Function(
      EmailConfig config,
      SmtpOAuthProvider provider,
    )?
    onReconnectOAuth,
    Future<EmailConfig> Function(EmailConfig config)? onDisconnectOAuth,
  }) {
    final config =
        initialConfig ??
        EmailConfig(
          id: 'cfg-test',
          configName: 'SMTP Principal',
          smtpServer: 'smtp.example.com',
          username: 'smtp@example.com',
          password: 'secret',
          recipients: const ['destino@example.com'],
          fromEmail: 'smtp@example.com',
        );

    return FluentApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(1920, 1080),
          textScaler: TextScaler.linear(0.9),
        ),
        child: NotificationConfigDialog(
          initialConfig: config,
          initialRecipientEmail: 'destino@example.com',
          onConnectOAuth: onConnectOAuth,
          onReconnectOAuth: onReconnectOAuth,
          onDisconnectOAuth: onDisconnectOAuth,
        ),
      ),
    );
  }

  group('NotificationConfigDialog', () {
    testWidgets(
      'shows oauth actions when selecting OAuth mode',
      (tester) async {
        final oauthConfig = EmailConfig(
          id: 'cfg-oauth',
          configName: 'SMTP OAuth',
          username: 'oauth-user@example.com',
          authMode: SmtpAuthMode.oauthGoogle,
          oauthProvider: SmtpOAuthProvider.google,
          recipients: const ['destino@example.com'],
          fromEmail: 'oauth-user@example.com',
        );

        await tester.pumpWidget(
          buildDialog(
            initialConfig: oauthConfig,
            onConnectOAuth: (config, provider) async => config,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Nenhuma conta OAuth conectada'), findsOneWidget);
        expect(find.text('Conectar'), findsOneWidget);
        expect(find.text('Reconectar'), findsOneWidget);
        expect(find.text('Desconectar'), findsOneWidget);
      },
    );

    testWidgets(
      'connect oauth updates account and shows success message',
      (tester) async {
        final oauthConfig = EmailConfig(
          id: 'cfg-oauth-connect',
          configName: 'SMTP OAuth',
          username: 'oauth-user@example.com',
          authMode: SmtpAuthMode.oauthGoogle,
          oauthProvider: SmtpOAuthProvider.google,
          recipients: const ['destino@example.com'],
          fromEmail: 'oauth-user@example.com',
        );

        await tester.pumpWidget(
          FluentApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(1920, 1080),
                textScaler: TextScaler.linear(0.9),
              ),
              child: NotificationConfigDialog(
                initialConfig: oauthConfig,
                initialRecipientEmail: 'destino@example.com',
                onConnectOAuth: (config, provider) async {
                  return config.copyWith(
                    authMode: SmtpAuthMode.oauthGoogle,
                    oauthProvider: provider,
                    oauthAccountEmail: 'oauth-user@example.com',
                    oauthTokenKey: 'oauth-token-key',
                    oauthConnectedAt: DateTime.utc(2026, 2, 20, 18),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Conectar'));
        await tester.tap(find.text('Conectar'));
        await tester.pumpAndSettle();

        expect(
          find.text('Conta OAuth SMTP conectada com sucesso.'),
          findsOneWidget,
        );
      },
    );
  });
}
