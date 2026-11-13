import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/application/providers/log_provider.dart';
import 'package:backup_database/application/services/log_service.dart';
import 'package:backup_database/application/services/notification/email_delivery_batcher.dart';
import 'package:backup_database/application/services/notification/notification_audit_writer.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_diagnostics.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/repositories/i_email_test_audit_repository.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/backup_history_repository.dart';
import 'package:backup_database/infrastructure/repositories/backup_log_repository.dart';
import 'package:backup_database/presentation/pages/logs_page.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart' as rd;

class MockLogService extends Mock implements LogService {}

class MockEmailAuditRepository extends Mock
    implements IEmailTestAuditRepository {}

void main() {
  late AppDatabase database;
  late BackupLogRepository logs;
  late BackupHistoryRepository histories;

  setUp(() {
    database = AppDatabase.inMemory();
    logs = BackupLogRepository(database);
    histories = BackupHistoryRepository(database, logs);
  });
  tearDown(() => database.close());

  for (final format in ExportFormat.values) {
    test('exports ${format.name} to the exact selected file path', () async {
      final directory = await Directory.systemTemp.createTemp('backup-export-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/meus logs ç.${format.name}');
      await file.writeAsString('conteúdo anterior');
      await logs.create(
        BackupLog(
          level: LogLevel.error,
          category: LogCategory.execution,
          message: 'Falha no envio',
          details: 'FTP: acesso negado',
          backupHistoryId: 'exec-123',
        ),
      );
      final result = await LogService(logs).exportLogs(
        outputPath: file.path,
        format: format,
      );
      expect(result.getOrThrow(), file.path);
      final content = await file.readAsString();
      expect(content, contains('FTP: acesso negado'));
      expect(content, isNot(contains('conteúdo anterior')));
      expect(await directory.list().length, 1);
      if (format == ExportFormat.json) {
        expect(
          (jsonDecode(content) as Map<String, dynamic>)['totalRecords'],
          1,
        );
      }
    });
  }

  test(
    'creates selected file and reports missing parent without success',
    () async {
      final directory = await Directory.systemTemp.createTemp('backup-export-');
      addTearDown(() => directory.delete(recursive: true));
      final service = LogService(logs);
      final file = File('${directory.path}/novo.txt');
      expect(
        (await service.exportLogs(outputPath: file.path)).isSuccess(),
        isTrue,
      );
      expect(await file.exists(), isTrue);
      final result = await service.exportLogs(
        outputPath: '${directory.path}/missing/log.txt',
      );
      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<FileSystemFailure>());
    },
  );

  testWidgets('shows selectable cause and execution on Logs page', (
    tester,
  ) async {
    final service = MockLogService();
    when(() => service.getLogs(limit: 50, offset: 0)).thenAnswer(
      (_) async => rd.Success([
        BackupLog(
          level: LogLevel.error,
          category: LogCategory.execution,
          message: 'Falha no envio',
          details: 'Causa: FTP 530 acesso negado',
          backupHistoryId: 'run-42',
        ),
      ]),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LogProvider(service),
        child: const FluentApp(home: LogsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Causa: FTP 530 acesso negado'), findsOneWidget);
    expect(find.text('Execução: run-42'), findsOneWidget);
    expect(find.byType(SelectableText), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  test('notification success explains that the backup itself failed', () async {
    final writer = NotificationAuditWriter(
      backupLogRepository: logs,
      emailTestAuditRepository: MockEmailAuditRepository(),
    );
    await writer.saveBackupDeliveryAuditLog(
      configId: 'config',
      historyId: 'execution',
      eventType: 'backup_error',
      target: EmailNotificationTarget(
        emailConfigId: 'config',
        recipientEmail: 'test@example.com',
      ),
      result: RecipientDeliveryResult.sent(recipientEmail: 'test@example.com'),
    );
    final entry = (await logs.getAll()).getOrThrow().single;
    expect(entry.message, contains('Envio da notificação'));
    expect(entry.message, contains('enviado'));
    expect(entry.details, contains('não a causa do backup'));
    expect(entry.details, contains('execution'));
    expect(entry.level, LogLevel.info);
  });

  for (final status in BackupStatus.values.where(
    (s) => s != BackupStatus.running,
  )) {
    test(
      'preserves late upload error after $status without changing history',
      () async {
        final history = BackupHistory(
          id: 'execution-1',
          scheduleId: 'schedule-1',
          databaseName: 'Database A',
          databaseType: 'sqlServer',
          backupPath: 'backup.bak',
          fileSize: 10,
          status: status,
          startedAt: DateTime(2026),
        );
        await histories.create(history);
        for (var attempt = 0; attempt < 2; attempt++) {
          final result = await histories.updateHistoryAndLogIfRunning(
            history: history.copyWith(status: BackupStatus.error),
            logStep: 'upload_failed',
            logLevel: LogLevel.error,
            logMessage: 'FTP: conexão interrompida',
            logDetails: 'Destino: Filial\nCausa: timeout',
          );
          expect(
            result.isError(),
            isTrue,
            reason: 'must not claim state was changed',
          );
        }
        final saved = (await logs.getByBackupHistory(history.id)).getOrThrow();
        expect(saved, hasLength(1));
        expect(saved.single.details, contains('upload_failed'));
        expect(saved.single.details, contains('Filial'));
        expect(saved.single.details, contains('Database A'));
        expect(
          (await histories.getById(history.id)).getOrThrow().status,
          status,
        );
      },
    );
  }

  test('combines filters and search before ordering and pagination', () async {
    for (var index = 0; index < 5; index++) {
      await logs.create(
        BackupLog(
          id: '$index',
          backupHistoryId: 'run-1',
          level: index == 0 ? LogLevel.info : LogLevel.error,
          category: index == 1 ? LogCategory.audit : LogCategory.execution,
          message: 'falha',
          details: 'FTP timeout',
          createdAt: DateTime(2026, 1, index + 1),
        ),
      );
    }
    final service = LogService(logs);
    final first = (await service.getLogs(
      level: LogLevel.error,
      category: LogCategory.execution,
      searchQuery: 'ftp',
      limit: 2,
    )).getOrThrow();
    final second = (await service.getLogs(
      level: LogLevel.error,
      category: LogCategory.execution,
      searchQuery: 'ftp',
      limit: 2,
      offset: 2,
    )).getOrThrow();
    expect(first.map((e) => e.id), ['4', '3']);
    expect(second.map((e) => e.id), ['2']);
    expect(
      (await service.getLogs(searchQuery: 'run-1')).getOrThrow(),
      hasLength(5),
    );
  });

  test('keeps original cause and code while hiding credentials', () {
    final text = failureDiagnostics(
      const BackupFailure(
        message: 'Envio falhou',
        code: 'upload_failed',
        originalError: NetworkFailure(
          message: 'FTP 530 ftp://user:secret@host password="very secret" access_token=token',
        ),
      ),
    );
    expect(text, contains('upload_failed'));
    expect(text, contains('Causa: NetworkFailure'));
    expect(text, contains('FTP 530'));
    expect(text, isNot(contains('secret')));
    expect(text, isNot(contains('=token')));
  });

  test('reloads the latest filters changed while loading', () async {
    final service = MockLogService();
    final pending = Completer<rd.Result<List<BackupLog>>>();
    when(() => service.getLogs(limit: 50, offset: 0))
        .thenAnswer((_) => pending.future);
    final latest = BackupLog(
      level: LogLevel.error,
      category: LogCategory.execution,
      message: 'FTP',
    );
    when(
      () => service.getLogs(
        limit: 50,
        offset: 0,
        level: LogLevel.error,
        searchQuery: 'FTP',
      ),
    ).thenAnswer((_) async => rd.Success([latest]));
    final provider = LogProvider(service);
    final loading = provider.loadLogs();
    provider.setFilterLevel(LogLevel.error);
    provider.setSearchQuery('FTP');
    pending.complete(const rd.Success([]));
    await loading;
    expect(provider.logs, [latest]);
    provider.dispose();
  });
}
