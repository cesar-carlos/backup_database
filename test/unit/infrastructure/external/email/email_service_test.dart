import 'dart:io';

import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/smtp_oauth_state.dart';
import 'package:backup_database/domain/services/i_oauth_smtp_service.dart';
import 'package:backup_database/infrastructure/external/email/email_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _FakeOAuthSmtpService implements IOAuthSmtpService {
  _FakeOAuthSmtpService({this.accessTokenResult});

  final rd.Result<String>? accessTokenResult;
  SmtpOAuthProvider? lastProvider;
  String? lastTokenKey;

  @override
  Future<rd.Result<SmtpOAuthState>> connect({
    required String configId,
    required SmtpOAuthProvider provider,
  }) async {
    return rd.Failure(Exception('unused'));
  }

  @override
  Future<rd.Result<void>> disconnect({required String tokenKey}) async {
    return const rd.Success(unit);
  }

  @override
  Future<rd.Result<SmtpOAuthState>> reconnect({
    required String configId,
    required SmtpOAuthProvider provider,
  }) async {
    return rd.Failure(Exception('unused'));
  }

  @override
  Future<rd.Result<String>> resolveValidAccessToken({
    required SmtpOAuthProvider provider,
    required String tokenKey,
  }) async {
    lastProvider = provider;
    lastTokenKey = tokenKey;
    return accessTokenResult ?? rd.Failure(Exception('unused'));
  }
}

