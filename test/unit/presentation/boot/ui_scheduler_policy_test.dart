import 'package:backup_database/domain/services/i_windows_service_service.dart';
import 'package:backup_database/presentation/boot/ui_scheduler_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class MockWindowsServiceService extends Mock
    implements IWindowsServiceService {}

void main() {
  group('UiSchedulerPolicy', () {
    late MockWindowsServiceService mockWindowsServiceService;

    setUp(() {
      mockWindowsServiceService = MockWindowsServiceService();
    });

    test(
      'should return false and skip service status lookup when not windows',
      () async {
        final policy = UiSchedulerPolicy(
          mockWindowsServiceService,
          isWindows: false,
        );

        final shouldSkipScheduler = await policy.shouldSkipSchedulerInUiMode();

        expect(shouldSkipScheduler, isFalse);
        verifyNever(() => mockWindowsServiceService.getStatus());
      },
    );

    test(
      'should return true when service is installed and running',
      () async {
        when(
          () => mockWindowsServiceService.getStatus(),
        ).thenAnswer(
          (_) async => const rd.Success(
            WindowsServiceStatus(
              isInstalled: true,
              isRunning: true,
            ),
          ),
        );

        final policy = UiSchedulerPolicy(
          mockWindowsServiceService,
          isWindows: true,
        );
        final shouldSkipScheduler = await policy.shouldSkipSchedulerInUiMode();

        expect(shouldSkipScheduler, isTrue);
        verify(() => mockWindowsServiceService.getStatus()).called(1);
      },
    );

    test(
      'should return false when service is installed but not running',
      () async {
        when(
          () => mockWindowsServiceService.getStatus(),
        ).thenAnswer(
          (_) async => const rd.Success(
            WindowsServiceStatus(
              isInstalled: true,
              isRunning: false,
            ),
          ),
        );

        final policy = UiSchedulerPolicy(
          mockWindowsServiceService,
          isWindows: true,
        );
        final shouldSkipScheduler = await policy.shouldSkipSchedulerInUiMode();

        expect(shouldSkipScheduler, isFalse);
        verify(() => mockWindowsServiceService.getStatus()).called(1);
      },
    );

    test(
      'should return false and log warning when status query returns failure',
      () async {
        final warnings = <String>[];
        when(
          () => mockWindowsServiceService.getStatus(),
        ).thenAnswer(
          (_) async => rd.Failure(Exception('status failure')),
        );

        final policy = UiSchedulerPolicy(
          mockWindowsServiceService,
          isWindows: true,
          onWarning: warnings.add,
        );
        final shouldSkipScheduler = await policy.shouldSkipSchedulerInUiMode();

        expect(shouldSkipScheduler, isFalse);
        expect(warnings, hasLength(1));
        expect(
          warnings.first,
          contains('Nao foi possivel consultar status do servico'),
        );
      },
    );

    test(
      'should return true on failure when fallback mode is failSafe',
      () async {
        final warnings = <String>[];
        when(
          () => mockWindowsServiceService.getStatus(),
        ).thenAnswer(
          (_) async => rd.Failure(Exception('status failure')),
        );

        final policy = UiSchedulerPolicy(
          mockWindowsServiceService,
          isWindows: true,
          onWarning: warnings.add,
          fallbackMode: UiSchedulerFallbackMode.failSafe,
        );
        final shouldSkipScheduler = await policy.shouldSkipSchedulerInUiMode();

        expect(shouldSkipScheduler, isTrue);
        expect(warnings, hasLength(1));
      },
    );

    test(
      'should return false and log warning when status query throws',
      () async {
        final warnings = <String>[];
        when(
          () => mockWindowsServiceService.getStatus(),
        ).thenThrow(Exception('query crash'));

        final policy = UiSchedulerPolicy(
          mockWindowsServiceService,
          isWindows: true,
          onWarning: warnings.add,
        );
        final shouldSkipScheduler = await policy.shouldSkipSchedulerInUiMode();

        expect(shouldSkipScheduler, isFalse);
        expect(warnings, hasLength(1));
        expect(
          warnings.first,
          contains('Falha ao verificar servico do Windows'),
        );
      },
    );

    test(
      'should return true on exception when fallback mode is failSafe',
      () async {
        final warnings = <String>[];
        when(
          () => mockWindowsServiceService.getStatus(),
        ).thenThrow(Exception('query crash'));

        final policy = UiSchedulerPolicy(
          mockWindowsServiceService,
          isWindows: true,
          onWarning: warnings.add,
          fallbackMode: UiSchedulerFallbackMode.failSafe,
        );
        final shouldSkipScheduler = await policy.shouldSkipSchedulerInUiMode();

        expect(shouldSkipScheduler, isTrue);
        expect(warnings, hasLength(1));
      },
    );
  });
}
