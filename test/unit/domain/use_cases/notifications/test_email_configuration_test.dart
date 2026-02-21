import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/services/i_notification_service.dart';
import 'package:backup_database/domain/use_cases/notifications/test_email_configuration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockNotificationService extends Mock implements INotificationService {}

void main() {
  late _MockNotificationService notificationService;
  late TestEmailConfiguration useCase;

  final config = EmailConfig(
    id: 'config-1',
    configName: 'SMTP Principal',
    smtpServer: 'smtp.example.com',
    username: 'smtp@example.com',
    password: 'secret',
    recipients: const [],
  );

  setUpAll(() {
    registerFallbackValue(config);
  });

  setUp(() {
    notificationService = _MockNotificationService();
    useCase = TestEmailConfiguration(notificationService);
  });

  test(
    'calls notificationService.testEmailConfiguration with provided config',
    () async {
      when(
        () => notificationService.testEmailConfiguration(any()),
      ).thenAnswer((_) async => const rd.Success(true));

      final result = await useCase(config);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrElse((_) => false), isTrue);
      verify(
        () => notificationService.testEmailConfiguration(config),
      ).called(1);
      verifyNever(
        () => notificationService.sendTestEmail(any(), any()),
      );
    },
  );

  test(
    'propagates failure from notificationService.testEmailConfiguration',
    () async {
      when(
        () => notificationService.testEmailConfiguration(any()),
      ).thenAnswer(
        (_) async => const rd.Failure(
          ValidationFailure(message: 'Falha de validacao'),
        ),
      );

      final result = await useCase(config);

      expect(result.isError(), isTrue);
    },
  );
}
