import 'dart:async';

import 'package:backup_database/application/providers/notification_provider.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/entities/email_test_audit.dart';
import 'package:backup_database/domain/entities/smtp_oauth_state.dart';
import 'package:backup_database/domain/repositories/i_email_config_repository.dart';
import 'package:backup_database/domain/repositories/i_email_notification_target_repository.dart';
import 'package:backup_database/domain/repositories/i_email_test_audit_repository.dart';
import 'package:backup_database/domain/services/i_oauth_smtp_service.dart';
import 'package:backup_database/domain/use_cases/notifications/test_email_configuration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockEmailConfigRepository extends Mock
    implements IEmailConfigRepository {}

class _MockEmailNotificationTargetRepository extends Mock
    implements IEmailNotificationTargetRepository {}

class _MockEmailTestAuditRepository extends Mock
    implements IEmailTestAuditRepository {}

class _MockTestEmailConfiguration extends Mock
    implements TestEmailConfiguration {}

class _MockOAuthSmtpService extends Mock implements IOAuthSmtpService {}

void main() {
  late _MockEmailConfigRepository emailConfigRepository;
  late _MockEmailNotificationTargetRepository targetRepository;
  late _MockEmailTestAuditRepository emailTestAuditRepository;
  late _MockTestEmailConfiguration testEmailConfiguration;
  late _MockOAuthSmtpService oauthSmtpService;
  late NotificationProvider provider;

  final configA = EmailConfig(
    id: 'config-a',
    configName: 'SMTP A',
    smtpServer: 'smtp-a.example.com',
    username: 'a@example.com',
    password: 'secret',
    recipients: const ['legacy-a@example.com'],
  );
  final configB = EmailConfig(
    id: 'config-b',
    configName: 'SMTP B',
    smtpServer: 'smtp-b.example.com',
    smtpPort: 465,
    username: 'b@example.com',
    password: 'secret',
    recipients: const ['legacy-b@example.com'],
  );

  final targetA = EmailNotificationTarget(
    id: 'target-a',
    emailConfigId: 'config-a',
    recipientEmail: 'destino-a@example.com',
    notifyOnWarning: false,
  );

  setUpAll(() {
    registerFallbackValue(configA);
    registerFallbackValue(targetA);
  });

  setUp(() {
    emailConfigRepository = _MockEmailConfigRepository();
    targetRepository = _MockEmailNotificationTargetRepository();
    emailTestAuditRepository = _MockEmailTestAuditRepository();
    testEmailConfiguration = _MockTestEmailConfiguration();
    oauthSmtpService = _MockOAuthSmtpService();

    when(
      () => emailConfigRepository.getAll(),
    ).thenAnswer((_) async => const rd.Success(<EmailConfig>[]));
    when(
      () => emailConfigRepository.saveWithPrimaryTarget(
        config: any(named: 'config'),
        primaryRecipientEmail: any(named: 'primaryRecipientEmail'),
      ),
    ).thenAnswer((invocation) async {
      return rd.Success(invocation.namedArguments[#config] as EmailConfig);
    });
    when(
      () => targetRepository.getByConfigId(any()),
    ).thenAnswer((_) async => const rd.Success(<EmailNotificationTarget>[]));
    when(
      () => testEmailConfiguration(any()),
    ).thenAnswer((_) async => const rd.Success(true));
    when(
      () => emailTestAuditRepository.getRecent(
        configId: any(named: 'configId'),
        startAt: any(named: 'startAt'),
        endAt: any(named: 'endAt'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => const rd.Success(<EmailTestAudit>[]));

    provider = NotificationProvider(
      emailConfigRepository: emailConfigRepository,
      emailNotificationTargetRepository: targetRepository,
      emailTestAuditRepository: emailTestAuditRepository,
      oauthSmtpService: oauthSmtpService,
      testEmailConfiguration: testEmailConfiguration,
    );
  });

  group('NotificationProvider multi-config', () {
    test(
      'loadConfigs keeps first config selected and loads its targets',
      () async {
        when(
          () => emailConfigRepository.getAll(),
        ).thenAnswer((_) async => rd.Success([configA, configB]));
        when(
          () => targetRepository.getByConfigId(configA.id),
        ).thenAnswer((_) async => rd.Success([targetA]));

        await provider.loadConfigs();

        expect(provider.configs.length, 2);
        expect(provider.selectedConfigId, configA.id);
        expect(provider.targets.length, 1);
        expect(provider.targets.first.recipientEmail, targetA.recipientEmail);
        expect(provider.error, isNull);
      },
    );

    test(
      'saveConfig uses create for a new config and refreshes selection',
      () async {
        when(
          () => emailConfigRepository.getAll(),
        ).thenAnswer((_) async => const rd.Success(<EmailConfig>[]));
        await provider.loadConfigs();

        when(
          () => emailConfigRepository.getAll(),
        ).thenAnswer((_) async => rd.Success([configA]));
        when(
          () => targetRepository.getByConfigId(configA.id),
        ).thenAnswer(
          (_) async => const rd.Success(<EmailNotificationTarget>[]),
        );
        final result = await provider.saveConfig(configA);

        expect(result, isTrue);
        expect(provider.selectedConfigId, configA.id);
        expect(provider.configs.length, 1);
        verify(
          () => emailConfigRepository.saveWithPrimaryTarget(
            config: any(named: 'config'),
            primaryRecipientEmail: configA.recipients.first,
          ),
        ).called(1);
      },
    );

    test(
      'saveConfig fails when there is no recipient and no legacy target',
      () async {
        final configWithoutRecipients = configA.copyWith(recipients: const []);

        when(
          () => targetRepository.getByConfigId(configWithoutRecipients.id),
        ).thenAnswer(
          (_) async => const rd.Success(<EmailNotificationTarget>[]),
        );

        final result = await provider.saveConfig(configWithoutRecipients);

        expect(result, isFalse);
        expect(
          provider.error,
          contains('Informe ao menos um e-mail destinatário'),
        );
        verifyNever(
          () => emailConfigRepository.saveWithPrimaryTarget(
            config: any(named: 'config'),
            primaryRecipientEmail: any(named: 'primaryRecipientEmail'),
          ),
        );
      },
    );

    test(
      'getPrimaryRecipientEmail falls back to notification target when config recipients are empty',
      () async {
        final configWithoutRecipients = configA.copyWith(recipients: const []);

        when(
          () => emailConfigRepository.getAll(),
        ).thenAnswer((_) async => rd.Success([configWithoutRecipients]));
        when(
          () => targetRepository.getByConfigId(configWithoutRecipients.id),
        ).thenAnswer((_) async => rd.Success([targetA]));

        await provider.loadConfigs();
        final recipient = await provider.getPrimaryRecipientEmail(
          configWithoutRecipients.id,
        );

        expect(recipient, targetA.recipientEmail);
      },
    );

    test('addTarget creates and reloads target list', () async {
      when(
        () => emailConfigRepository.getAll(),
      ).thenAnswer((_) async => rd.Success([configA]));

      var targetLoadCount = 0;
      when(() => targetRepository.getByConfigId(configA.id)).thenAnswer((
        _,
      ) async {
        targetLoadCount++;
        if (targetLoadCount == 1) {
          return const rd.Success(<EmailNotificationTarget>[]);
        }
        return rd.Success([targetA]);
      });

      when(
        () => targetRepository.create(any()),
      ).thenAnswer((_) async => rd.Success(targetA));

      await provider.loadConfigs();
      final result = await provider.addTarget(targetA);

      expect(result, isTrue);
      expect(provider.targets.length, 1);
      expect(provider.targets.first.id, targetA.id);
    });

    test(
      'testConfiguration returns false when no config is selected',
      () async {
        when(
          () => emailConfigRepository.getAll(),
        ).thenAnswer((_) async => const rd.Success(<EmailConfig>[]));

        await provider.loadConfigs();
        final result = await provider.testConfiguration();

        expect(result, isFalse);
        expect(
          provider.error,
          contains('Nenhuma configuração de e-mail definida'),
        );
        verifyNever(() => testEmailConfiguration(any()));
      },
    );

    test(
      'toggleTargetEnabled returns false when target does not exist',
      () async {
        when(
          () => emailConfigRepository.getAll(),
        ).thenAnswer((_) async => rd.Success([configA]));
        when(
          () => targetRepository.getByConfigId(configA.id),
        ).thenAnswer(
          (_) async => const rd.Success(<EmailNotificationTarget>[]),
        );

        await provider.loadConfigs();
        final result = await provider.toggleTargetEnabled(
          'missing-target',
          true,
        );

        expect(result, isFalse);
        expect(provider.error, contains('Destinatário não encontrado'));
      },
    );

    test(
      'testDraftConfiguration blocks concurrent execution for the same config id',
      () async {
        final completer = Completer<rd.Result<bool>>();
        when(
          () => testEmailConfiguration(any()),
        ).thenAnswer((_) => completer.future);

        final firstCall = provider.testDraftConfiguration(configA);
        final secondCall = await provider.testDraftConfiguration(configA);

        expect(secondCall, isFalse);
        expect(provider.error, contains('teste de conexão em execução'));
        expect(provider.isConfigUnderTest(configA.id), isTrue);

        completer.complete(const rd.Success(true));
        final firstResult = await firstCall;

        expect(firstResult, isTrue);
        expect(provider.isConfigUnderTest(configA.id), isFalse);
      },
    );

    test('connectOAuth returns updated config with OAuth metadata', () async {
      final oauthState = SmtpOAuthState(
        provider: SmtpOAuthProvider.google,
        accountEmail: 'oauth-user@example.com',
        tokenKey: 'oauth-token-key',
        connectedAt: DateTime.utc(2026, 2, 20, 18),
      );

      when(
        () => oauthSmtpService.connect(
          configId: configA.id,
          provider: SmtpOAuthProvider.google,
        ),
      ).thenAnswer((_) async => rd.Success(oauthState));

      final result = await provider.connectOAuth(
        config: configA,
        provider: SmtpOAuthProvider.google,
      );

      expect(result, isNotNull);
      expect(result!.authMode, SmtpAuthMode.oauthGoogle);
      expect(result.oauthProvider, SmtpOAuthProvider.google);
      expect(result.oauthTokenKey, 'oauth-token-key');
      expect(result.oauthAccountEmail, 'oauth-user@example.com');
      expect(provider.error, isNull);
    });

    test(
      'disconnectOAuth clears OAuth fields and switches to password mode',
      () async {
        final oauthConfig = configA.copyWith(
          authMode: SmtpAuthMode.oauthGoogle,
          oauthProvider: SmtpOAuthProvider.google,
          oauthTokenKey: 'oauth-token-key',
          oauthAccountEmail: 'oauth-user@example.com',
          oauthConnectedAt: DateTime.utc(2026, 2, 20, 18),
        );

        when(
          () => oauthSmtpService.disconnect(tokenKey: 'oauth-token-key'),
        ).thenAnswer((_) async => const rd.Success(unit));

        final result = await provider.disconnectOAuth(oauthConfig);

        expect(result.authMode, SmtpAuthMode.password);
        expect(result.oauthProvider, isNull);
        expect(result.oauthTokenKey, isNull);
        expect(result.oauthAccountEmail, isNull);
      },
    );
  });
}
