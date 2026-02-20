import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/repositories/i_email_config_repository.dart';
import 'package:backup_database/domain/repositories/i_email_notification_target_repository.dart';
import 'package:backup_database/domain/use_cases/notifications/get_email_notification_profiles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockEmailConfigRepository extends Mock
    implements IEmailConfigRepository {}

class _MockEmailNotificationTargetRepository extends Mock
    implements IEmailNotificationTargetRepository {}

void main() {
  late _MockEmailConfigRepository configRepository;
  late _MockEmailNotificationTargetRepository targetRepository;
  late GetEmailNotificationProfiles useCase;

  final configA = EmailConfig(
    id: 'config-a',
    configName: 'SMTP A',
    smtpServer: 'smtp.a.local',
    username: 'user@a.local',
    password: 'secret',
    recipients: const ['legacy@a.local'],
  );
  final configB = EmailConfig(
    id: 'config-b',
    configName: 'SMTP B',
    smtpServer: 'smtp.b.local',
    username: 'user@b.local',
    password: 'secret',
    recipients: const ['legacy@b.local'],
  );

  final targetA = EmailNotificationTarget(
    id: 'target-a',
    emailConfigId: 'config-a',
    recipientEmail: 'dest@a.local',
  );

  setUp(() {
    configRepository = _MockEmailConfigRepository();
    targetRepository = _MockEmailNotificationTargetRepository();

    useCase = GetEmailNotificationProfiles(
      emailConfigRepository: configRepository,
      targetRepository: targetRepository,
    );
  });

  group('GetEmailNotificationProfiles', () {
    test('returns profiles with targets for each config', () async {
      when(
        () => configRepository.getAll(),
      ).thenAnswer((_) async => rd.Success([configA, configB]));
      when(
        () => targetRepository.getByConfigId('config-a'),
      ).thenAnswer((_) async => rd.Success([targetA]));
      when(
        () => targetRepository.getByConfigId('config-b'),
      ).thenAnswer((_) async => const rd.Success([]));

      final result = await useCase();

      expect(result.isSuccess(), isTrue);
      result.fold(
        (profiles) {
          expect(profiles.length, 2);
          expect(profiles.first.config.id, 'config-a');
          expect(profiles.first.targets.length, 1);
          expect(profiles.first.hasEnabledTargets, isTrue);
          expect(profiles.last.config.id, 'config-b');
          expect(profiles.last.targets, isEmpty);
          expect(profiles.last.hasEnabledTargets, isFalse);
        },
        (failure) => fail('Nao deveria falhar: $failure'),
      );
    });

    test('keeps profile when target fetch fails for one config', () async {
      when(
        () => configRepository.getAll(),
      ).thenAnswer((_) async => rd.Success([configA]));
      when(
        () => targetRepository.getByConfigId('config-a'),
      ).thenAnswer(
        (_) async => const rd.Failure(DatabaseFailure(message: 'target fail')),
      );

      final result = await useCase();

      expect(result.isSuccess(), isTrue);
      result.fold(
        (profiles) {
          expect(profiles.length, 1);
          expect(profiles.first.targets, isEmpty);
        },
        (failure) => fail('Nao deveria falhar: $failure'),
      );
    });

    test('returns failure when config list fails', () async {
      when(
        () => configRepository.getAll(),
      ).thenAnswer(
        (_) async => const rd.Failure(DatabaseFailure(message: 'config fail')),
      );

      final result = await useCase();

      expect(result.isError(), isTrue);
      expect(
        result.exceptionOrNull().toString(),
        contains('Erro ao carregar perfis de notificacao'),
      );
    });
  });
}
