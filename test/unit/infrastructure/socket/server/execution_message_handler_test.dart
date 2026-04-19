import 'dart:async';

import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_backup_destination_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/use_cases/scheduling/execute_scheduled_backup.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/server/execution_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/execution_queue_service.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockScheduleRepository extends Mock implements IScheduleRepository {}

class _MockDestinationRepository extends Mock
    implements IBackupDestinationRepository {}

class _MockLicensePolicyService extends Mock implements ILicensePolicyService {}

class _MockSchedulerService extends Mock implements ISchedulerService {}

class _MockExecuteBackup extends Mock implements ExecuteScheduledBackup {}

class _MockProgressNotifier extends Mock implements IBackupProgressNotifier {}

void main() {
  late _MockScheduleRepository scheduleRepository;
  late _MockDestinationRepository destinationRepository;
  late _MockLicensePolicyService licensePolicyService;
  late _MockSchedulerService schedulerService;
  late _MockExecuteBackup executeBackup;
  late _MockProgressNotifier progressNotifier;
  late RemoteExecutionRegistry executionRegistry;
  late ExecutionMessageHandler handler;

  const scheduleId = 'sch-1';
  final schedule = Schedule(
    id: scheduleId,
    name: 'Backup Diario',
    databaseConfigId: 'db-1',
    databaseType: DatabaseType.sqlServer,
    scheduleType: ScheduleType.daily.name,
    scheduleConfig: '{}',
    destinationIds: const ['dest-1'],
    backupFolder: r'C:\backup',
  );
  final destination = BackupDestination(
    id: 'dest-1',
    name: 'Local',
    type: DestinationType.local,
    config: '{"path":"C:/backup"}',
  );

  late List<({String clientId, Message message})> sent;

  Future<void> sendToClient(String clientId, Message m) async {
    sent.add((clientId: clientId, message: m));
  }

  setUpAll(() {
    registerFallbackValue(schedule);
    registerFallbackValue(destination);
  });

  setUp(() {
    scheduleRepository = _MockScheduleRepository();
    destinationRepository = _MockDestinationRepository();
    licensePolicyService = _MockLicensePolicyService();
    schedulerService = _MockSchedulerService();
    executeBackup = _MockExecuteBackup();
    progressNotifier = _MockProgressNotifier();
    executionRegistry = RemoteExecutionRegistry();
    sent = [];

    when(() => schedulerService.isExecutingBackup).thenReturn(false);
    when(() => progressNotifier.tryStartBackup(any())).thenReturn(true);
    // Default: backup async resolve sucesso (mas testes que querem
    // observar runtime async substituem isso por Completer<...>)
    when(() => executeBackup(any())).thenAnswer((_) async => rd.Success(true));
    when(
      () => scheduleRepository.getById(scheduleId),
    ).thenAnswer((_) async => rd.Success(schedule));
    when(
      () => destinationRepository.getByIds(any()),
    ).thenAnswer((_) async => rd.Success([destination]));
    when(
      () => licensePolicyService.validateExecutionCapabilities(any(), any()),
    ).thenAnswer((_) async => const rd.Success(true));

    handler = ExecutionMessageHandler(
      scheduleRepository: scheduleRepository,
      destinationRepository: destinationRepository,
      licensePolicyService: licensePolicyService,
      schedulerService: schedulerService,
      executeBackup: executeBackup,
      progressNotifier: progressNotifier,
      executionRegistry: executionRegistry,
      clock: () => DateTime.utc(2026, 4, 19, 12),
    );
  });

  group('startBackup nao-bloqueante (M2.2)', () {
    test('responde IMEDIATAMENTE com runId + state=running + 202', () async {
      // Bloqueia o backup async para confirmar que o handler nao
      // espera por ele antes de responder.
      final blockBackup = Completer<rd.Result<bool>>();
      when(() => executeBackup(any())).thenAnswer((_) => blockBackup.future);

      final req = createStartBackupRequest(scheduleId: scheduleId);
      await handler.handle('c1', req, sendToClient);

      // Resposta ja deve estar no `sent` MESMO sem ter resolvido o backup
      expect(sent, hasLength(1));
      final resp = sent.single.message;
      expect(resp.header.type, MessageType.startBackupResponse);
      expect(resp.payload['statusCode'], 202);
      expect(resp.payload['state'], 'running');
      expect(resp.payload['scheduleId'], scheduleId);
      expect(resp.payload['runId'], isA<String>());
      expect((resp.payload['runId'] as String), startsWith('$scheduleId\_'));
      expect(executionRegistry.activeCount, 1);

      // Libera para evitar pending Future warnings
      blockBackup.complete(const rd.Success(true));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    test('rejeita scheduleId vazio com error invalidRequest', () async {
      final req = Message(
        header: MessageHeader(
          type: MessageType.startBackupRequest,
          length: 0,
          requestId: 1,
        ),
        payload: const <String, dynamic>{'scheduleId': ''},
        checksum: 0,
      );
      await handler.handle('c1', req, sendToClient);
      final resp = sent.single.message;
      expect(resp.header.type, MessageType.error);
      expect(getErrorCodeFromMessage(resp), ErrorCode.invalidRequest);
    });

    test('rejeita quando ja existe backup em execucao', () async {
      when(() => schedulerService.isExecutingBackup).thenReturn(true);
      final req = createStartBackupRequest(scheduleId: scheduleId);
      await handler.handle('c1', req, sendToClient);
      final resp = sent.single.message;
      expect(resp.header.type, MessageType.error);
      expect(
        getErrorCodeFromMessage(resp),
        ErrorCode.backupAlreadyRunning,
      );
    });

    test('rejeita quando scheduleId nao existe', () async {
      when(
        () => scheduleRepository.getById(scheduleId),
      ).thenAnswer((_) async => rd.Failure(Exception('not found')));
      final req = createStartBackupRequest(scheduleId: scheduleId);
      await handler.handle('c1', req, sendToClient);
      final resp = sent.single.message;
      expect(resp.header.type, MessageType.error);
      expect(getErrorCodeFromMessage(resp), ErrorCode.scheduleNotFound);
    });

    test('rejeita quando licenca nega', () async {
      when(
        () => licensePolicyService.validateExecutionCapabilities(any(), any()),
      ).thenAnswer((_) async => rd.Failure(Exception('license denied')));
      final req = createStartBackupRequest(scheduleId: scheduleId);
      await handler.handle('c1', req, sendToClient);
      final resp = sent.single.message;
      expect(resp.header.type, MessageType.error);
      expect(getErrorCodeFromMessage(resp), ErrorCode.licenseDenied);
    });

    test(
      'idempotencyKey: 2a request com mesma chave NAO dispara executeBackup',
      () async {
        final blockBackup = Completer<rd.Result<bool>>();
        when(() => executeBackup(any())).thenAnswer((_) => blockBackup.future);

        final req = createStartBackupRequest(
          scheduleId: scheduleId,
          idempotencyKey: 'idem-1',
        );
        await handler.handle('c1', req, sendToClient);
        await handler.handle('c1', req, sendToClient);

        // 2 respostas iguais, mas executeBackup foi chamado APENAS 1 vez
        verify(() => executeBackup(any())).called(1);
        expect(sent, hasLength(2));
        expect(
          sent[0].message.payload['runId'],
          equals(sent[1].message.payload['runId']),
        );

        blockBackup.complete(const rd.Success(true));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
    );

    test(
      'idempotencyKey: falha NAO e cacheada (cliente pode tentar de novo)',
      () async {
        // 1a chamada: scheduleId nao existe
        when(
          () => scheduleRepository.getById(scheduleId),
        ).thenAnswer((_) async => rd.Failure(Exception('not found')));
        final req = createStartBackupRequest(
          scheduleId: scheduleId,
          idempotencyKey: 'idem-2',
        );
        await handler.handle('c1', req, sendToClient);
        expect(sent.last.message.header.type, MessageType.error);

        // 2a chamada: agora schedule existe (config corrigida)
        when(
          () => scheduleRepository.getById(scheduleId),
        ).thenAnswer((_) async => rd.Success(schedule));
        await handler.handle('c1', req, sendToClient);
        expect(sent.last.message.header.type, MessageType.startBackupResponse);
      },
    );
  });

  group('cancelBackup', () {
    test('por runId: aceita quando execucao ativa', () async {
      // Setup: registra execucao ativa
      executionRegistry.register(
        runId: 'r1',
        scheduleId: scheduleId,
        clientId: 'c1',
        requestId: 0,
        sendToClient: (_, __) async {},
      );
      when(
        () => schedulerService.cancelExecution(scheduleId),
      ).thenAnswer((_) async => const rd.Success(true));

      final req = createCancelBackupRequest(runId: 'r1');
      await handler.handle('c1', req, sendToClient);

      final resp = sent.single.message;
      expect(resp.header.type, MessageType.cancelBackupResponse);
      expect(resp.payload['state'], 'cancelled');
      expect(resp.payload['statusCode'], 200);
      verify(() => schedulerService.cancelExecution(scheduleId)).called(1);
    });

    test('por scheduleId: aceita', () async {
      executionRegistry.register(
        runId: 'r1',
        scheduleId: scheduleId,
        clientId: 'c1',
        requestId: 0,
        sendToClient: (_, __) async {},
      );
      when(
        () => schedulerService.cancelExecution(scheduleId),
      ).thenAnswer((_) async => const rd.Success(true));

      final req = createCancelBackupRequest(scheduleId: scheduleId);
      await handler.handle('c1', req, sendToClient);
      expect(sent.single.message.payload['state'], 'cancelled');
    });

    test('runId desconhecido -> noActiveExecution', () async {
      final req = createCancelBackupRequest(runId: 'r-nope');
      await handler.handle('c1', req, sendToClient);
      final resp = sent.single.message;
      expect(resp.payload['state'], 'notFound');
      expect(resp.payload['errorCode'], 'NO_ACTIVE_EXECUTION');
      expect(resp.payload['statusCode'], 409);
    });

    test('scheduleId sem execucao ativa -> noActiveExecution', () async {
      final req = createCancelBackupRequest(scheduleId: 'sch-x');
      await handler.handle('c1', req, sendToClient);
      final resp = sent.single.message;
      expect(resp.payload['errorCode'], 'NO_ACTIVE_EXECUTION');
    });

    test('XOR violado (ambos vazios) -> error invalidRequest', () async {
      final req = Message(
        header: MessageHeader(
          type: MessageType.cancelBackupRequest,
          length: 0,
          requestId: 1,
        ),
        payload: const <String, dynamic>{},
        checksum: 0,
      );
      await handler.handle('c1', req, sendToClient);
      final resp = sent.single.message;
      expect(resp.header.type, MessageType.error);
      expect(getErrorCodeFromMessage(resp), ErrorCode.invalidRequest);
    });

    test('falha do scheduler vira state=failed', () async {
      executionRegistry.register(
        runId: 'r1',
        scheduleId: scheduleId,
        clientId: 'c1',
        requestId: 0,
        sendToClient: (_, __) async {},
      );
      when(
        () => schedulerService.cancelExecution(scheduleId),
      ).thenAnswer((_) async => rd.Failure(Exception('cancel failed')));

      final req = createCancelBackupRequest(runId: 'r1');
      await handler.handle('c1', req, sendToClient);
      final resp = sent.single.message;
      expect(resp.payload['state'], 'failed');
      expect(resp.payload['errorCode'], 'UNKNOWN');
    });

    test('idempotencyKey: 2a cancelacao com mesma chave reusa cache', () async {
      executionRegistry.register(
        runId: 'r1',
        scheduleId: scheduleId,
        clientId: 'c1',
        requestId: 0,
        sendToClient: (_, __) async {},
      );
      when(
        () => schedulerService.cancelExecution(scheduleId),
      ).thenAnswer((_) async => const rd.Success(true));

      final req = createCancelBackupRequest(
        runId: 'r1',
        idempotencyKey: 'idem-cancel',
      );
      await handler.handle('c1', req, sendToClient);
      await handler.handle('c1', req, sendToClient);

      verify(() => schedulerService.cancelExecution(scheduleId)).called(1);
      expect(sent, hasLength(2));
    });
  });

  group('startBackup com queueIfBusy (PR-3a)', () {
    test(
      'queueIfBusy=true quando ocupado: enfileira e responde state=queued + 202',
      () async {
        when(() => schedulerService.isExecutingBackup).thenReturn(true);
        final queue = ExecutionQueueService();
        handler = ExecutionMessageHandler(
          scheduleRepository: scheduleRepository,
          destinationRepository: destinationRepository,
          licensePolicyService: licensePolicyService,
          schedulerService: schedulerService,
          executeBackup: executeBackup,
          progressNotifier: progressNotifier,
          executionRegistry: executionRegistry,
          queueService: queue,
          clock: () => DateTime.utc(2026, 4, 19, 12),
        );

        final req = createStartBackupRequest(
          scheduleId: scheduleId,
          queueIfBusy: true,
        );
        await handler.handle('c1', req, sendToClient);

        final resp = sent.single.message;
        expect(resp.header.type, MessageType.startBackupResponse);
        expect(resp.payload['state'], 'queued');
        expect(resp.payload['scheduleId'], scheduleId);
        expect(resp.payload['queuePosition'], 1);
        expect(resp.payload['statusCode'], 202);
        expect(queue.queueSize, 1);
        expect(queue.isScheduleQueued(scheduleId), isTrue);
      },
    );

    test(
      'queueIfBusy=false (default): rejeita com 409 quando ocupado',
      () async {
        when(() => schedulerService.isExecutingBackup).thenReturn(true);
        final req = createStartBackupRequest(scheduleId: scheduleId);
        await handler.handle('c1', req, sendToClient);
        final resp = sent.single.message;
        expect(resp.header.type, MessageType.error);
        expect(
          getErrorCodeFromMessage(resp),
          ErrorCode.backupAlreadyRunning,
        );
      },
    );

    test(
      'queueIfBusy=true mas mesmo schedule ja na fila: rejeita',
      () async {
        when(() => schedulerService.isExecutingBackup).thenReturn(true);
        final queue = ExecutionQueueService();
        queue.tryEnqueue(
          scheduleId: scheduleId,
          clientId: 'other',
          requestId: 99,
          requestedBy: 'other',
        );
        handler = ExecutionMessageHandler(
          scheduleRepository: scheduleRepository,
          destinationRepository: destinationRepository,
          licensePolicyService: licensePolicyService,
          schedulerService: schedulerService,
          executeBackup: executeBackup,
          progressNotifier: progressNotifier,
          executionRegistry: executionRegistry,
          queueService: queue,
          clock: () => DateTime.utc(2026),
        );
        final req = createStartBackupRequest(
          scheduleId: scheduleId,
          queueIfBusy: true,
        );
        await handler.handle('c1', req, sendToClient);
        final resp = sent.single.message;
        expect(resp.header.type, MessageType.error);
        expect(
          getErrorCodeFromMessage(resp),
          ErrorCode.backupAlreadyRunning,
        );
        expect(queue.queueSize, 1, reason: 'fila nao deve crescer');
      },
    );

    test('queueIfBusy=true e fila cheia: rejeita com erro', () async {
      when(() => schedulerService.isExecutingBackup).thenReturn(true);
      final queue = ExecutionQueueService(maxQueueSize: 1);
      queue.tryEnqueue(
        scheduleId: 'other',
        clientId: 'other',
        requestId: 99,
        requestedBy: 'other',
      );
      handler = ExecutionMessageHandler(
        scheduleRepository: scheduleRepository,
        destinationRepository: destinationRepository,
        licensePolicyService: licensePolicyService,
        schedulerService: schedulerService,
        executeBackup: executeBackup,
        progressNotifier: progressNotifier,
        executionRegistry: executionRegistry,
        queueService: queue,
        clock: () => DateTime.utc(2026),
      );
      final req = createStartBackupRequest(
        scheduleId: scheduleId,
        queueIfBusy: true,
      );
      await handler.handle('c1', req, sendToClient);
      final resp = sent.single.message;
      expect(resp.header.type, MessageType.error);
      expect(getErrorFromMessage(resp), contains('Fila'));
    });
  });

  group('outros tipos de mensagem', () {
    test('ignora mensagens nao relacionadas (no-op)', () async {
      final unrelated = Message(
        header: MessageHeader(type: MessageType.heartbeat, length: 0),
        payload: const <String, dynamic>{},
        checksum: 0,
      );
      await handler.handle('c1', unrelated, sendToClient);
      expect(sent, isEmpty);
    });
  });
}
