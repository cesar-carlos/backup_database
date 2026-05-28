import 'package:backup_database/application/providers/dashboard_provider.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBackupHistoryRepository extends Mock
    implements IBackupHistoryRepository {}

class _MockScheduleRepository extends Mock implements IScheduleRepository {}

void main() {
  AppMode? previousMode;

  setUp(() => previousMode = currentAppMode);
  tearDown(() {
    if (previousMode != null) {
      setAppMode(previousMode!);
    }
  });

  test(
    '§audit-2026-05-28 P2: skips all local queries when in client mode',
    () async {
      // Regressão: antes o dashboard chamava getAll(), getByDateRange(),
      // getEnabled() e generateReport() em todo `loadDashboardData()`,
      // mesmo em modo cliente — onde nada disso é exibido. Em SQLite
      // pequeno isso é I/O barato, mas em máquinas com milhares de
      // registros legados (cliente "migrado" de um server antigo) ele
      // empurrava o boot do painel em 200-400ms.
      setAppMode(AppMode.client);

      final backupHistoryRepo = _MockBackupHistoryRepository();
      final scheduleRepo = _MockScheduleRepository();

      final provider = DashboardProvider(backupHistoryRepo, scheduleRepo);

      await provider.loadDashboardData();

      verifyZeroInteractions(backupHistoryRepo);
      verifyZeroInteractions(scheduleRepo);

      expect(provider.totalBackups, 0);
      expect(provider.backupsToday, 0);
      expect(provider.failedToday, 0);
      expect(provider.activeSchedules, 0);
      expect(provider.recentBackups, isEmpty);
      expect(provider.activeSchedulesList, isEmpty);
      expect(provider.serverMetrics, isNull);
      expect(provider.metricsReport, isNull);
    },
  );
}
