import 'package:backup_database/application/providers/notification_provider.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/repositories/i_email_config_repository.dart';
import 'package:backup_database/domain/repositories/i_email_notification_target_repository.dart';
import 'package:backup_database/domain/use_cases/notifications/test_email_configuration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockEmailConfigRepository extends Mock
    implements IEmailConfigRepository {}

class _MockEmailNotificationTargetRepository extends Mock
    implements IEmailNotificationTargetRepository {}

class _MockTestEmailConfiguration extends Mock
    implements TestEmailConfiguration {}

void main() {
  late _MockEmailConfigRepository emailConfigRepository;
  late _MockEmailNotificationTargetRepository targetRepository;
  late _MockTestEmailConfiguration testEmailConfiguration;
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
    testEmailConfiguration = _MockTestEmailConfiguration();

    when(
      () => emailConfigRepository.getAll(),
    ).thenAnswer((_) async => const rd.Success(<EmailConfig>[]));
    when(
      () => targetRepository.getByConfigId(any()),
    ).thenAnswer((_) async => const rd.Success(<EmailNotificationTarget>[]));
    when(
      () => testEmailConfiguration(any()),
    ).thenAnswer((_) async => const rd.Success(true));

    provider = NotificationProvider(
      emailConfigRepository: emailConfigRepository,
      emailNotificationTargetRepository: targetRepository,
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
        when(
          () => emailConfigRepository.create(any()),
        ).thenAnswer((invocation) async {
          return rd.Success(
            invocation.positionalArguments.first as EmailConfig,
          );
        });

        final result = await provider.saveConfig(configA);

        expect(result, isTrue);
        expect(provider.selectedConfigId, configA.id);
        expect(provider.configs.length, 1);
        verify(() => emailConfigRepository.create(any())).called(1);
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
          contains('Nenhuma configuracao de e-mail definida'),
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
        expect(provider.error, contains('Destinatario nao encontrado'));
      },
    );
  });
}
