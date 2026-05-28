import 'dart:async';

import 'package:backup_database/application/providers/auto_update_provider.dart';
import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAutoUpdateService extends Mock implements AutoUpdateService {}

void main() {
  /// §audit-2026-05-28 wave 4 (UI banner): testes do getter
  /// `isBlockedByUacPolicy`. Esse é o **único bit** que a UI consulta
  /// para decidir se mostra o banner UAC com "Atualizar agora" embutido.
  ///
  /// Cobertura por matriz: status × blockReason.
  group('AutoUpdateProvider.isBlockedByUacPolicy', () {
    late _MockAutoUpdateService service;
    late StreamController<AppUpdateSnapshot> snapshots;

    setUp(() {
      service = _MockAutoUpdateService();
      snapshots = StreamController<AppUpdateSnapshot>.broadcast();
      when(() => service.snapshots).thenAnswer((_) => snapshots.stream);
    });

    tearDown(() async {
      await snapshots.close();
    });

    AutoUpdateProvider buildProvider(AppUpdateSnapshot initial) {
      when(() => service.snapshot).thenReturn(initial);
      return AutoUpdateProvider(autoUpdateService: service);
    }

    test('true when status=blocked AND reason=uacPolicy', () {
      final provider = buildProvider(
        const AppUpdateSnapshot(
          status: AppUpdateStatus.blockedByActiveBackup,
          blockReason: AppUpdateBlockReason.uacPolicy,
        ),
      );

      expect(provider.isBlockedByUacPolicy, isTrue);
      expect(provider.blockReason, AppUpdateBlockReason.uacPolicy);

      provider.dispose();
    });

    test('false when status=blocked but reason is OTHER', () {
      // Cada outro reason deve render banner GENÉRICO (não o de UAC).
      const otherReasons = [
        AppUpdateBlockReason.localBackupRunning,
        AppUpdateBlockReason.remoteBackupRunning,
        AppUpdateBlockReason.fileTransferActive,
        AppUpdateBlockReason.serviceAccountUnsupported,
      ];

      for (final reason in otherReasons) {
        final provider = buildProvider(
          AppUpdateSnapshot(
            status: AppUpdateStatus.blockedByActiveBackup,
            blockReason: reason,
          ),
        );
        expect(
          provider.isBlockedByUacPolicy,
          isFalse,
          reason: 'reason=$reason should NOT trigger UAC banner',
        );
        provider.dispose();
      }
    });

    test('false when blockReason=uacPolicy but status is NOT blocked', () {
      // Defesa: o reason pode ficar "stale" no snapshot após um ciclo
      // que destravou; só mostrar o banner quando AMBOS batem.
      final provider = buildProvider(
        const AppUpdateSnapshot(
          status: AppUpdateStatus.upToDate,
          blockReason: AppUpdateBlockReason.uacPolicy,
        ),
      );

      expect(provider.isBlockedByUacPolicy, isFalse);

      provider.dispose();
    });

    test(
      'false when both status=blocked and reason=null (legacy snapshot)',
      () {
        // Snapshot vindo de uma versão pré-wave-4 (sem `blockReason`).
        // Cai no caminho do banner genérico, não no UAC.
        final provider = buildProvider(
          const AppUpdateSnapshot(
            status: AppUpdateStatus.blockedByActiveBackup,
          ),
        );

        expect(provider.isBlockedByUacPolicy, isFalse);
        expect(provider.blockReason, isNull);

        provider.dispose();
      },
    );

    test('blockReason getter passes through from snapshot', () {
      final provider = buildProvider(
        const AppUpdateSnapshot(
          status: AppUpdateStatus.blockedByActiveBackup,
          blockReason: AppUpdateBlockReason.remoteBackupRunning,
        ),
      );

      expect(provider.blockReason, AppUpdateBlockReason.remoteBackupRunning);
      expect(provider.isBlockedByUacPolicy, isFalse);

      provider.dispose();
    });

    test('updates when a new snapshot arrives via stream', () async {
      final provider = buildProvider(
        const AppUpdateSnapshot(
          status: AppUpdateStatus.idle,
        ),
      );
      expect(provider.isBlockedByUacPolicy, isFalse);

      snapshots.add(
        const AppUpdateSnapshot(
          status: AppUpdateStatus.blockedByActiveBackup,
          blockReason: AppUpdateBlockReason.uacPolicy,
        ),
      );
      // Drena uma microtask para o listener atualizar `_snapshot`.
      await Future<void>.delayed(Duration.zero);

      expect(provider.isBlockedByUacPolicy, isTrue);

      provider.dispose();
    });
  });
}