void main() {
  EmailConfig buildConfig() {
    return EmailConfig(
      id: 'cfg-1',
      configName: 'SMTP Test',
      smtpServer: 'smtp.example.com',
      username: 'smtp-user@example.com',
      password: 'super-secret',
      fromEmail: 'sender@example.com',
      fromName: 'Backup Database',
      recipients: const ['destino@example.com'],
    );
  }

  SendReport buildReport() {
    final message = Message()
      ..from = const Address('sender@example.com', 'Backup Database')
      ..recipients.add('destino@example.com')
      ..subject = 'Teste'
      ..text = 'Body';
    final now = DateTime.now();
    return SendReport(message, now, now, now);
  }

  group('EmailService.sendEmail', () {
    test('retries for transient socket failures and succeeds later', () async {
      var attempts = 0;
      var delayCalls = 0;

      final service = EmailService(
        oauthSmtpService: _FakeOAuthSmtpService(),
        smtpSendFn:
            (
              Message _,
              SmtpServer _, {
              Duration? timeout,
            }) async {
              attempts++;
              if (attempts < 3) {
                throw const SocketException('connection reset by peer');
              }
              return buildReport();
            },
        retryDelayFn: (_) async {
          delayCalls++;
        },
      );

      final result = await service.sendEmail(
        config: buildConfig(),
        subject: 'Assunto',
        body: 'Mensagem',
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrElse((_) => false), isTrue);
      expect(attempts, 3);
      expect(delayCalls, 2);
    });

    test('does not retry on SMTP authentication failure', () async {
      var attempts = 0;
      var delayCalls = 0;

      final service = EmailService(
        oauthSmtpService: _FakeOAuthSmtpService(),
        smtpSendFn:
            (
              Message _,
              SmtpServer _, {
              Duration? timeout,
            }) async {
              attempts++;
              throw SmtpClientAuthenticationException(
                '535 Authentication failed',
              );
            },
        retryDelayFn: (_) async {
          delayCalls++;
        },
      );

      final result = await service.sendEmail(
        config: buildConfig(),
        subject: 'Assunto',
        body: 'Mensagem',
      );

      expect(result.isError(), isTrue);
      expect(
        result.exceptionOrNull().toString().toLowerCase(),
        contains('autenticacao smtp'),
      );
      expect(attempts, 1);
      expect(delayCalls, 0);
    });

    test('retries for SMTP 4xx communication failures', () async {
      var attempts = 0;
      var delayCalls = 0;

      final service = EmailService(
        oauthSmtpService: _FakeOAuthSmtpService(),
        smtpSendFn:
            (
              Message _,
              SmtpServer _, {
              Duration? timeout,
            }) async {
              attempts++;
              if (attempts == 1) {
                throw SmtpClientCommunicationException('421 Temporary failure');
              }
              return buildReport();
            },
        retryDelayFn: (_) async {
          delayCalls++;
        },
      );

      final result = await service.sendEmail(
        config: buildConfig(),
        subject: 'Assunto',
        body: 'Mensagem',
      );

      expect(result.isSuccess(), isTrue);
      expect(attempts, 2);
      expect(delayCalls, 1);
    });

    test('does not retry for SMTP 5xx communication failures', () async {
      var attempts = 0;
      var delayCalls = 0;

      final service = EmailService(
        oauthSmtpService: _FakeOAuthSmtpService(),
        smtpSendFn:
            (
              Message _,
              SmtpServer _, {
              Duration? timeout,
            }) async {
              attempts++;
              throw SmtpClientCommunicationException('550 Mailbox unavailable');
            },
        retryDelayFn: (_) async {
          delayCalls++;
        },
      );

      final result = await service.sendEmail(
        config: buildConfig(),
        subject: 'Assunto',
        body: 'Mensagem',
      );

      expect(result.isError(), isTrue);
      expect(attempts, 1);
      expect(delayCalls, 0);
    });

    test('redacts sensitive values in returned error message', () async {
      final service = EmailService(
        oauthSmtpService: _FakeOAuthSmtpService(),
        smtpSendFn:
            (
              Message _,
              SmtpServer _, {
              Duration? timeout,
            }) async {
              throw Exception('password=abc123 token:xyz987 secret=qwe999');
            },
      );

      final result = await service.sendEmail(
        config: buildConfig(),
        subject: 'Assunto',
        body: 'Mensagem',
      );

      expect(result.isError(), isTrue);
      final message = result.exceptionOrNull().toString().toLowerCase();
      expect(message, contains('<redacted>'));
      expect(message, isNot(contains('abc123')));
      expect(message, isNot(contains('xyz987')));
      expect(message, isNot(contains('qwe999')));
    });

    test('returns validation failure when recipients list is empty', () async {
      var attempts = 0;
      final service = EmailService(
        oauthSmtpService: _FakeOAuthSmtpService(),
        smtpSendFn:
            (
              Message _,
              SmtpServer _, {
              Duration? timeout,
            }) async {
              attempts++;
              return buildReport();
            },
      );

      final result = await service.sendEmail(
        config: buildConfig().copyWith(recipients: const []),
        subject: 'Assunto',
        body: 'Mensagem',
      );

      expect(result.isError(), isTrue);
      expect(
        result.exceptionOrNull().toString(),
        contains('Nenhum destinatario'),
      );
      expect(attempts, 0);
    });

    test('uses XOAUTH2 when auth mode is OAuth', () async {
      final oauthService = _FakeOAuthSmtpService(
        accessTokenResult: const rd.Success('oauth-access-token'),
      );

      SmtpServer? capturedServer;
      final service = EmailService(
        oauthSmtpService: oauthService,
        smtpSendFn:
            (
              Message _,
              SmtpServer smtpServer, {
              Duration? timeout,
            }) async {
              capturedServer = smtpServer;
              return buildReport();
            },
      );

      final oauthConfig = buildConfig().copyWith(
        authMode: SmtpAuthMode.oauthGoogle,
        oauthProvider: SmtpOAuthProvider.google,
        oauthTokenKey: 'oauth-key-1',
        oauthAccountEmail: 'oauth-user@example.com',
      );

      final result = await service.sendEmail(
        config: oauthConfig,
        subject: 'Assunto',
        body: 'Mensagem',
      );

      expect(result.isSuccess(), isTrue);
      expect(oauthService.lastProvider, SmtpOAuthProvider.google);
      expect(oauthService.lastTokenKey, 'oauth-key-1');
      expect(capturedServer, isNotNull);
      expect(capturedServer!.xoauth2Token, isNotNull);
      expect(capturedServer!.xoauth2Token, isNotEmpty);
      expect(capturedServer!.username, isNull);
      expect(capturedServer!.password, isNull);
    });
  });
}
