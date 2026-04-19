import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/socket/server/schedule_crud_message_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockScheduleRepository extends Mock implements IScheduleRepository {}

Schedule _schedule({String id = 's1', bool enabled = true}) => Schedule(
      id: id,
      name: 'Backup Diario',
      databaseConfigId: 'db-1',
      databaseType: DatabaseType.sqlServer,
      scheduleType: ScheduleType.daily.name,
      scheduleConfig: '{}',
      destinationIds: const ['dest-1'],
      backupFolder: r'C:\backup',
      enabled: enabled,
    );

void main() {
  late _MockScheduleRepository repo;
  late ScheduleCrudMessageHandler handler;
  late List<Message> sent;

  Future<void> sendToClient(String _, Message m) async {
    sent.add(m);
  }

  setUpAll(() {
    registerFallbackValue(_schedule());
  });

  setUp(() {
    repo = _MockScheduleRepository();
    handler = ScheduleCrudMessageHandler(scheduleRepository: repo);
    sent = [];
  });

  group('createSchedule', () {
    test('cria com sucesso e responde com schedule criado', () async {
      final s = _schedule();
      when(() => repo.create(any())).thenAnswer((_) async => rd.Success(s));

      final req = createCreateScheduleMessage(requestId: 1, schedule: s);
      await handler.handle('c1', req, sendToClient);

      final resp = sent.single;
      expect(resp.header.type, MessageType.scheduleMutationResponse);
      expect(resp.payload['operation'], 'created');
      expect(resp.payload['scheduleId'], s.id);
      expect(resp.payload['statusCode'], 200);
      expect(resp.payload['success'], isTrue);
      expect(resp.payload.containsKey('schedule'), isTrue);
    });

    test('falha do repo vira error UNKNOWN', () async {
      when(() => repo.create(any())).thenAnswer(
        (_) async => rd.Failure(Exception('db error')),
      );
      final req = createCreateScheduleMessage(
        requestId: 1,
        schedule: _schedule(),
      );
      await handler.handle('c1', req, sendToClient);
      final resp = sent.single;
      expect(resp.header.type, MessageType.error);
      expect(getErrorCodeFromMessage(resp), ErrorCode.unknown);
    });

    test('payload sem campo schedule -> invalidRequest', () async {
      final bad = Message(
        header: MessageHeader(
          type: MessageType.createSchedule,
          length: 0,
          requestId: 1,
        ),
        payload: const <String, dynamic>{},
        checksum: 0,
      );
      await handler.handle('c1', bad, sendToClient);
      final resp = sent.single;
      expect(resp.header.type, MessageType.error);
      expect(getErrorCodeFromMessage(resp), ErrorCode.invalidRequest);
    });
  });

  group('deleteSchedule', () {
    test('deleta com sucesso quando existe', () async {
      final s = _schedule();
      when(() => repo.getById(s.id)).thenAnswer((_) async => rd.Success(s));
      when(() => repo.delete(s.id)).thenAnswer((_) async => const rd.Success('ok'));

      final req = createDeleteScheduleMessage(requestId: 1, scheduleId: s.id);
      await handler.handle('c1', req, sendToClient);
      final resp = sent.single;
      expect(resp.payload['operation'], 'deleted');
      expect(resp.payload['scheduleId'], s.id);
      expect(resp.payload.containsKey('schedule'), isFalse);
    });

    test('scheduleId desconhecido -> 404 SCHEDULE_NOT_FOUND', () async {
      when(() => repo.getById('x')).thenAnswer(
        (_) async => rd.Failure(Exception('not found')),
      );
      final req = createDeleteScheduleMessage(requestId: 1, scheduleId: 'x');
      await handler.handle('c1', req, sendToClient);
      final resp = sent.single;
      expect(resp.header.type, MessageType.error);
      expect(getErrorCodeFromMessage(resp), ErrorCode.scheduleNotFound);
    });

    test('scheduleId vazio -> invalidRequest', () async {
      final req = createDeleteScheduleMessage(requestId: 1, scheduleId: '');
      await handler.handle('c1', req, sendToClient);
      final resp = sent.single;
      expect(getErrorCodeFromMessage(resp), ErrorCode.invalidRequest);
    });
  });

  group('pauseSchedule / resumeSchedule', () {
    test('pause: muda enabled para false', () async {
      final s = _schedule();
      when(() => repo.getById(s.id)).thenAnswer((_) async => rd.Success(s));
      when(() => repo.update(any())).thenAnswer(
        (inv) async => rd.Success(inv.positionalArguments[0] as Schedule),
      );

      final req = createPauseScheduleMessage(requestId: 1, scheduleId: s.id);
      await handler.handle('c1', req, sendToClient);
      final resp = sent.single;
      expect(resp.payload['operation'], 'paused');
      final captured = verify(() => repo.update(captureAny())).captured;
      expect((captured.first as Schedule).enabled, isFalse);
    });

    test('resume: muda enabled para true', () async {
      final s = _schedule(enabled: false);
      when(() => repo.getById(s.id)).thenAnswer((_) async => rd.Success(s));
      when(() => repo.update(any())).thenAnswer(
        (inv) async => rd.Success(inv.positionalArguments[0] as Schedule),
      );

      final req = createResumeScheduleMessage(requestId: 1, scheduleId: s.id);
      await handler.handle('c1', req, sendToClient);
      final resp = sent.single;
      expect(resp.payload['operation'], 'resumed');
      final captured = verify(() => repo.update(captureAny())).captured;
      expect((captured.first as Schedule).enabled, isTrue);
    });

    test(
      'pause em schedule ja desabilitado: idempotente, NAO chama update',
      () async {
        final s = _schedule(enabled: false);
        when(() => repo.getById(s.id)).thenAnswer((_) async => rd.Success(s));

        final req = createPauseScheduleMessage(requestId: 1, scheduleId: s.id);
        await handler.handle('c1', req, sendToClient);
        verifyNever(() => repo.update(any()));
        expect(sent.single.payload['operation'], 'paused');
      },
    );

    test('schedule nao existe -> 404', () async {
      when(() => repo.getById('x')).thenAnswer(
        (_) async => rd.Failure(Exception('not found')),
      );
      final req = createPauseScheduleMessage(requestId: 1, scheduleId: 'x');
      await handler.handle('c1', req, sendToClient);
      expect(getErrorCodeFromMessage(sent.single), ErrorCode.scheduleNotFound);
    });
  });

  group('idempotencyKey', () {
    test(
      'create com mesma chave: 2a chamada NAO chama repo.create de novo',
      () async {
        final s = _schedule();
        when(() => repo.create(any())).thenAnswer((_) async => rd.Success(s));

        final req = createCreateScheduleMessage(
          requestId: 1,
          schedule: s,
          idempotencyKey: 'idem-create',
        );
        await handler.handle('c1', req, sendToClient);
        await handler.handle('c1', req, sendToClient);

        verify(() => repo.create(any())).called(1);
        expect(sent, hasLength(2));
        expect(
          sent[0].payload['scheduleId'],
          equals(sent[1].payload['scheduleId']),
        );
      },
    );

    test('falha NAO e cacheada (cliente pode tentar de novo)', () async {
      final s = _schedule();
      when(() => repo.create(any())).thenAnswer(
        (_) async => rd.Failure(Exception('db transient')),
      );
      final req = createCreateScheduleMessage(
        requestId: 1,
        schedule: s,
        idempotencyKey: 'idem-x',
      );
      await handler.handle('c1', req, sendToClient);
      expect(sent.last.header.type, MessageType.error);

      // Agora repo funciona
      when(() => repo.create(any())).thenAnswer((_) async => rd.Success(s));
      await handler.handle('c1', req, sendToClient);
      expect(sent.last.header.type, MessageType.scheduleMutationResponse);
    });
  });

  group('outros tipos', () {
    test('ignora mensagem nao relacionada (no-op)', () async {
      final unrelated = Message(
        header: MessageHeader(type: MessageType.heartbeat, length: 0),
        payload: const <String, dynamic>{},
        checksum: 0,
      );
      await handler.handle('c1', unrelated, sendToClient);
      expect(sent, isEmpty);
    });
  });

  group('ScheduleMutationResult helpers', () {
    test('isCreated/isDeleted/isPaused/isResumed', () {
      const r1 = ScheduleMutationResult(
        operation: 'created',
        scheduleId: 's',
      );
      expect(r1.isCreated, isTrue);
      expect(r1.isDeleted, isFalse);

      const r2 = ScheduleMutationResult(operation: 'deleted', scheduleId: 's');
      expect(r2.isDeleted, isTrue);

      const r3 = ScheduleMutationResult(operation: 'paused', scheduleId: 's');
      expect(r3.isPaused, isTrue);

      const r4 = ScheduleMutationResult(operation: 'resumed', scheduleId: 's');
      expect(r4.isResumed, isTrue);
    });
  });
}
