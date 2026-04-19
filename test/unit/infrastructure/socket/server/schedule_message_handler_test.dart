import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/backup_progress_snapshot.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_backup_destination_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/use_cases/scheduling/execute_scheduled_backup.dart';
import 'package:backup_database/domain/use_cases/scheduling/update_schedule.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';
import 'package:backup_database/infrastructure/socket/server/schedule_message_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockScheduleRepository extends Mock implements IScheduleRepository {}

class _MockDestinationRepository extends Mock
    implements IBackupDestinationRepository {}

class _MockLicensePolicyService extends Mock implements ILicensePolicyService {}

class _MockSchedulerService extends Mock implements ISchedulerService {}

class _MockUpdateSchedule extends Mock implements UpdateSchedule {}

class _MockExecuteBackup extends Mock implements ExecuteScheduledBackup {}

class _MockProgressNotifier extends Mock implements IBackupProgressNotifier {}

void main() {
  late _MockScheduleRepository scheduleRepository;
  late _MockDestinationRepository destinationRepository;
  late _MockLicensePolicyService licensePolicyService;
  late _MockSchedulerService schedulerService;
  late _MockUpdateSchedule updateSchedule;
  late _MockExecuteBackup executeBackup;
  late _MockProgressNotifier progressNotifier;
  late RemoteExecutionRegistry executionRegistry;
  late ScheduleMessageHandler handler;

  const scheduleId = 'schedule-1';
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

  setUpAll(() {
    registerFallbackValue(schedule);
    registerFallbackValue(destination);
  });

  setUp(() {
    scheduleRepository = _MockScheduleRepository();
    destinationRepository = _MockDestinationRepository();
    licensePolicyService = _MockLicensePolicyService();
    schedulerService = _MockSchedulerService();
    updateSchedule = _MockUpdateSchedule();
    executeBackup = _MockExecuteBackup();
    progressNotifier = _MockProgressNotifier();

    when(() => schedulerService.isExecutingBackup).thenReturn(false);
    when(() => progressNotifier.tryStartBackup(any())).thenReturn(true);
    when(() => progressNotifier.currentSnapshot).thenReturn(null);

    executionRegistry = RemoteExecutionRegistry();
    handler = ScheduleMessageHandler(
      scheduleRepository: scheduleRepository,
      destinationRepository: destinationRepository,
      licensePolicyService: licensePolicyService,
      schedulerService: schedulerService,
      updateSchedule: updateSchedule,
      executeBackup: executeBackup,
      progressNotifier: progressNotifier,
      executionRegistry: executionRegistry,
    );
  });

  tearDown(() {
    handler.dispose();
  });

  group('ScheduleMessageHandler remote bypass', () {
    test(
      'executeSchedule rejects when validateExecutionCapabilities fails',
      () async {
        when(
          () => scheduleRepository.getById(scheduleId),
        ).thenAnswer((_) async => rd.Success(schedule));
        when(
          () => destinationRepository.getByIds(any()),
        ).thenAnswer((_) async => rd.Success([destination]));
        when(
          () => licensePolicyService.validateExecutionCapabilities(
            any(),
            any(),
          ),
        ).thenAnswer(
          (_) async => const rd.Failure(
            ValidationFailure(
              message: 'Backup diferencial requer licença',
            ),
          ),
        );

        Message? sentMessage;
        Future<void> sendToClient(String clientId, Message msg) async {
          sentMessage = msg;
        }

        final message = createExecuteScheduleMessage(
          requestId: 1,
          scheduleId: scheduleId,
        );

        await handler.handle('client-1', message, sendToClient);

        expect(sentMessage, isNotNull);
        expect(
          sentMessage!.payload['error'],
          contains('Backup diferencial requer licença'),
        );
        verifyNever(() => executeBackup(any()));
        verifyNever(() => progressNotifier.tryStartBackup(any()));
      },
    );

    test(
      'executeSchedule proceeds when validateExecutionCapabilities succeeds',
      () async {
        when(
          () => scheduleRepository.getById(scheduleId),
        ).thenAnswer((_) async => rd.Success(schedule));
        when(
          () => destinationRepository.getByIds(any()),
        ).thenAnswer((_) async => rd.Success([destination]));
        when(
          () => licensePolicyService.validateExecutionCapabilities(
            any(),
            any(),
          ),
        ).thenAnswer((_) async => const rd.Success(rd.unit));
        when(
          () => executeBackup(scheduleId),
        ).thenAnswer((_) async => const rd.Success(rd.unit));

        Message? sentMessage;
        Future<void> sendToClient(String clientId, Message msg) async {
          sentMessage = msg;
        }

        final message = createExecuteScheduleMessage(
          requestId: 1,
          scheduleId: scheduleId,
        );

        await handler.handle('client-1', message, sendToClient);

        expect(sentMessage, isNotNull);
        verify(() => executeBackup(scheduleId)).called(1);
      },
    );
  });

  group('ScheduleMessageHandler execution registry integration', () {
    test(
      'execucao bem-sucedida desregistra contexto do registry',
      () async {
        when(() => scheduleRepository.getById(scheduleId))
            .thenAnswer((_) async => rd.Success(schedule));
        when(() => destinationRepository.getByIds(any()))
            .thenAnswer((_) async => rd.Success([destination]));
        when(
          () => licensePolicyService.validateExecutionCapabilities(any(), any()),
        ).thenAnswer((_) async => const rd.Success(rd.unit));
        when(() => executeBackup(scheduleId))
            .thenAnswer((_) async => const rd.Success(rd.unit));

        Future<void> noopSend(String clientId, Message msg) async {}

        await handler.handle(
          'client-1',
          createExecuteScheduleMessage(requestId: 1, scheduleId: scheduleId),
          noopSend,
        );

        // Apos execucao bem-sucedida o contexto deve sair do registry
        // (caso contrario o proximo disparo seria rejeitado por
        // `hasActiveForSchedule`).
        expect(executionRegistry.hasActiveForSchedule(scheduleId), isFalse);
        expect(executionRegistry.activeCount, 0);
      },
    );

    test(
      'execucao com falha no executeBackup tambem desregistra contexto',
      () async {
        when(() => scheduleRepository.getById(scheduleId))
            .thenAnswer((_) async => rd.Success(schedule));
        when(() => destinationRepository.getByIds(any()))
            .thenAnswer((_) async => rd.Success([destination]));
        when(
          () => licensePolicyService.validateExecutionCapabilities(any(), any()),
        ).thenAnswer((_) async => const rd.Success(rd.unit));
        when(() => executeBackup(scheduleId)).thenAnswer(
          (_) async => const rd.Failure(BackupFailure(message: 'erro')),
        );

        Future<void> noopSend(String clientId, Message msg) async {}

        await handler.handle(
          'client-1',
          createExecuteScheduleMessage(requestId: 1, scheduleId: scheduleId),
          noopSend,
        );

        expect(executionRegistry.hasActiveForSchedule(scheduleId), isFalse);
        expect(executionRegistry.activeCount, 0);
      },
    );

    test(
      'cancelSchedule responde "Não há backup em execução" quando registry esta vazio',
      () async {
        Message? sentMessage;
        Future<void> sendToClient(String clientId, Message msg) async {
          sentMessage = msg;
        }

        await handler.handle(
          'client-X',
          createCancelScheduleMessage(
            requestId: 99,
            scheduleId: 'schedule-inexistente',
          ),
          sendToClient,
        );

        expect(sentMessage, isNotNull);
        expect(sentMessage!.header.type, MessageType.error);
        expect(
          sentMessage!.payload['error'],
          contains('Não há backup em execução'),
        );
        verifyNever(() => schedulerService.cancelExecution(any()));
      },
    );

    test(
      'cancelSchedule de schedule diferente do ativo nao cancela o ativo',
      () async {
        // Pre-popula registry simulando execucao em curso de schedule-A
        const activeSchedule = 'schedule-A';
        executionRegistry.register(
          runId: executionRegistry.generateRunId(activeSchedule),
          scheduleId: activeSchedule,
          clientId: 'client-A',
          requestId: 100,
          sendToClient: (clientId, msg) async {},
        );

        Message? sentMessage;
        Future<void> sendToClient(String clientId, Message msg) async {
          sentMessage = msg;
        }

        // Outro cliente tenta cancelar um schedule DIFERENTE
        await handler.handle(
          'client-B',
          createCancelScheduleMessage(
            requestId: 200,
            scheduleId: 'schedule-B',
          ),
          sendToClient,
        );

        // Resposta deve ser erro padronizado, nao deve afetar schedule-A
        expect(sentMessage, isNotNull);
        expect(sentMessage!.header.type, MessageType.error);
        expect(
          sentMessage!.payload['error'],
          contains('Não há backup em execução'),
        );
        // schedule-A continua ativo no registry (nao foi cancelado)
        expect(executionRegistry.hasActiveForSchedule(activeSchedule), isTrue);
        verifyNever(() => schedulerService.cancelExecution(any()));
      },
    );

    test(
      'segundo execute para o mesmo scheduleId e rejeitado mesmo se '
      'isExecutingBackup retornar false (defesa em profundidade do registry)',
      () async {
        // Simula janela TOCTOU: scheduler ainda nao reportou ocupado,
        // mas o registry ja tem entrada (cenario possivel se o scheduler
        // local e o handler remoto tiverem timing distintos).
        const targetSchedule = 'schedule-shared';
        executionRegistry.register(
          runId: executionRegistry.generateRunId(targetSchedule),
          scheduleId: targetSchedule,
          clientId: 'client-A',
          requestId: 1,
          sendToClient: (clientId, msg) async {},
        );

        when(() => schedulerService.isExecutingBackup).thenReturn(false);

        Message? sentMessage;
        Future<void> sendToClient(String clientId, Message msg) async {
          sentMessage = msg;
        }

        await handler.handle(
          'client-B',
          createExecuteScheduleMessage(
            requestId: 2,
            scheduleId: targetSchedule,
          ),
          sendToClient,
        );

        expect(sentMessage, isNotNull);
        expect(sentMessage!.header.type, MessageType.error);
        expect(
          sentMessage!.payload['error'],
          contains('Já existe um backup em execução para este agendamento'),
        );
        verifyNever(() => executeBackup(any()));
        verifyNever(() => progressNotifier.tryStartBackup(any()));
        // client-A continua ativo (nao foi sobrescrito como acontecia
        // com os singletons antigos).
        expect(
          executionRegistry.getActiveByScheduleId(targetSchedule)!.clientId,
          'client-A',
        );
      },
    );

    test(
      'execucao popula o registry com clientId/requestId corretos durante o backup',
      () async {
        when(() => scheduleRepository.getById(scheduleId))
            .thenAnswer((_) async => rd.Success(schedule));
        when(() => destinationRepository.getByIds(any()))
            .thenAnswer((_) async => rd.Success([destination]));
        when(
          () => licensePolicyService.validateExecutionCapabilities(any(), any()),
        ).thenAnswer((_) async => const rd.Success(rd.unit));

        // Captura o estado do registry no momento em que o backup esta
        // rodando — antes da chamada terminar e desregistrar.
        RemoteExecutionContext? capturedContext;
        when(() => executeBackup(scheduleId)).thenAnswer((_) async {
          capturedContext = executionRegistry.getActiveByScheduleId(scheduleId);
          return const rd.Success(rd.unit);
        });

        Future<void> noopSend(String clientId, Message msg) async {}

        await handler.handle(
          'client-Z',
          createExecuteScheduleMessage(requestId: 777, scheduleId: scheduleId),
          noopSend,
        );

        expect(capturedContext, isNotNull);
        expect(capturedContext!.clientId, 'client-Z');
        expect(capturedContext!.requestId, 777);
        expect(capturedContext!.scheduleId, scheduleId);
        expect(capturedContext!.runId, startsWith('${scheduleId}_'));
      },
    );
  });

  group('ScheduleMessageHandler errorCode envelope (F0.2)', () {
    test(
      'scheduleId vazio em executeSchedule -> INVALID_REQUEST (400)',
      () async {
        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle(
          'c1',
          createExecuteScheduleMessage(requestId: 1, scheduleId: ''),
          capture,
        );

        expect(sent, isNotNull);
        expect(sent!.header.type, MessageType.error);
        expect(getErrorCodeFromMessage(sent!), ErrorCode.invalidRequest);
        expect(getStatusCodeFromMessage(sent!), 400);
      },
    );

    test(
      'isExecutingBackup=true -> BACKUP_ALREADY_RUNNING (409)',
      () async {
        when(() => schedulerService.isExecutingBackup).thenReturn(true);

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle(
          'c1',
          createExecuteScheduleMessage(requestId: 1, scheduleId: scheduleId),
          capture,
        );

        expect(sent, isNotNull);
        expect(getErrorCodeFromMessage(sent!), ErrorCode.backupAlreadyRunning);
        expect(getStatusCodeFromMessage(sent!), 409);
      },
    );

    test(
      'registry com schedule ja ativo -> BACKUP_ALREADY_RUNNING (409)',
      () async {
        // Pre-popula registry simulando outro cliente ja em execucao
        executionRegistry.register(
          runId: executionRegistry.generateRunId(scheduleId),
          scheduleId: scheduleId,
          clientId: 'other-client',
          requestId: 100,
          sendToClient: (clientId, msg) async {},
        );
        when(() => schedulerService.isExecutingBackup).thenReturn(false);

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle(
          'c1',
          createExecuteScheduleMessage(requestId: 1, scheduleId: scheduleId),
          capture,
        );

        expect(getErrorCodeFromMessage(sent!), ErrorCode.backupAlreadyRunning);
        expect(getStatusCodeFromMessage(sent!), 409);
      },
    );

    test(
      'schedule nao existe -> SCHEDULE_NOT_FOUND (404)',
      () async {
        when(() => scheduleRepository.getById(scheduleId)).thenAnswer(
          (_) async => const rd.Failure(
            NotFoundFailure(message: 'Schedule X not found'),
          ),
        );

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle(
          'c1',
          createExecuteScheduleMessage(requestId: 1, scheduleId: scheduleId),
          capture,
        );

        expect(getErrorCodeFromMessage(sent!), ErrorCode.scheduleNotFound);
        expect(getStatusCodeFromMessage(sent!), 404);
      },
    );

    test(
      'license policy fail -> LICENSE_DENIED (403)',
      () async {
        when(() => scheduleRepository.getById(scheduleId))
            .thenAnswer((_) async => rd.Success(schedule));
        when(() => destinationRepository.getByIds(any()))
            .thenAnswer((_) async => rd.Success([destination]));
        when(
          () => licensePolicyService.validateExecutionCapabilities(any(), any()),
        ).thenAnswer(
          (_) async => const rd.Failure(
            ValidationFailure(message: 'Licenca expirada'),
          ),
        );

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle(
          'c1',
          createExecuteScheduleMessage(requestId: 1, scheduleId: scheduleId),
          capture,
        );

        expect(getErrorCodeFromMessage(sent!), ErrorCode.licenseDenied);
        expect(getStatusCodeFromMessage(sent!), 403);
      },
    );

    test(
      'cancelSchedule sem execucao ativa -> NO_ACTIVE_EXECUTION (409)',
      () async {
        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle(
          'c1',
          createCancelScheduleMessage(requestId: 1, scheduleId: 'unknown-id'),
          capture,
        );

        expect(getErrorCodeFromMessage(sent!), ErrorCode.noActiveExecution);
        expect(getStatusCodeFromMessage(sent!), 409);
      },
    );

    test(
      'cancelSchedule com scheduleId vazio -> INVALID_REQUEST (400)',
      () async {
        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle(
          'c1',
          createCancelScheduleMessage(requestId: 1, scheduleId: ''),
          capture,
        );

        expect(getErrorCodeFromMessage(sent!), ErrorCode.invalidRequest);
        expect(getStatusCodeFromMessage(sent!), 400);
      },
    );
  });

  group('ScheduleMessageHandler runId in events (M2.3)', () {
    test(
      'mensagens de progresso enviadas durante backup carregam runId do contexto',
      () async {
        // Snapshot precisa retornar algo para o listener disparar
        when(() => progressNotifier.currentSnapshot).thenReturn(
          const BackupProgressSnapshot(
            step: 'Executando',
            message: 'em andamento',
            progress: 0.4,
          ),
        );

        // Captura listener registrado pelo handler para invoca-lo manualmente
        void Function()? capturedListener;
        when(() => progressNotifier.addListener(any())).thenAnswer((inv) {
          capturedListener = inv.positionalArguments.first as void Function();
        });
        when(() => progressNotifier.removeListener(any())).thenAnswer((_) {});

        // Recria handler com este mock especifico
        final localRegistry = RemoteExecutionRegistry();
        final localHandler = ScheduleMessageHandler(
          scheduleRepository: scheduleRepository,
          destinationRepository: destinationRepository,
          licensePolicyService: licensePolicyService,
          schedulerService: schedulerService,
          updateSchedule: updateSchedule,
          executeBackup: executeBackup,
          progressNotifier: progressNotifier,
          executionRegistry: localRegistry,
        );

        // Simula execucao em curso no registry
        final runId = localRegistry.generateRunId('schedule-X');
        final sentMessages = <Message>[];
        Future<void> capture(String clientId, Message msg) async {
          sentMessages.add(msg);
        }

        localRegistry.register(
          runId: runId,
          scheduleId: 'schedule-X',
          clientId: 'client-X',
          requestId: 555,
          sendToClient: capture,
        );

        // Dispara o listener manualmente (simula update do progressNotifier)
        expect(capturedListener, isNotNull);
        await Future(() => capturedListener!());
        // Aguarda microtask interno do handler async
        await Future.delayed(Duration.zero);

        expect(sentMessages, isNotEmpty);
        final progressMsg = sentMessages.firstWhere(
          isBackupProgressMessage,
        );
        expect(getRunIdFromBackupMessage(progressMsg), runId);
        expect(progressMsg.payload['scheduleId'], 'schedule-X');
        expect(progressMsg.header.requestId, 555);

        localHandler.dispose();
      },
    );

    test(
      'backupComplete enviado ao final inclui runId do contexto',
      () async {
        when(() => progressNotifier.currentSnapshot).thenReturn(
          const BackupProgressSnapshot(
            step: 'Concluído',
            message: 'ok',
            progress: 1,
            backupPath: '/tmp/x.zip',
          ),
        );

        void Function()? capturedListener;
        when(() => progressNotifier.addListener(any())).thenAnswer((inv) {
          capturedListener = inv.positionalArguments.first as void Function();
        });
        when(() => progressNotifier.removeListener(any())).thenAnswer((_) {});

        final localRegistry = RemoteExecutionRegistry();
        final localHandler = ScheduleMessageHandler(
          scheduleRepository: scheduleRepository,
          destinationRepository: destinationRepository,
          licensePolicyService: licensePolicyService,
          schedulerService: schedulerService,
          updateSchedule: updateSchedule,
          executeBackup: executeBackup,
          progressNotifier: progressNotifier,
          executionRegistry: localRegistry,
        );

        final runId = localRegistry.generateRunId('schedule-Y');
        final sentMessages = <Message>[];
        Future<void> capture(String clientId, Message msg) async {
          sentMessages.add(msg);
        }

        localRegistry.register(
          runId: runId,
          scheduleId: 'schedule-Y',
          clientId: 'client-Y',
          requestId: 888,
          sendToClient: capture,
        );

        await Future(() => capturedListener!());
        await Future.delayed(Duration.zero);

        final completeMsg = sentMessages.firstWhere(isBackupCompleteMessage);
        expect(getRunIdFromBackupMessage(completeMsg), runId);
        expect(completeMsg.payload['backupPath'], '/tmp/x.zip');
        // Apos enviar Concluído o registry desregistra (limpeza)
        expect(localRegistry.hasActiveForSchedule('schedule-Y'), isFalse);

        localHandler.dispose();
      },
    );

    test(
      'backupFailed enviado em snapshot Erro inclui runId',
      () async {
        when(() => progressNotifier.currentSnapshot).thenReturn(
          const BackupProgressSnapshot(
            step: 'Erro',
            message: 'falhou',
            error: 'erro x',
          ),
        );

        void Function()? capturedListener;
        when(() => progressNotifier.addListener(any())).thenAnswer((inv) {
          capturedListener = inv.positionalArguments.first as void Function();
        });
        when(() => progressNotifier.removeListener(any())).thenAnswer((_) {});

        final localRegistry = RemoteExecutionRegistry();
        final localHandler = ScheduleMessageHandler(
          scheduleRepository: scheduleRepository,
          destinationRepository: destinationRepository,
          licensePolicyService: licensePolicyService,
          schedulerService: schedulerService,
          updateSchedule: updateSchedule,
          executeBackup: executeBackup,
          progressNotifier: progressNotifier,
          executionRegistry: localRegistry,
        );

        final runId = localRegistry.generateRunId('schedule-Z');
        final sentMessages = <Message>[];
        Future<void> capture(String clientId, Message msg) async {
          sentMessages.add(msg);
        }

        localRegistry.register(
          runId: runId,
          scheduleId: 'schedule-Z',
          clientId: 'client-Z',
          requestId: 999,
          sendToClient: capture,
        );

        await Future(() => capturedListener!());
        await Future.delayed(Duration.zero);

        final failedMsg = sentMessages.firstWhere(isBackupFailedMessage);
        expect(getRunIdFromBackupMessage(failedMsg), runId);
        expect(failedMsg.payload['error'], 'erro x');

        localHandler.dispose();
      },
    );
  });
}
