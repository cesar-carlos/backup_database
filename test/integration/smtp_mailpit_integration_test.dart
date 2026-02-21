import 'dart:io';

import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/smtp_oauth_state.dart';
import 'package:backup_database/domain/services/i_oauth_smtp_service.dart';
import 'package:backup_database/infrastructure/external/email/email_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _FakeOAuthSmtpService implements IOAuthSmtpService {
  @override
  Future<rd.Result<SmtpOAuthState>> connect({
    required String configId,
    required SmtpOAuthProvider provider,
  }) async => rd.Failure(Exception('unused'));

  @override
  Future<rd.Result<void>> disconnect({required String tokenKey}) async =>
      const rd.Success(unit);

  @override
  Future<rd.Result<SmtpOAuthState>> reconnect({
    required String configId,
    required SmtpOAuthProvider provider,
  }) async => rd.Failure(Exception('unused'));

  @override
  Future<rd.Result<String>> resolveValidAccessToken({
    required SmtpOAuthProvider provider,
    required String tokenKey,
  }) async => rd.Failure(Exception('unused'));
}

void main() {
  final runIntegration = Platform.environment['RUN_SMTP_INTEGRATION'] == '1';

  group('SMTP Mailpit integration', () {
    test(
      'sends email through local SMTP fake server',
      () async {
        final host = Platform.environment['SMTP_TEST_HOST'] ?? '127.0.0.1';
        final portRaw = Platform.environment['SMTP_TEST_PORT'] ?? '1025';
        final port = int.tryParse(portRaw) ?? 1025;
        final username = Platform.environment['SMTP_TEST_USERNAME'] ?? '';
        final password = Platform.environment['SMTP_TEST_PASSWORD'] ?? '';
        final fromEmail =
            Platform.environment['SMTP_TEST_FROM'] ??
            'backup-test@example.local';
        final toEmail =
            Platform.environment['SMTP_TEST_TO'] ?? 'dest@example.local';

        final config = EmailConfig(
          id: 'smtp-integration',
          configName: 'SMTP Integration',
          smtpServer: host,
          smtpPort: port,
          username: username,
          password: password,
          fromEmail: fromEmail,
          fromName: 'Backup Database',
          useSsl: false,
          recipients: [toEmail],
        );

        final service = EmailService(oauthSmtpService: _FakeOAuthSmtpService());
        final result = await service.sendEmail(
          config: config,
          subject: '[SMTP-TEST] Mailpit integration',
          body: 'Mensagem de teste de integracao SMTP',
        );

        expect(result.isSuccess(), isTrue);
      },
      skip: !runIntegration,
    );
  });
}
