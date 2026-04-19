import 'dart:convert';
import 'dart:io';

import 'package:backup_database/infrastructure/protocol/auth_messages.dart';
import 'package:backup_database/infrastructure/protocol/capabilities_messages.dart';
import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_queue_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/health_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/metrics_messages.dart';
import 'package:backup_database/infrastructure/protocol/preflight_messages.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/protocol/session_messages.dart';
import 'package:flutter_test/flutter_test.dart';

/// Golden tests do envelope JSON do protocolo socket (M6.1).
///
/// Trava o contrato de payload de cada `MessageType` critico contra
/// uma fixture commitada. Se algum factory mudar o shape do payload
/// (renomear campo, adicionar/remover chave, mudar tipo), o teste
/// falha com diff legivel.
///
/// Atualizar fixture intencionalmente:
///   `UPDATE_GOLDEN=1 flutter test test/golden/protocol/envelope_golden_test.dart`
///
/// O modo update reescreve a fixture a partir do output atual do
/// factory. Use SOMENTE em mudancas intencionais de contrato (com PR
/// dedicado e ADR de breaking change quando aplicavel).
///
/// Convencao das fixtures:
///   - apenas `type` (nome do `MessageType`) e `payload` sao validados
///   - `requestId`, `length` e `checksum` ficam fora porque dependem
///     de chamada/serializacao (covered em outros testes)
///   - servidor `v1` (sem `runId`) e `v2` (com `runId`) tem fixtures
///     separadas para garantir backward compat (M2.3)
void main() {
  group('Protocol envelope goldens', () {
    test('authResponse success', () {
      final msg = createAuthResponse(success: true);
      _assertGolden(msg, 'auth_response_success');
    });

    test('authResponse failure with errorCode', () {
      final msg = createAuthResponse(
        success: false,
        error: 'Credenciais invalidas',
        errorCode: ErrorCode.authenticationFailed,
      );
      _assertGolden(msg, 'auth_response_failure_with_code');
    });

    test('listSchedules', () {
      final msg = createListSchedulesMessage();
      _assertGolden(msg, 'list_schedules');
    });

    test('executeSchedule', () {
      final msg = createExecuteScheduleMessage(
        requestId: 1,
        scheduleId: 'schedule-1',
      );
      _assertGolden(msg, 'execute_schedule');
    });

    test('cancelSchedule', () {
      final msg = createCancelScheduleMessage(
        requestId: 1,
        scheduleId: 'schedule-1',
      );
      _assertGolden(msg, 'cancel_schedule');
    });

    test('scheduleCancelled', () {
      final msg = createScheduleCancelledMessage(
        requestId: 1,
        scheduleId: 'schedule-1',
      );
      _assertGolden(msg, 'schedule_cancelled');
    });

    group('backup events backward compat (M2.3)', () {
      test('backupProgress sem runId (servidor v1)', () {
        final msg = createBackupProgressMessage(
          requestId: 1,
          scheduleId: 'schedule-1',
          step: 'Iniciando',
          message: 'Iniciando backup',
        );
        _assertGolden(msg, 'backup_progress_v1_legacy');
      });

      test('backupProgress com runId (servidor v2+)', () {
        final msg = createBackupProgressMessage(
          requestId: 1,
          scheduleId: 'schedule-1',
          step: 'Executando backup',
          message: 'Executando backup do banco de dados...',
          progress: 0.5,
          runId: 'schedule-1_fixed-uuid-aaa',
        );
        _assertGolden(msg, 'backup_progress_v2_with_run_id');
      });

      test('backupComplete sem runId/backupPath (servidor v1)', () {
        final msg = createBackupCompleteMessage(
          requestId: 1,
          scheduleId: 'schedule-1',
        );
        _assertGolden(msg, 'backup_complete_v1_legacy');
      });

      test('backupComplete com runId e backupPath (servidor v2+)', () {
        final msg = createBackupCompleteMessage(
          requestId: 1,
          scheduleId: 'schedule-1',
          message: 'Backup concluído com sucesso',
          backupPath: 'remote/schedule-1/backup-2026-04-19.zip',
          runId: 'schedule-1_fixed-uuid-aaa',
        );
        _assertGolden(msg, 'backup_complete_v2_with_run_id_and_path');
      });

      test('backupFailed sem runId (servidor v1)', () {
        final msg = createBackupFailedMessage(
          requestId: 1,
          scheduleId: 'schedule-1',
          error: 'Conexão com banco perdida',
        );
        _assertGolden(msg, 'backup_failed_v1_legacy');
      });

      test('backupFailed com runId (servidor v2+)', () {
        final msg = createBackupFailedMessage(
          requestId: 1,
          scheduleId: 'schedule-1',
          error: 'Conexão com banco perdida',
          runId: 'schedule-1_fixed-uuid-aaa',
        );
        _assertGolden(msg, 'backup_failed_v2_with_run_id');
      });
    });

    group('error envelope', () {
      test('createScheduleErrorMessage (legado, sem errorCode)', () {
        final msg = createScheduleErrorMessage(
          requestId: 1,
          error: 'Já existe um backup em execução no servidor.',
        );
        _assertGolden(msg, 'schedule_error_legacy');
      });

      test('createScheduleErrorMessage com BACKUP_ALREADY_RUNNING (F0.2)', () {
        final msg = createScheduleErrorMessage(
          requestId: 1,
          error:
              'Já existe um backup em execução no servidor. '
              'Aguarde conclusão para iniciar novo.',
          errorCode: ErrorCode.backupAlreadyRunning,
        );
        _assertGolden(msg, 'schedule_error_backup_already_running');
      });

      test('createErrorMessage com errorCode', () {
        final msg = createErrorMessage(
          requestId: 1,
          errorMessage: 'Caminho não permitido',
          errorCode: ErrorCode.pathNotAllowed,
        );
        _assertGolden(msg, 'error_with_code');
      });

      test('createErrorMessage sem errorCode', () {
        final msg = createErrorMessage(
          requestId: 1,
          errorMessage: 'Failure ao processar mensagem',
        );
        _assertGolden(msg, 'error_without_code');
      });
    });

    group('metrics', () {
      test('metricsRequest', () {
        final msg = createMetricsRequestMessage();
        _assertGolden(msg, 'metrics_request');
      });

      test('metricsResponse minimal payload (legado, sem campos novos)', () {
        final msg = createMetricsResponseMessage(
          requestId: 1,
          payload: const {
            'backupInProgress': false,
            'totalBackupsToday': 3,
            'uptimeSeconds': 86400,
          },
        );
        _assertGolden(msg, 'metrics_response_minimal');
      });

      test(
        'metricsResponse v2 idle (servidor enriquecido, sem execucao ativa)',
        () {
          // Reproduz o payload que MetricsMessageHandler enriquecido
          // produz quando registry esta vazio e staging tem 0 bytes.
          final msg = createMetricsResponseMessage(
            requestId: 1,
            payload: const {
              'totalBackups': 42,
              'backupsToday': 3,
              'failedToday': 0,
              'activeSchedules': 5,
              'recentBackups': <Map<String, dynamic>>[],
              'backupInProgress': false,
              'serverTimeUtc': '2026-04-19T15:30:00.000Z',
              'activeRunCount': 0,
              'stagingUsageBytes': 0,
            },
          );
          _assertGolden(msg, 'metrics_response_v2_idle');
        },
      );

      test(
        'metricsResponse v2 com execucao ativa (M5.3/M7.1)',
        () {
          // Cenario: 1 backup remoto rodando, registry tem 1 ativo,
          // staging com ~500MB.
          final msg = createMetricsResponseMessage(
            requestId: 1,
            payload: const {
              'totalBackups': 42,
              'backupsToday': 3,
              'failedToday': 0,
              'activeSchedules': 5,
              'recentBackups': <Map<String, dynamic>>[],
              'backupInProgress': true,
              'serverTimeUtc': '2026-04-19T15:30:00.000Z',
              'backupScheduleName': 'Backup Diario Producao',
              'activeRunCount': 1,
              'activeRunId': 'schedule-prod-1_fixed-uuid-aaa',
              'stagingUsageBytes': 524288000,
            },
          );
          _assertGolden(msg, 'metrics_response_v2_with_active_run');
        },
      );
    });

    group('health (M1.10)', () {
      test('healthRequest tem payload vazio', () {
        final msg = createHealthRequestMessage();
        _assertGolden(msg, 'health_request');
      });

      test('healthResponse ok com checks minimos', () {
        final msg = createHealthResponseMessage(
          requestId: 1,
          status: ServerHealthStatus.ok,
          checks: const {'socket': true, 'database': true},
          serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
          uptimeSeconds: 3600,
        );
        _assertGolden(msg, 'health_response_ok');
      });

      test('healthResponse degraded com mensagem diagnostica', () {
        final msg = createHealthResponseMessage(
          requestId: 1,
          status: ServerHealthStatus.degraded,
          checks: const {
            'socket': true,
            'database': true,
            'staging': false,
          },
          serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
          uptimeSeconds: 7200,
          message: 'staging optional check failed',
        );
        _assertGolden(msg, 'health_response_degraded');
      });
    });

    group('session (M1.10)', () {
      test('sessionRequest tem payload vazio', () {
        final msg = createSessionRequestMessage();
        _assertGolden(msg, 'session_request');
      });

      test('sessionResponse com cliente autenticado e serverId', () {
        final msg = createSessionResponseMessage(
          requestId: 1,
          clientId: 'client-uuid-123',
          isAuthenticated: true,
          host: '192.168.1.10',
          port: 51234,
          connectedAt: DateTime.utc(2026, 4, 19, 10),
          serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
          serverId: 'server-A',
        );
        _assertGolden(msg, 'session_response_authenticated');
      });

      test('sessionResponse com cliente nao autenticado (sem serverId)', () {
        final msg = createSessionResponseMessage(
          requestId: 1,
          clientId: 'client-uuid-456',
          isAuthenticated: false,
          host: '127.0.0.1',
          port: 51235,
          connectedAt: DateTime.utc(2026, 4, 19, 10),
          serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
        );
        _assertGolden(msg, 'session_response_unauthenticated');
      });
    });

    group('preflight (F1.8)', () {
      test('preflightRequest tem payload vazio', () {
        final msg = createPreflightRequestMessage();
        _assertGolden(msg, 'preflight_request');
      });

      test('preflightResponse passed com checks bloqueantes ok', () {
        final msg = createPreflightResponseMessage(
          requestId: 1,
          status: PreflightStatus.passed,
          checks: const [
            PreflightCheckResult(
              name: 'compression_tool',
              passed: true,
              severity: PreflightSeverity.blocking,
              message: 'WinRAR detectado em PATH',
            ),
            PreflightCheckResult(
              name: 'temp_dir_writable',
              passed: true,
              severity: PreflightSeverity.blocking,
              message: 'Pasta temp gravavel',
            ),
          ],
          serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
        );
        _assertGolden(msg, 'preflight_response_passed');
      });

      test(
        'preflightResponse blocked com bloqueante + warning (com details)',
        () {
          final msg = createPreflightResponseMessage(
            requestId: 1,
            status: PreflightStatus.blocked,
            checks: const [
              PreflightCheckResult(
                name: 'compression_tool',
                passed: false,
                severity: PreflightSeverity.blocking,
                message: 'WinRAR nao encontrado no PATH',
              ),
              PreflightCheckResult(
                name: 'disk_space',
                passed: false,
                severity: PreflightSeverity.warning,
                message: 'Apenas 2GB livres',
                details: {
                  'freeBytes': 2147483648,
                  'requiredBytes': 5368709120,
                },
              ),
            ],
            serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
            message: 'Bloqueado: compression_tool, disk_space',
          );
          _assertGolden(msg, 'preflight_response_blocked');
        },
      );
    });

    group('execution status (PR-2 base / M2.3)', () {
      test('executionStatusRequest carrega runId', () {
        final msg = createExecutionStatusRequestMessage(
          requestId: 1,
          runId: 'sched-1_uuid-aaa',
        );
        _assertGolden(msg, 'execution_status_request');
      });

      test('executionStatusResponse running com snapshot completo', () {
        final msg = createExecutionStatusResponseMessage(
          requestId: 1,
          runId: 'sched-1_uuid-aaa',
          state: ExecutionState.running,
          serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
          scheduleId: 'sched-1',
          clientId: 'client-X',
          startedAt: DateTime.utc(2026, 4, 19, 11, 30),
        );
        _assertGolden(msg, 'execution_status_response_running');
      });

      test(
        'executionStatusResponse notFound com mensagem diagnostica',
        () {
          final msg = createExecutionStatusResponseMessage(
            requestId: 1,
            runId: 'unknown-runid',
            state: ExecutionState.notFound,
            serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
            message: 'Execucao nao encontrada no registry ativo',
          );
          _assertGolden(msg, 'execution_status_response_not_found');
        },
      );
    });

    group('execution queue (PR-3b base)', () {
      test('executionQueueRequest tem payload vazio', () {
        final msg = createExecutionQueueRequestMessage();
        _assertGolden(msg, 'execution_queue_request');
      });

      test('executionQueueResponse fila vazia (PR-1 default)', () {
        final msg = createExecutionQueueResponseMessage(
          requestId: 1,
          queue: const <QueuedExecution>[],
          maxQueueSize: 50,
          serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
        );
        _assertGolden(msg, 'execution_queue_response_empty');
      });

      test(
        'executionQueueResponse com 2 itens enfileirados (PR-3b futuro)',
        () {
          final msg = createExecutionQueueResponseMessage(
            requestId: 1,
            queue: [
              QueuedExecution(
                runId: 'sched-A_uuid-aaa',
                scheduleId: 'sched-A',
                queuedAt: DateTime.utc(2026, 4, 19, 11, 30),
                queuedPosition: 1,
                requestedBy: 'client-X',
              ),
              QueuedExecution(
                runId: 'sched-B_uuid-bbb',
                scheduleId: 'sched-B',
                queuedAt: DateTime.utc(2026, 4, 19, 11, 45),
                queuedPosition: 2,
              ),
            ],
            maxQueueSize: 50,
            serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
          );
          _assertGolden(msg, 'execution_queue_response_with_items');
        },
      );
    });

    group('capabilities (M1.3 / M4.1)', () {
      test('capabilitiesRequest tem payload vazio', () {
        final msg = createCapabilitiesRequestMessage();
        _assertGolden(msg, 'capabilities_request');
      });

      test('testDatabaseConnectionRequest por id', () {
        final msg = createTestDatabaseConnectionRequest(
          databaseType: RemoteDatabaseType.sybase,
          databaseConfigId: 'cfg-123',
          timeoutMs: 5000,
          requestId: 1,
        );
        _assertGolden(msg, 'test_database_connection_request_by_id');
      });

      test('testDatabaseConnectionRequest ad-hoc', () {
        final msg = createTestDatabaseConnectionRequest(
          databaseType: RemoteDatabaseType.postgres,
          config: <String, dynamic>{
            'host': 'db.local',
            'port': 5432,
            'database': 'app',
            'username': 'u',
            'password': 'p',
          },
          requestId: 2,
        );
        _assertGolden(msg, 'test_database_connection_request_adhoc');
      });

      test('testDatabaseConnectionResponse sucesso', () {
        final msg = createTestDatabaseConnectionResponse(
          requestId: 1,
          connected: true,
          latencyMs: 142,
          serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
          details: const {
            'serverVersion': '14.2',
          },
        );
        _assertGolden(msg, 'test_database_connection_response_success');
      });

      test('startBackupRequest com idempotencyKey', () {
        final msg = createStartBackupRequest(
          scheduleId: 'sch-1',
          idempotencyKey: 'idem-abc',
          requestId: 1,
        );
        _assertGolden(msg, 'start_backup_request');
      });

      test('startBackupResponse 202 accepted (running)', () {
        final msg = createStartBackupResponse(
          requestId: 1,
          runId: 'sch-1_uuid-123',
          state: ExecutionState.running,
          scheduleId: 'sch-1',
          serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
          message: 'Backup iniciado em background',
        );
        _assertGolden(msg, 'start_backup_response_running');
      });

      test('cancelBackupRequest por runId', () {
        final msg = createCancelBackupRequest(
          runId: 'sch-1_uuid-123',
          idempotencyKey: 'idem-cancel',
          requestId: 2,
        );
        _assertGolden(msg, 'cancel_backup_request_by_runid');
      });

      test('cancelBackupResponse cancelled', () {
        final msg = createCancelBackupResponse(
          requestId: 2,
          state: ExecutionState.cancelled,
          serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
          runId: 'sch-1_uuid-123',
          scheduleId: 'sch-1',
          message: 'Cancelamento sinalizado ao scheduler',
        );
        _assertGolden(msg, 'cancel_backup_response_cancelled');
      });

      test('cancelBackupResponse noActiveExecution', () {
        final msg = createCancelBackupResponse(
          requestId: 2,
          state: ExecutionState.notFound,
          serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
          runId: 'sch-1_uuid-xxx',
          message: 'Nenhuma execucao ativa com este runId',
          errorCode: ErrorCode.noActiveExecution,
        );
        _assertGolden(msg, 'cancel_backup_response_no_active');
      });

      test('testDatabaseConnectionResponse falha de auth', () {
        final msg = createTestDatabaseConnectionResponse(
          requestId: 1,
          connected: false,
          latencyMs: 87,
          serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
          error: 'usuario ou senha invalidos',
          errorCode: ErrorCode.authenticationFailed,
        );
        _assertGolden(msg, 'test_database_connection_response_auth_failed');
      });

      test('capabilitiesResponse v1 com flags atuais', () {
        final msg = createCapabilitiesResponseMessage(
          requestId: 1,
          protocolVersion: 1,
          wireVersion: 1,
          supportsRunId: true,
          supportsResume: true,
          supportsArtifactRetention: false,
          supportsChunkAck: false,
          supportsExecutionQueue: false,
          chunkSize: 65536,
          compression: 'gzip',
          serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
        );
        _assertGolden(msg, 'capabilities_response_v1');
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Caminho absoluto para o diretorio de fixtures, resolvido a partir do
/// diretorio do proprio arquivo de teste para evitar dependencia de cwd
/// (`flutter test` executa do package root, mas chamadas isoladas via IDE
/// podem variar).
String _fixturesDir() {
  final scriptUri = Uri.parse(Platform.script.toString());
  // Quando rodando via `flutter test`, Platform.script aponta para um
  // arquivo gerado em .dart_tool. O fallback usa caminho relativo ao
  // package root, que e o cwd de `flutter test`.
  final fromScript = File.fromUri(scriptUri).parent.path;
  if (fromScript.contains('test${Platform.pathSeparator}golden')) {
    return '$fromScript${Platform.pathSeparator}fixtures';
  }
  // Fallback: assume cwd no package root
  return 'test${Platform.pathSeparator}golden${Platform.pathSeparator}'
      'protocol${Platform.pathSeparator}fixtures';
}

/// Retorna `true` quando o usuario passou `UPDATE_GOLDEN=1` (ou similar)
/// para reescrever as fixtures a partir do output atual.
bool _shouldUpdate() {
  final value = Platform.environment['UPDATE_GOLDEN'];
  if (value == null) return false;
  final normalized = value.toLowerCase().trim();
  return normalized == '1' || normalized == 'true' || normalized == 'yes';
}

/// Compara `actual` com a fixture `name`. Em modo `UPDATE_GOLDEN`,
/// reescreve a fixture com o output atual e marca o teste como esperando
/// re-execucao normal.
void _assertGolden(Message actual, String name) {
  final fixturePath =
      '${_fixturesDir()}${Platform.pathSeparator}$name.golden.json';
  final fixtureFile = File(fixturePath);

  final actualGolden = <String, dynamic>{
    'type': actual.header.type.name,
    'payload': actual.payload,
  };

  if (_shouldUpdate()) {
    fixtureFile.writeAsStringSync(_prettyEncode(actualGolden));
    // Marca explicito para o usuario perceber que rodou em modo update
    fail(
      'UPDATE_GOLDEN=1 ativo. Fixture $name reescrita. '
      'Rode novamente sem UPDATE_GOLDEN para validar.',
    );
  }

  if (!fixtureFile.existsSync()) {
    fail(
      'Fixture nao encontrada: $fixturePath\n'
      'Crie a fixture ou rode com UPDATE_GOLDEN=1 para gerar.',
    );
  }

  final expected =
      jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;

  expect(
    actualGolden['type'],
    expected['type'],
    reason: 'message type divergiu da fixture $name',
  );
  expect(
    actualGolden['payload'],
    expected['payload'],
    reason:
        'payload divergiu da fixture $name. '
        'Se for mudanca intencional de contrato, rode '
        '`UPDATE_GOLDEN=1 flutter test ${fixturePath.replaceAll(r'\', '/')}` '
        'e revise o diff.',
  );
}

String _prettyEncode(Object obj) {
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert(obj)}\n';
}
