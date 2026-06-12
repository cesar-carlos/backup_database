import 'package:backup_database/application/providers/backup_progress_provider.dart';
import 'package:backup_database/application/providers/remote_file_transfer_provider.dart';
import 'package:backup_database/application/providers/remote_schedules_provider.dart';
import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:backup_database/domain/services/i_elevation_probe.dart';
import 'package:backup_database/presentation/boot/app_initializer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

class _MockBackupProgress extends Mock implements BackupProgressProvider {}

class _MockRemoteSchedules extends Mock implements RemoteSchedulesProvider {}

class _MockRemoteFileTransfer extends Mock
    implements RemoteFileTransferProvider {}

class _MockElevationProbe extends Mock implements IElevationProbe {}

void main() {
  group('checkInstallReadiness', () {
    late GetIt locator;

    setUp(() {
      locator = GetIt.asNewInstance();
    });

    test('returns null when no provider reports activity', () async {
      final backup = _MockBackupProgress();
      when(() => backup.isRunning).thenReturn(false);
      when(() => backup.currentBackupName).thenReturn(null);

      final remote = _MockRemoteSchedules();
      when(() => remote.isExecuting).thenReturn(false);

      final transfer = _MockRemoteFileTransfer();
      when(() => transfer.isTransferring).thenReturn(false);

      locator
        ..registerSingleton<BackupProgressProvider>(backup)
        ..registerSingleton<RemoteSchedulesProvider>(remote)
        ..registerSingleton<RemoteFileTransferProvider>(transfer);

      expect(await checkInstallReadiness(getIt: locator), isNull);
    });

    test(
      'blocks update when a local UI backup is running (with name)',
      () async {
        final backup = _MockBackupProgress();
        when(() => backup.isRunning).thenReturn(true);
        when(() => backup.currentBackupName).thenReturn('Daily Production');
        locator.registerSingleton<BackupProgressProvider>(backup);

        final outcome = await checkInstallReadiness(getIt: locator);

        expect(outcome, isNotNull);
        expect(outcome!.reason, AppUpdateBlockReason.localBackupRunning);
        expect(outcome.message, contains('Daily Production'));
        expect(outcome.message, contains('Aguarde'));
      },
    );

    test(
      'blocks update when a local UI backup is running (without name)',
      () async {
        final backup = _MockBackupProgress();
        when(() => backup.isRunning).thenReturn(true);
        when(() => backup.currentBackupName).thenReturn(null);
        locator.registerSingleton<BackupProgressProvider>(backup);

        final outcome = await checkInstallReadiness(getIt: locator);

        expect(outcome, isNotNull);
        expect(outcome!.reason, AppUpdateBlockReason.localBackupRunning);
        expect(outcome.message, contains('na UI'));
      },
    );

    test(
      'blocks update when a REMOTE backup is executing (client mode)',
      () async {
        // §audit-2026-05-28: cenario central do modo cliente — o backup
        // roda no servidor. Antes da correcao, `isExecuting` no remote
        // provider era invisivel para o readiness check.
        final backup = _MockBackupProgress();
        when(() => backup.isRunning).thenReturn(false);

        final remote = _MockRemoteSchedules();
        when(() => remote.isExecuting).thenReturn(true);

        locator
          ..registerSingleton<BackupProgressProvider>(backup)
          ..registerSingleton<RemoteSchedulesProvider>(remote);

        final outcome = await checkInstallReadiness(getIt: locator);

        expect(outcome, isNotNull);
        expect(outcome!.reason, AppUpdateBlockReason.remoteBackupRunning);
        expect(outcome.message, contains('backup remoto'));
      },
    );

    test(
      'blocks update when a file transfer from server is in progress',
      () async {
        final backup = _MockBackupProgress();
        when(() => backup.isRunning).thenReturn(false);

        final remote = _MockRemoteSchedules();
        when(() => remote.isExecuting).thenReturn(false);

        final transfer = _MockRemoteFileTransfer();
        when(() => transfer.isTransferring).thenReturn(true);

        locator
          ..registerSingleton<BackupProgressProvider>(backup)
          ..registerSingleton<RemoteSchedulesProvider>(remote)
          ..registerSingleton<RemoteFileTransferProvider>(transfer);

        final outcome = await checkInstallReadiness(getIt: locator);

        expect(outcome, isNotNull);
        expect(outcome!.reason, AppUpdateBlockReason.fileTransferActive);
        expect(outcome.message, contains('transferência'));
      },
    );

    test('returns null when providers are NOT registered', () async {
      // Caminho defensivo: nem todos os ambientes (testes, headless)
      // têm os providers remotos registrados. O check deve degradar
      // graciosamente — checa só o que existe.
      expect(await checkInstallReadiness(getIt: locator), isNull);
    });

    test(
      'blocks update when readiness provider throws (fail-closed)',
      () async {
        final backup = _MockBackupProgress();
        when(() => backup.isRunning).thenThrow(StateError('provider down'));
        locator.registerSingleton<BackupProgressProvider>(backup);

        final outcome = await checkInstallReadiness(getIt: locator);

        expect(outcome, isNotNull);
        expect(
          outcome!.reason,
          AppUpdateBlockReason.readinessCheckUnavailable,
        );
        expect(outcome.message, contains('Não foi possível verificar'));
      },
    );

    test('local UI backup takes precedence over remote ones', () async {
      // Determinismo: se ambos local e remoto estiverem ativos, o
      // local ganha porque é o caminho mais critico (UI vai sumir
      // imediatamente no relaunch).
      final backup = _MockBackupProgress();
      when(() => backup.isRunning).thenReturn(true);
      when(() => backup.currentBackupName).thenReturn('Local');

      final remote = _MockRemoteSchedules();
      when(() => remote.isExecuting).thenReturn(true);

      locator
        ..registerSingleton<BackupProgressProvider>(backup)
        ..registerSingleton<RemoteSchedulesProvider>(remote);

      final outcome = await checkInstallReadiness(getIt: locator);

      expect(outcome!.reason, AppUpdateBlockReason.localBackupRunning);
      expect(outcome.message, contains('Local'));
    });
  });

  // -------------------------------------------------------------------
  // §audit-2026-05-28 wave 4: gate UAC
  // -------------------------------------------------------------------

  group('checkInstallReadiness — UAC gate', () {
    late GetIt locator;

    setUp(() {
      locator = GetIt.asNewInstance();
    });

    /// Quando UAC ativo + processo não-elevado + checagem AUTOMÁTICA
    /// (`periodic` ou `startup`), o auto-update deve ser **bloqueado**
    /// com mensagem amigável instruindo update manual.
    test(
      'blocks automatic update (periodic) when UAC would trigger prompt',
      () async {
        final probe = _MockElevationProbe();
        when(probe.probe).thenAnswer(
          (_) async => const ElevationSnapshot(
            uacEnabled: true,
            processIsElevated: false,
          ),
        );
        locator.registerSingleton<IElevationProbe>(probe);

        final outcome = await checkInstallReadiness(
          getIt: locator,
          source: AppUpdateSource.periodic,
        );

        expect(outcome, isNotNull);
        expect(outcome!.reason, AppUpdateBlockReason.uacPolicy);
        expect(outcome.message, contains('UAC'));
        expect(outcome.message, contains('Atualizar agora'));
        verify(probe.probe).called(1);
      },
    );

    test(
      'blocks automatic update (startup) when UAC would trigger prompt',
      () async {
        final probe = _MockElevationProbe();
        when(probe.probe).thenAnswer(
          (_) async => const ElevationSnapshot(
            uacEnabled: true,
            processIsElevated: false,
          ),
        );
        locator.registerSingleton<IElevationProbe>(probe);

        final outcome = await checkInstallReadiness(
          getIt: locator,
          source: AppUpdateSource.startup,
        );

        expect(outcome, isNotNull);
        expect(outcome!.reason, AppUpdateBlockReason.uacPolicy);
        expect(outcome.message, contains('UAC'));
      },
    );

    /// `manual` significa o usuário clicou "Atualizar agora" — está
    /// pronto para confirmar o prompt UAC. Não bloqueamos, e nem
    /// precisamos consultar o probe.
    test(
      'manual update is NOT blocked even when UAC would trigger prompt',
      () async {
        final probe = _MockElevationProbe();
        when(probe.probe).thenAnswer(
          (_) async => const ElevationSnapshot(
            uacEnabled: true,
            processIsElevated: false,
          ),
        );
        locator.registerSingleton<IElevationProbe>(probe);

        // §audit: o teste é PRECISAMENTE sobre o source `manual` não
        // disparar o gate UAC. Usamos o default da função
        // (`AppUpdateSource.manual`) — mudar o default no futuro deve
        // **quebrar** este teste explicitamente.
        final outcome = await checkInstallReadiness(getIt: locator);

        expect(outcome, isNull);
        verifyNever(probe.probe);
      },
    );

    test('passes when UAC is disabled (any source)', () async {
      final probe = _MockElevationProbe();
      when(probe.probe).thenAnswer(
        (_) async => const ElevationSnapshot(
          uacEnabled: false,
          processIsElevated: false,
        ),
      );
      locator.registerSingleton<IElevationProbe>(probe);

      expect(
        await checkInstallReadiness(
          getIt: locator,
          source: AppUpdateSource.periodic,
        ),
        isNull,
      );
    });

    test(
      "passes when process IS elevated (UAC prompt won't fire)",
      () async {
        final probe = _MockElevationProbe();
        when(probe.probe).thenAnswer(
          (_) async => const ElevationSnapshot(
            uacEnabled: true,
            processIsElevated: true,
          ),
        );
        locator.registerSingleton<IElevationProbe>(probe);

        expect(
          await checkInstallReadiness(
            getIt: locator,
            source: AppUpdateSource.periodic,
          ),
          isNull,
        );
      },
    );

    test(
      'passes when probe returns unknown (defensive fail-open documented)',
      () async {
        // Bandeira `wouldTriggerUacPrompt` é `false` quando qualquer
        // bit é `null` — preferimos correr o risco de um prompt UAC
        // silencioso a bloquear update legítimo em máquinas onde a
        // detecção falha (sem registry, PS quebrado, etc.).
        final probe = _MockElevationProbe();
        when(probe.probe).thenAnswer(
          (_) async => const ElevationSnapshot(
            uacEnabled: null,
            processIsElevated: null,
          ),
        );
        locator.registerSingleton<IElevationProbe>(probe);

        expect(
          await checkInstallReadiness(
            getIt: locator,
            source: AppUpdateSource.periodic,
          ),
          isNull,
        );
      },
    );

    test(
      'no probe registered → passes (degrades gracefully on headless setups)',
      () async {
        expect(
          await checkInstallReadiness(
            getIt: locator,
            source: AppUpdateSource.periodic,
          ),
          isNull,
        );
      },
    );

    test(
      'active backup takes precedence over UAC gate (no probe call)',
      () async {
        // Se já vai bloquear por backup ativo, nem perde tempo
        // perguntando ao probe (preserva bateria + reduz log).
        final backup = _MockBackupProgress();
        when(() => backup.isRunning).thenReturn(true);
        when(() => backup.currentBackupName).thenReturn('Critical');

        final probe = _MockElevationProbe();
        when(probe.probe).thenAnswer(
          (_) async => const ElevationSnapshot(
            uacEnabled: true,
            processIsElevated: false,
          ),
        );

        locator
          ..registerSingleton<BackupProgressProvider>(backup)
          ..registerSingleton<IElevationProbe>(probe);

        final outcome = await checkInstallReadiness(
          getIt: locator,
          source: AppUpdateSource.periodic,
        );

        expect(outcome!.reason, AppUpdateBlockReason.localBackupRunning);
        expect(outcome.message, contains('Critical'));
        verifyNever(probe.probe);
      },
    );
  });
}
