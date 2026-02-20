import 'package:backup_database/application/services/notification_service.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/repositories/i_backup_log_repository.dart';
import 'package:backup_database/domain/repositories/i_email_config_repository.dart';
import 'package:backup_database/domain/repositories/i_email_notification_target_repository.dart';
import 'package:backup_database/domain/services/i_email_service.dart';
import 'package:backup_database/domain/services/i_license_validation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockEmailConfigRepository extends Mock
    implements IEmailConfigRepository {}

class _MockEmailNotificationTargetRepository extends Mock
    implements IEmailNotificationTargetRepository {}

class _MockBackupLogRepository extends Mock implements IBackupLogRepository {}

class _MockEmailService extends Mock implements IEmailService {}

class _MockLicenseValidationService extends Mock
    implements ILicenseValidationService {}

void main() {
  late _MockEmailConfigRepository emailConfigRepository;
  late _MockEmailNotificationTargetRepository targetRepository;
  late _MockBackupLogRepository backupLogRepository;
  late _MockEmailService emailService;
  late _MockLicenseValidationService licenseValidationService;
  late NotificationService service;

  final baseConfig = EmailConfig(
    id: 'config-1',
    configName: 'SMTP Principal',
    smtpServer: 'smtp.example.com',
    username: 'user@example.com',
    password: 'secret',
    recipients: const ['legacy@example.com'],
  );

  final successHistory = BackupHistory(
    id: 'history-1',
    scheduleId: 'schedule-1',
    databaseName: 'Base',
    databaseType: 'sqlServer',
    backupPath: r'C:\tmp\base.bak',
    fileSize: 1024,
    status: BackupStatus.success,
    startedAt: DateTime(2026, 2, 20, 10),
  );

  setUpAll(() {
    registerFallbackValue(baseConfig);
    registerFallbackValue(successHistory);
  });

  setUp(() {
    emailConfigRepository = _MockEmailConfigRepository();
    targetRepository = _MockEmailNotificationTargetRepository();
    backupLogRepository = _MockBackupLogRepository();
    emailService = _MockEmailService();
    licenseValidationService = _MockLicenseValidationService();

    when(
      () => licenseValidationService.isFeatureAllowed(any()),
    ).thenAnswer((_) async => const rd.Success(true));

    when(
      () => backupLogRepository.getByBackupHistory(any()),
    ).thenAnswer((_) async => const rd.Success([]));

    service = NotificationService(
      emailConfigRepository: emailConfigRepository,
      emailNotificationTargetRepository: targetRepository,
      backupLogRepository: backupLogRepository,
      emailService: emailService,
      licenseValidationService: licenseValidationService,
    );
  });

  group('NotificationService.notifyBackupComplete', () {
    test(
      'returns false and skips sending when license does not allow email',
      () async {
        when(
          () => licenseValidationService.isFeatureAllowed(any()),
        ).thenAnswer((_) async => const rd.Success(false));

        final result = await service.notifyBackupComplete(successHistory);

        expect(result.isSuccess(), isTrue);
        expect(result.getOrElse((_) => true), isFalse);
        verifyNever(() => emailConfigRepository.getAll());
        verifyNever(
          () => emailService.sendBackupSuccessNotification(
            config: any(named: 'config'),
            history: any(named: 'history'),
            logPath: any(named: 'logPath'),
          ),
        );
      },
    );

    test(
      'continues after a target failure and returns success when at least one send succeeds',
      () async {
        final targets = [
          EmailNotificationTarget(
            id: 'target-fail',
            emailConfigId: baseConfig.id,
            recipientEmail: 'fail@example.com',
          ),
          EmailNotificationTarget(
            id: 'target-ok',
            emailConfigId: baseConfig.id,
            recipientEmail: 'ok@example.com',
          ),
          EmailNotificationTarget(
            id: 'target-skip',
            emailConfigId: baseConfig.id,
            recipientEmail: 'skip@example.com',
            notifyOnSuccess: false,
          ),
        ];

        when(
          () => emailConfigRepository.getAll(),
        ).thenAnswer((_) async => rd.Success([baseConfig]));
        when(
          () => targetRepository.getByConfigId(baseConfig.id),
        ).thenAnswer((_) async => rd.Success(targets));

        when(
          () => emailService.sendBackupSuccessNotification(
            config: any(named: 'config'),
            history: any(named: 'history'),
            logPath: any(named: 'logPath'),
          ),
        ).thenAnswer((invocation) async {
          final config = invocation.namedArguments[#config]! as EmailConfig;
          if (config.recipients.first == 'fail@example.com') {
            return const rd.Failure(DatabaseFailure(message: 'smtp fail'));
          }
          return const rd.Success(true);
        });

        final result = await service.notifyBackupComplete(successHistory);

        expect(result.isSuccess(), isTrue);
        expect(result.getOrElse((_) => false), isTrue);

        final capturedConfigs = verify(
          () => emailService.sendBackupSuccessNotification(
            config: captureAny(named: 'config'),
            history: any(named: 'history'),
            logPath: any(named: 'logPath'),
          ),
        ).captured.cast<EmailConfig>();

        final recipients = capturedConfigs
            .map((config) => config.recipients.first)
            .toSet();
        expect(recipients, equals({'fail@example.com', 'ok@example.com'}));
      },
    );

    test(
      'returns failure when target query fails and does not use legacy fallback',
      () async {
        when(
          () => emailConfigRepository.getAll(),
        ).thenAnswer((_) async => rd.Success([baseConfig]));

        when(
          () => targetRepository.getByConfigId(baseConfig.id),
        ).thenAnswer(
          (_) async => const rd.Failure(DatabaseFailure(message: 'db fail')),
        );

        when(
          () => emailService.sendBackupSuccessNotification(
            config: any(named: 'config'),
            history: any(named: 'history'),
            logPath: any(named: 'logPath'),
          ),
        ).thenAnswer((_) async => const rd.Success(true));

        final result = await service.notifyBackupComplete(successHistory);

        expect(result.isSuccess(), isFalse);
        verifyNever(
          () => emailService.sendBackupSuccessNotification(
            config: any(named: 'config'),
            history: any(named: 'history'),
            logPath: any(named: 'logPath'),
          ),
        );
      },
    );
  });

  group('NotificationService.sendWarning', () {
    test(
      'sends warning only for enabled targets with notifyOnWarning=true',
      () async {
        final targets = [
          EmailNotificationTarget(
            id: 'warning-false',
            emailConfigId: baseConfig.id,
            recipientEmail: 'off@example.com',
            notifyOnWarning: false,
          ),
          EmailNotificationTarget(
            id: 'warning-true',
            emailConfigId: baseConfig.id,
            recipientEmail: 'on@example.com',
          ),
          EmailNotificationTarget(
            id: 'warning-disabled',
            emailConfigId: baseConfig.id,
            recipientEmail: 'disabled@example.com',
            enabled: false,
          ),
        ];

        when(
          () => emailConfigRepository.getAll(),
        ).thenAnswer((_) async => rd.Success([baseConfig]));
        when(
          () => targetRepository.getByConfigId(baseConfig.id),
        ).thenAnswer((_) async => rd.Success(targets));
        when(
          () => emailService.sendBackupWarningNotification(
            config: any(named: 'config'),
            databaseName: any(named: 'databaseName'),
            warningMessage: any(named: 'warningMessage'),
            logPath: any(named: 'logPath'),
          ),
        ).thenAnswer((_) async => const rd.Success(true));

        final result = await service.sendWarning(
          databaseName: 'Base',
          message: 'espaco em disco baixo',
        );

        expect(result.isSuccess(), isTrue);
        expect(result.getOrElse((_) => false), isTrue);

        final capturedConfig =
            verify(
                  () => emailService.sendBackupWarningNotification(
                    config: captureAny(named: 'config'),
                    databaseName: any(named: 'databaseName'),
                    warningMessage: any(named: 'warningMessage'),
                    logPath: any(named: 'logPath'),
                  ),
                ).captured.single
                as EmailConfig;

        expect(capturedConfig.recipients, equals(const ['on@example.com']));
      },
    );
  });

  group('NotificationService.sendTestEmail', () {
    test('uses the recipient passed to sendTestEmail', () async {
      when(
        () => emailConfigRepository.get(),
      ).thenAnswer((_) async => rd.Success(baseConfig));

      when(
        () => emailService.sendEmail(
          config: any(named: 'config'),
          subject: any(named: 'subject'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => const rd.Success(true));

      final result = await service.sendTestEmail(
        'destino@exemplo.com',
        'Assunto Teste',
      );

      expect(result.isSuccess(), isTrue);

      final capturedConfig =
          verify(
                () => emailService.sendEmail(
                  config: captureAny(named: 'config'),
                  subject: any(named: 'subject'),
                  body: any(named: 'body'),
                ),
              ).captured.single
              as EmailConfig;

      expect(capturedConfig.recipients, equals(const ['destino@exemplo.com']));
    });
  });
}
