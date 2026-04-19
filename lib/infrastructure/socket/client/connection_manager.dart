import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/core/di/service_locator.dart' as di;
import 'package:backup_database/core/logging/logging.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/remote_file_entry.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/infrastructure/datasources/daos/server_connection_dao.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/protocol/capabilities_messages.dart';
import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_queue_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/file_transfer_messages.dart';
import 'package:backup_database/infrastructure/protocol/health_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/metrics_messages.dart';
import 'package:backup_database/infrastructure/protocol/preflight_messages.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/protocol/session_messages.dart';
import 'package:backup_database/infrastructure/socket/client/file_transfer_resume_metadata_store.dart';
import 'package:backup_database/infrastructure/socket/client/socket_client_service.dart';
import 'package:backup_database/infrastructure/socket/client/tcp_socket_client.dart';
import 'package:crypto/crypto.dart';
import 'package:result_dart/result_dart.dart' as rd;

typedef BackupProgressCallback =
    void Function(
      String step,
      String message,
      double progress,
    );

class ConnectionManager {
  ConnectionManager({
    ServerConnectionDao? serverConnectionDao,
    FileTransferResumeMetadataStore? resumeMetadataStore,
  }) : _serverConnectionDao = serverConnectionDao,
       _resumeMetadataStore =
           resumeMetadataStore ?? const FileTransferResumeMetadataStore(),
       _socketLogger = di.getIt<SocketLoggerService>();

  final ServerConnectionDao? _serverConnectionDao;
  final FileTransferResumeMetadataStore _resumeMetadataStore;
  final SocketLoggerService _socketLogger;
  TcpSocketClient? _client;
  String? _activeHost;
  int? _activePort;
  int _nextRequestId = 0;
  final Map<int, Completer<Message>> _pendingRequests = {};
  StreamSubscription<Message>? _messageSubscription;

  /// Subscription do `statusStream` do client. Antes não havia listener
  /// — quando a conexão caía abruptamente (timeout, RST), os completers
  /// em `_pendingRequests` ficavam pendurados para sempre, vazando
  /// memória e deixando UIs esperando indefinidamente.
  StreamSubscription<ConnectionStatus>? _statusSubscription;

  final Map<int, _FileTransferState> _activeTransfers = {};
  final Map<int, _BackupProgressState> _activeBackups = {};

  /// Cache do snapshot de capabilities da conexao atual.
  ///
  /// Populado por [refreshServerCapabilities] (tipicamente chamado logo
  /// apos a autenticacao bem-sucedida). Permanece `null` ate o cliente
  /// pedir explicitamente. Quando o servidor nao implementa
  /// `capabilitiesRequest` (legado v1) ou a chamada falha, o cache e
  /// preenchido com [ServerCapabilities.legacyDefault] para que
  /// providers consumam um snapshot consistente sem ter que tratar
  /// "ausencia de capabilities" caso a caso (M4.1 - degradacao graceful).
  ///
  /// Resetado para `null` em [disconnect] para evitar uso de capabilities
  /// stale apos reconexao a um servidor potencialmente diferente.
  ServerCapabilities? _cachedServerCapabilities;

  // Getter para verificar se há transferências ativas (usado pelo heartbeat)
  bool get hasActiveTransfers => _activeTransfers.isNotEmpty;

  TcpSocketClient? get activeClient => _client;
  String? get activeHost => _activeHost;
  int? get activePort => _activePort;
  bool get isConnected => _client?.isConnected ?? false;
  ConnectionStatus get status =>
      _client?.status ?? ConnectionStatus.disconnected;
  String? get lastErrorMessage => _client?.lastErrorMessage;
  Stream<Message>? get messageStream => _client?.messageStream;
  Stream<ConnectionStatus>? get statusStream => _client?.statusStream;

  /// Snapshot atual das capabilities reportadas pelo servidor (M4.1).
  ///
  /// `null` ate [refreshServerCapabilities] ser chamado pela primeira
  /// vez (ou ate o auto-refresh em [connect] completar). Apos populado,
  /// fica disponivel para providers como gate de feature sincrono — sem
  /// precisar fazer round-trip para o servidor a cada decisao.
  ///
  /// Convencao: prefira os getters de feature especificos
  /// ([isRunIdSupported], [isExecutionQueueSupported], etc.) em vez
  /// de inspecionar este snapshot diretamente — eles ja fazem o
  /// fallback para [ServerCapabilities.legacyDefault] quando o cache
  /// esta vazio.
  ServerCapabilities? get serverCapabilities => _cachedServerCapabilities;

  /// Capabilities efetivas: usa o cache quando disponivel, senao cai
  /// em [ServerCapabilities.legacyDefault]. Garante que getters de
  /// feature nunca retornem decisao indefinida — providers podem
  /// consultar com seguranca em qualquer ponto do ciclo de vida.
  ServerCapabilities get _effectiveCapabilities =>
      _cachedServerCapabilities ?? ServerCapabilities.legacyDefault;

  /// `true` quando o servidor anuncia suporte a `runId` no contrato
  /// de progresso de backup (M2.3). Falso para servidor `v1` legado
  /// ou quando capabilities ainda nao foram carregadas — fluxos
  /// dependentes de `runId` devem usar `scheduleId` como fallback.
  bool get isRunIdSupported => _effectiveCapabilities.supportsRunId;

  /// `true` quando o servidor anuncia suporte a fila de execucao
  /// (`backupQueued/Dequeued/Started`, `getExecutionQueue`,
  /// `cancelQueuedBackup` — PR-3b). Falso por enquanto em todos os
  /// servidores ate a fila ser implementada.
  bool get isExecutionQueueSupported =>
      _effectiveCapabilities.supportsExecutionQueue;

  /// `true` quando o servidor anuncia retencao formal de artefato com
  /// TTL e `getArtifactMetadata` (PR-4). Cliente deve usar este gate
  /// antes de habilitar logica de re-download por `artifactExpiresAt`.
  bool get isArtifactRetentionSupported =>
      _effectiveCapabilities.supportsArtifactRetention;

  /// `true` quando o servidor anuncia suporte a `fileAck`/janela na
  /// transferencia de arquivos. Em `v1` e sempre falso por decisao
  /// explicita de ADR-002.
  bool get isChunkAckSupported => _effectiveCapabilities.supportsChunkAck;

  Future<void> connect({
    required String host,
    required int port,
    String? serverId,
    String? password,
    bool enableAutoReconnect = false,
    bool refreshCapabilitiesOnConnect = true,
  }) async {
    await disconnect();
    _client = TcpSocketClient(
      socketLogger: _socketLogger,
      canDisconnectOnTimeout: () => !hasActiveTransfers,
    );
    await _client!.connect(
      host: host,
      port: port,
      serverId: serverId,
      password: password,
      enableAutoReconnect: enableAutoReconnect,
    );
    _activeHost = host;
    _activePort = port;
    _messageSubscription = _client!.messageStream.listen(_onMessage);
    // Observa transições de status para abortar requests pendentes
    // quando a conexão cair sem chamar `disconnect()` explicitamente.
    _statusSubscription = _client!.statusStream.listen(_onStatusChanged);
    final useAuth =
        serverId != null &&
        serverId.isNotEmpty &&
        password != null &&
        password.isNotEmpty;
    try {
      await _awaitConnectionReady(useAuth: useAuth);
    } on Object {
      await disconnect();
      rethrow;
    }

    // Apos conexao estavel, popula cache de capabilities para que
    // providers nao precisem chamar `refreshServerCapabilities()`
    // manualmente. Em servidor `v1` que nao implementa o endpoint, o
    // refresh cai no fallback `legacyDefault` (zero risco — ver
    // `refreshServerCapabilities`). Pode ser desabilitado via
    // [refreshCapabilitiesOnConnect] em testes especificos ou cenarios
    // onde o consumidor quer controlar o timing.
    if (refreshCapabilitiesOnConnect) {
      try {
        await refreshServerCapabilities();
      } on Object catch (e) {
        // `refreshServerCapabilities` ja faz fallback graceful, mas
        // protege contra exception sincrona (raro — apenas se o futuro
        // for cancelado durante shutdown concorrente).
        LoggerService.warning(
          '[ConnectionManager] Refresh automatico de capabilities falhou: $e. '
          'Cache permanece ${_cachedServerCapabilities == null ? "vazio" : "populado"}.',
        );
      }
    }
  }

  Future<void> _awaitConnectionReady({required bool useAuth}) async {
    final client = _client;
    if (client == null) {
      throw StateError('ConnectionManager not connected');
    }

    if (!useAuth) {
      if (!client.isConnected) {
        throw StateError(
          client.lastErrorMessage ?? 'Não foi possível conectar ao servidor',
        );
      }
      return;
    }

    final deadline = DateTime.now().add(SocketConfig.connectionTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final currentStatus = client.status;
      if (currentStatus == ConnectionStatus.connected) {
        return;
      }

      if (currentStatus == ConnectionStatus.authenticationFailed) {
        throw StateError(
          client.lastErrorMessage ?? 'Autenticação rejeitada pelo servidor',
        );
      }

      if (currentStatus == ConnectionStatus.error) {
        throw StateError(
          client.lastErrorMessage ?? 'Erro ao conectar no servidor',
        );
      }

      if (currentStatus == ConnectionStatus.disconnected) {
        throw StateError(
          client.lastErrorMessage ??
              'Conexão encerrada pelo servidor durante autenticação',
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    throw TimeoutException(
      'Tempo esgotado aguardando resposta de autenticação do servidor',
    );
  }

  /// Callback do `statusStream`: quando a conexão entra em estado
  /// terminal sem `disconnect()` explícito, faz cleanup dos completers
  /// pendentes para evitar vazamento e UIs travadas. O cleanup é
  /// idempotente — se `disconnect()` for chamado depois, encontra os
  /// maps vazios.
  void _onStatusChanged(ConnectionStatus status) {
    final isTerminal =
        status == ConnectionStatus.disconnected ||
        status == ConnectionStatus.error ||
        status == ConnectionStatus.authenticationFailed;
    if (!isTerminal) return;
    if (_pendingRequests.isEmpty &&
        _activeBackups.isEmpty &&
        _activeTransfers.isEmpty) {
      return;
    }
    LoggerService.warning(
      '[ConnectionManager] Conexão entrou em estado $status com '
      '${_pendingRequests.length} request(s), '
      '${_activeTransfers.length} transferência(s) e '
      '${_activeBackups.length} backup(s) pendente(s) — abortando.',
    );
    _abortPending(status);
  }

  /// Aborta todas as operações pendentes com um erro indicando o estado
  /// da conexão. Extraído para reuso entre [_onStatusChanged] e
  /// [disconnect] no futuro (atualmente `disconnect` ainda tem sua
  /// própria implementação ligeiramente diferente para fileSink close).
  void _abortPending(ConnectionStatus status) {
    final stateError = StateError(
      'Conexão encerrada (status: $status) com operações pendentes',
    );
    final exception = Exception(stateError.message);
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(stateError);
      }
    }
    _pendingRequests.clear();
    for (final state in _activeBackups.values) {
      if (!state.completer.isCompleted) {
        state.completer.complete(rd.Failure(exception));
      }
    }
    _activeBackups.clear();
    for (final state in _activeTransfers.values) {
      if (!state.completer.isCompleted) {
        state.completer.complete(rd.Failure(exception));
      }
    }
    _activeTransfers.clear();
  }

  void _onMessage(Message message) {
    final requestId = message.header.requestId;
    final transferState = _activeTransfers[requestId];
    if (transferState != null) {
      _handleFileTransferMessage(requestId, message, transferState);
      return;
    }
    final backupState = _activeBackups[requestId];
    if (backupState != null) {
      _handleBackupProgressMessage(message, backupState);
      return;
    }
    final completer = _pendingRequests.remove(requestId);
    completer?.complete(message);
  }

  Future<void> _handleFileTransferMessage(
    int requestId,
    Message message,
    _FileTransferState state,
  ) async {
    if (isFileTransferStartMetadata(message)) {
      state.fileName = getFileNameFromMetadata(message);
      state.totalChunks = getTotalChunksFromMetadata(message);
      state.isCompressed = getIsCompressedFromMetadata(message);
      state.expectedSize = getFileSizeFromMetadata(message);
      state.transferChunkSize =
          getChunkSizeFromMetadata(message) ?? SocketConfig.chunkSize;
      if (state.transferChunkSize <= 0) {
        state.transferChunkSize = SocketConfig.chunkSize;
      }

      // Validar SHA-256 (Fase 2)
      if (message.payload.containsKey('hash')) {
        state.expectedHash = getHashFromMetadata(message);
      }

      LoggerService.info(
        '[ConnectionManager] Metadata recebida: ${state.fileName}, '
        'chunks: ${state.totalChunks}, compressed: ${state.isCompressed}, '
        'expectedSize: ${state.expectedSize}, '
        'chunkSize: ${state.transferChunkSize}',
      );

      try {
        await _resumeMetadataStore.write(
          state.outputPath,
          FileTransferResumeMetadata(
            filePath: state.sourceFilePath,
            partFilePath: state.partFilePath,
            chunkSize: state.transferChunkSize,
            expectedSize: state.expectedSize > 0 ? state.expectedSize : null,
            expectedHash: state.expectedHash,
            isCompressed: state.isCompressed,
            scheduleId: state.scheduleId,
            updatedAt: DateTime.now(),
          ),
        );
      } on Object catch (e) {
        LoggerService.warning(
          '[ConnectionManager] Falha ao persistir metadata de resume: $e',
        );
      }
      return;
    }
    if (isFileChunkMessage(message)) {
      final chunk = getFileChunkFromPayload(message);
      var dataToWrite = chunk.data;

      // Decompressão (Fase 3)
      if (state.isCompressed) {
        try {
          dataToWrite = Uint8List.fromList(gzip.decode(chunk.data));
          LoggerService.debug(
            '[ConnectionManager] Chunk descomprimido: ${chunk.data.length} -> ${dataToWrite.length} bytes',
          );
        } on Object catch (e) {
          LoggerService.error(
            '[ConnectionManager] Falha ao descomprimir chunk ${chunk.chunkIndex}: $e',
          );
          await _cleanupTransfer(requestId);
          state.completer.complete(
            rd.Failure(Exception('Falha na descompressão GZIP: $e')),
          );
          return;
        }
      }

      // Streaming: Escrever diretamente no sink
      state.fileSink.add(dataToWrite);
      if (chunk.chunkIndex % 10 == 0) {
        // Flush periódico opcional
      }

      LoggerService.debug(
        '[ConnectionManager] Chunk ${chunk.chunkIndex}/${chunk.totalChunks} recebido e escrito: ${chunk.data.length} bytes',
      );
      return;
    }
    if (isFileTransferProgressMessage(message)) {
      final current = getCurrentChunkFromProgress(message);
      final total = getTotalChunksFromProgress(message);
      state.onProgress?.call(current, total);
      LoggerService.debug('[ConnectionManager] Progresso: $current/$total');
      return;
    }
    if (isFileTransferCompleteMessage(message)) {
      LoggerService.info(
        '[ConnectionManager] Transferência completa recebida, finalizando arquivo...',
      );
      _activeTransfers.remove(requestId);
      _completeFileTransfer(state);
      return;
    }
    if (isFileTransferErrorMessage(message)) {
      final error = getErrorFromFileTransferError(message);
      LoggerService.error(
        '[ConnectionManager] Erro de transferência recebido: $error',
      );
      _cleanupTransfer(requestId);
      state.completer.complete(
        rd.Failure(Exception(error)),
      );
    }
  }

  Future<void> _completeFileTransfer(_FileTransferState state) async {
    LoggerService.info('[ConnectionManager] _completeFileTransfer iniciado');
    LoggerService.info('[ConnectionManager] OutputPath: ${state.outputPath}');

    try {
      // Finalizar escrita no .part
      await state.fileSink.flush();
      await state.fileSink.close();

      // AGUARDAR liberação do arquivo no Windows (bug de lock)
      await _waitForFileRelease(state.partFilePath);

      final partFile = File(state.partFilePath);
      final finalFile = File(state.outputPath);

      // Verificar tamanho do arquivo baixado
      final partSize = await partFile.length();
      LoggerService.info(
        '[ConnectionManager] Tamanho do arquivo parcial: $partSize bytes',
      );

      // Validar tamanho esperado (se disponível no metadata)
      if (state.expectedSize > 0) {
        LoggerService.info(
          '[ConnectionManager] Validando tamanho: esperado=${state.expectedSize}, baixado=$partSize',
        );
        if (partSize != state.expectedSize) {
          LoggerService.error(
            '[ConnectionManager] Tamanho incorreto! Esperado: ${state.expectedSize}, Recebido: $partSize',
          );
          await partFile.delete(); // Deletar arquivo incompleto/corrompido
          throw FileSystemException(
            'Tamanho do arquivo incorreto. Esperado: ${state.expectedSize}, Recebido: $partSize',
            state.outputPath,
          );
        }
        LoggerService.info(
          '[ConnectionManager] ✓ Tamanho validado com sucesso!',
        );
      } else {
        LoggerService.warning(
          '[ConnectionManager] Tamanho esperado não disponível no metadata. Pulando validação de tamanho.',
        );
      }

      // Validar SHA-256 (Fase 2)
      if (state.expectedHash != null && state.expectedHash!.isNotEmpty) {
        LoggerService.info(
          '[ConnectionManager] Calculando SHA-256 para validação...',
        );
        final digest = await sha256.bind(partFile.openRead()).first;
        final actualHash = digest.toString();

        if (actualHash != state.expectedHash) {
          LoggerService.error(
            '[ConnectionManager] SHA-256 Checksum FALHOU! Esperado: ${state.expectedHash}, Calculado: $actualHash',
          );
          await partFile.delete(); // Deletar arquivo corrompido
          throw FileSystemException(
            'Falha de integridade: SHA-256 inválido.',
            state.outputPath,
          );
        }
        LoggerService.info(
          '[ConnectionManager] SHA-256 Verificado com sucesso.',
        );
      } else {
        LoggerService.warning(
          '[ConnectionManager] SHA-256 não disponível no metadata. Integridade não verificada.',
        );
      }

      // Rename Atômico: .part -> Final
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await partFile.rename(state.outputPath);
      LoggerService.info(
        '[ConnectionManager] ✓ Arquivo renomeado e salvo com sucesso!',
      );
      await _resumeMetadataStore.delete(state.outputPath);

      state.completer.complete(const rd.Success(rd.unit));
    } on Object catch (e) {
      LoggerService.error('[ConnectionManager] ✗ Erro ao salvar arquivo: $e');
      state.completer.complete(
        rd.Failure(e is Exception ? e : Exception(e.toString())),
      );
    }
  }

  /// Aguarda o arquivo ser liberado pelo sistema operacional.
  /// Necessário no Windows para evitar lock quando o arquivo ainda está
  /// sendo usado por outro processo (antivirus, indexador, etc).
  Future<void> _waitForFileRelease(String filePath) async {
    const maxAttempts = 10;
    const delayMs = 100;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        // Tentar abrir o arquivo em modo leitura para verificar se está liberado
        final file = File(filePath);
        final handle = await file.open();
        await handle.close();
        LoggerService.info(
          '[ConnectionManager] Arquivo liberado na tentativa ${attempt + 1}',
        );
        return; // Arquivo liberado
      } on Object catch (e) {
        LoggerService.debug(
          '[ConnectionManager] Arquivo ainda travado (tentativa ${attempt + 1}): $e',
        );
        if (attempt < maxAttempts - 1) {
          await Future.delayed(Duration(milliseconds: delayMs * (attempt + 1)));
        } else {
          LoggerService.warning(
            '[ConnectionManager] Arquivo ainda travado após $maxAttempts tentativas. Continuando...',
          );
        }
      }
    }
  }

  void _handleBackupProgressMessage(
    Message message,
    _BackupProgressState state,
  ) {
    // Log para rastrear tipo de mensagem recebida
    LoggerService.info(
      '[ConnectionManager._handleBackupProgressMessage] Tipo: ${message.header.type.name}, RequestID: ${message.header.requestId}',
    );
    LoggerService.info(
      '[ConnectionManager._handleBackupProgressMessage] Payload: ${message.payload}',
    );

    // M2.3: captura `runId` do payload na primeira mensagem que o trouxer.
    // Servidores `v1` nao enviam o campo (`getRunIdFromBackupMessage` retorna
    // null) — o cliente continua operando normalmente sem rastreamento por
    // execucao. Servidores `v2+` populam sempre, e o cliente passa a poder
    // correlacionar progresso/conclusao/falha pela mesma execucao logica.
    final messageRunId = getRunIdFromBackupMessage(message);
    if (messageRunId != null && state.runId == null) {
      state.runId = messageRunId;
      LoggerService.debug(
        '[ConnectionManager] runId capturado para backup: $messageRunId',
      );
    }

    if (isBackupProgressMessage(message)) {
      final step = getStepFromBackupProgress(message) ?? '';
      final progressMessage = getMessageFromBackupProgress(message) ?? '';
      final progress = getProgressFromBackupProgress(message) ?? 0.0;
      state.onProgress?.call(step, progressMessage, progress);
      return;
    }
    if (isBackupCompleteMessage(message)) {
      LoggerService.info(
        '[ConnectionManager] ✓ Mensagem backupComplete recebida!'
        '${state.runId != null ? ' (runId=${state.runId})' : ''}',
      );
      final path = getBackupPathFromBackupComplete(message);
      LoggerService.info('[ConnectionManager] backupPath extraído: "$path"');
      _activeBackups.remove(message.header.requestId);
      state.onProgress?.call('Concluído', 'Backup concluído com sucesso!', 1);
      if (!state.completer.isCompleted) {
        state.completer.complete(rd.Success(path ?? ''));
      }
      return;
    }
    if (isBackupFailedMessage(message)) {
      _activeBackups.remove(message.header.requestId);
      final error = getErrorFromBackupFailed(message) ?? 'Erro desconhecido';
      LoggerService.warning(
        '[ConnectionManager] backupFailed'
        '${state.runId != null ? ' (runId=${state.runId})' : ''}: $error',
      );
      state.completer.complete(rd.Failure(Exception(error)));
      return;
    }
  }

  Future<void> disconnect() async {
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _statusSubscription?.cancel();
    _statusSubscription = null;

    // Fechar todos os fileSinks antes de limpar
    for (final entry in _activeTransfers.entries) {
      if (!entry.value.completer.isCompleted) {
        entry.value.completer.complete(
          rd.Failure(Exception('Disconnected during file transfer')),
        );
        try {
          await entry.value.fileSink.close();
        } on Object catch (e) {
          LoggerService.warning(
            '[ConnectionManager] Erro ao fechar fileSink durante disconnect: $e',
          );
        }
      }
    }
    _activeTransfers.clear();

    for (final state in _activeBackups.values) {
      if (!state.completer.isCompleted) {
        state.completer.complete(
          rd.Failure(Exception('Disconnected during backup')),
        );
      }
    }
    _activeBackups.clear();
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Disconnected'));
      }
    }
    _pendingRequests.clear();
    // Invalida cache de capabilities: proxima conexao pode ser para
    // um servidor diferente, com versao/flags distintas. Manter cache
    // antigo levaria providers a habilitar features inexistentes no
    // novo servidor.
    _cachedServerCapabilities = null;
    if (_client != null) {
      await _client!.disconnect();
      _client = null;
      _activeHost = null;
      _activePort = null;
    }
  }

  Future<rd.Result<List<Schedule>>> listSchedules() async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    try {
      await send(createListSchedulesMessage(requestId: requestId));
      final message = await completer.future.timeout(
        SocketConfig.scheduleRequestTimeout,
      );
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (message.header.type != MessageType.scheduleList) {
        return rd.Failure(
          Exception('Resposta inesperada: ${message.header.type.name}'),
        );
      }
      return rd.Success(getSchedulesFromListPayload(message));
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(TimeoutException('listSchedules timeout'));
    } on Object catch (e, stackTrace) {
      _pendingRequests.remove(requestId);
      LoggerService.warning(
        '[ConnectionManager] listSchedules falhou',
        e,
        stackTrace,
      );
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  Future<rd.Result<Schedule>> updateSchedule(Schedule schedule) async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    try {
      await send(
        createUpdateScheduleMessage(requestId: requestId, schedule: schedule),
      );
      final message = await completer.future.timeout(
        SocketConfig.scheduleRequestTimeout,
      );
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (message.header.type != MessageType.scheduleUpdated) {
        return rd.Failure(
          Exception('Resposta inesperada: ${message.header.type.name}'),
        );
      }
      return rd.Success(getScheduleFromUpdatePayload(message));
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(TimeoutException('updateSchedule timeout'));
    } on Object catch (e, stackTrace) {
      _pendingRequests.remove(requestId);
      LoggerService.warning(
        '[ConnectionManager] updateSchedule falhou',
        e,
        stackTrace,
      );
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  Future<rd.Result<List<RemoteFileEntry>>> listAvailableFiles() async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    try {
      await send(createListFilesMessage(requestId: requestId));
      final message = await completer.future.timeout(
        SocketConfig.scheduleRequestTimeout,
      );
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (message.header.type != MessageType.fileList) {
        return rd.Failure(
          Exception('Resposta inesperada: ${message.header.type.name}'),
        );
      }
      return rd.Success(getFileListFromPayload(message));
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(TimeoutException('listAvailableFiles timeout'));
    } on Object catch (e, stackTrace) {
      _pendingRequests.remove(requestId);
      LoggerService.warning(
        '[ConnectionManager] listAvailableFiles falhou',
        e,
        stackTrace,
      );
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  bool _canResumeWithMetadata({
    required FileTransferResumeMetadata? metadata,
    required String filePath,
    required String? scheduleId,
  }) {
    if (metadata == null) {
      return true;
    }
    final sameFile = metadata.filePath == filePath;
    final sameSchedule = metadata.scheduleId == scheduleId;
    return sameFile && sameSchedule;
  }

  Future<rd.Result<void>> requestFile({
    required String filePath,
    required String outputPath,
    String? scheduleId,
    void Function(int currentChunk, int totalChunks)? onProgress,
  }) async {
    LoggerService.info('[ConnectionManager] requestFile chamado');
    LoggerService.info('[ConnectionManager] filePath: $filePath');
    LoggerService.info('[ConnectionManager] outputPath: $outputPath');
    LoggerService.info('[ConnectionManager] scheduleId: $scheduleId');

    if (!isConnected) {
      LoggerService.error('[ConnectionManager] Não conectado!');
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    LoggerService.info('[ConnectionManager] Conectado ✓');

    final requestId = _nextRequestId++;
    LoggerService.info('[ConnectionManager] RequestID: $requestId');

    final completer = Completer<rd.Result<void>>();

    // Resume Logic: Check for .part file
    final partFilePath = '$outputPath.part';
    final partFile = File(partFilePath);
    var startChunk = 0;
    var transferChunkSize = SocketConfig.chunkSize;
    IOSink? fileSink;

    try {
      final partExists = await partFile.exists();
      final resumeMetadata = await _resumeMetadataStore.read(outputPath);

      if (partExists) {
        if (resumeMetadata == null) {
          LoggerService.warning(
            '[ConnectionManager] Arquivo parcial descartado: '
            'metadata de resume ausente.',
          );
          await partFile.delete();
          await _resumeMetadataStore.delete(outputPath);
        } else if (!_canResumeWithMetadata(
          metadata: resumeMetadata,
          filePath: filePath,
          scheduleId: scheduleId,
        )) {
          LoggerService.warning(
            '[ConnectionManager] Arquivo parcial descartado: '
            'metadata de resume incompatível.',
          );
          await partFile.delete();
          await _resumeMetadataStore.delete(outputPath);
        } else if (resumeMetadata.chunkSize <= 0) {
          LoggerService.warning(
            '[ConnectionManager] Arquivo parcial descartado: '
            'chunkSize inválido no metadata de resume.',
          );
          await partFile.delete();
          await _resumeMetadataStore.delete(outputPath);
        } else {
          transferChunkSize = resumeMetadata.chunkSize;

          final partSize = await partFile.length();
          if (partSize > 0) {
            startChunk = (partSize / transferChunkSize).floor();
            final validSize = startChunk * transferChunkSize;

            LoggerService.info(
              '[ConnectionManager] Arquivo parcial encontrado. '
              'Resume do chunk $startChunk '
              '($validSize bytes, chunkSize=$transferChunkSize)',
            );

            if (partSize != validSize) {
              LoggerService.info(
                '[ConnectionManager] Truncando arquivo parcial '
                'de $partSize para $validSize bytes',
              );
              final raf = await partFile.open(mode: FileMode.append);
              await raf.truncate(validSize);
              await raf.close();
            }
          }
        }
      } else {
        await _resumeMetadataStore.delete(outputPath);
      }

      fileSink ??= partFile.openWrite(mode: FileMode.append);

      _activeTransfers[requestId] = _FileTransferState(
        completer: completer,
        outputPath: outputPath,
        partFilePath: partFilePath,
        sourceFilePath: filePath,
        scheduleId: scheduleId,
        transferChunkSize: transferChunkSize,
        fileSink: fileSink,
        onProgress: onProgress,
      );

      LoggerService.info(
        '[ConnectionManager] Enviando requisição de transferência (startChunk: $startChunk)...',
      );
      await send(
        createFileTransferStartRequestMessage(
          requestId: requestId,
          filePath: filePath,
          scheduleId: scheduleId,
          startChunk: startChunk,
        ),
      );
      LoggerService.info(
        '[ConnectionManager] Requisição enviada, aguardando resposta...',
      );

      final result = await completer.future.timeout(
        SocketConfig.fileTransferTimeout,
      );
      LoggerService.info('[ConnectionManager] Transferência completada!');
      return result;
    } on TimeoutException {
      await _cleanupTransfer(requestId);
      LoggerService.error('[ConnectionManager] Timeout na transferência!');
      return rd.Failure(TimeoutException('requestFile timeout'));
    } on Object catch (e) {
      await _cleanupTransfer(requestId);
      LoggerService.error('[ConnectionManager] Erro na transferência: $e');
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  Future<void> _cleanupTransfer(int requestId) async {
    final state = _activeTransfers.remove(requestId);
    if (state != null) {
      try {
        // Fechar o sink de forma assíncrona para garantir liberação do lock
        await state.fileSink.close();
      } on Object catch (e) {
        LoggerService.warning(
          '[ConnectionManager] Erro ao fechar fileSink durante cleanup: $e',
        );
      }

      try {
        final partExists = await File(state.partFilePath).exists();
        if (!partExists) {
          await _resumeMetadataStore.delete(state.outputPath);
        }
      } on Object catch (e) {
        LoggerService.warning(
          '[ConnectionManager] Erro ao limpar metadata de resume: $e',
        );
      }
    }
  }

  Future<rd.Result<String>> executeSchedule(
    String scheduleId, {
    BackupProgressCallback? onProgress,
  }) async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<rd.Result<String>>();

    if (onProgress != null) {
      _activeBackups[requestId] = _BackupProgressState(
        completer: completer,
        onProgress: onProgress,
      );
    }

    try {
      await send(
        createExecuteScheduleMessage(
          requestId: requestId,
          scheduleId: scheduleId,
        ),
      );

      if (onProgress == null) {
        final result = await completer.future.timeout(
          SocketConfig.backupExecutionTimeout,
        );
        _activeBackups.remove(requestId);
        return result;
      }

      final result = await completer.future.timeout(
        SocketConfig.backupExecutionTimeout,
      );
      _activeBackups.remove(requestId);
      return result;
    } on TimeoutException {
      _activeBackups.remove(requestId);
      return rd.Failure(
        TimeoutException(
          'Tempo esgotado ao aguardar conclusão do backup '
          '(limite: ${SocketConfig.backupExecutionTimeout.inMinutes} minutos)',
        ),
      );
    } on Object catch (e) {
      _activeBackups.remove(requestId);
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  /// Solicita capabilities, **cacheia** o resultado em
  /// [serverCapabilities] e retorna o snapshot.
  ///
  /// Em caso de falha (servidor `v1` legado que nao implementa o
  /// endpoint, timeout, erro de rede), o cache e populado com
  /// [ServerCapabilities.legacyDefault] e a falha original e logada,
  /// mas a chamada **retorna sucesso** com o snapshot legacy. Isso
  /// garante que providers nunca encontrem `serverCapabilities == null`
  /// apos chamarem este metodo, simplificando o gate de feature do
  /// lado deles (M4.1 - degradacao graceful).
  ///
  /// Convencao: chamar logo apos [connect] bem-sucedido. Pode ser
  /// chamado novamente para forcar refresh (ex.: apos hot-reload do
  /// servidor em dev).
  Future<rd.Result<ServerCapabilities>> refreshServerCapabilities() async {
    final result = await getServerCapabilities();
    final caps = result.fold(
      (s) => s,
      (failure) {
        LoggerService.info(
          '[ConnectionManager] getServerCapabilities falhou '
          '(servidor v1 legado ou erro): $failure. '
          'Usando ServerCapabilities.legacyDefault como fallback.',
        );
        return ServerCapabilities.legacyDefault;
      },
    );
    _cachedServerCapabilities = caps;
    return rd.Success(caps);
  }

  /// Solicita as capabilities atuais do servidor (M1.3 / M4.1) sem
  /// alterar o cache. Use [refreshServerCapabilities] em vez disso
  /// para padronizar o gate de feature em providers — esta variante
  /// e util quando o consumidor quer tratar o erro explicitamente
  /// (ex.: tela de diagnostico).
  ///
  /// Cliente deve usar o resultado como **gate de feature**: ler
  /// `capabilities.supportsRunId` (etc.) antes de habilitar code paths
  /// novos. Em servidor `v1` que ainda nao implementou
  /// `capabilitiesRequest`, a chamada retorna `Failure` (timeout ou
  /// erro generico) e o cliente deve usar
  /// [ServerCapabilities.legacyDefault] como fallback.
  Future<rd.Result<ServerCapabilities>> getServerCapabilities() async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    try {
      await send(createCapabilitiesRequestMessage(requestId: requestId));
      final message = await completer.future.timeout(
        SocketConfig.scheduleRequestTimeout,
      );
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (!isCapabilitiesResponseMessage(message)) {
        return rd.Failure(
          Exception(
            'Resposta inesperada para capabilities: ${message.header.type.name}',
          ),
        );
      }
      return rd.Success(readCapabilitiesFromResponse(message));
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(TimeoutException('getServerCapabilities timeout'));
    } on Object catch (e) {
      _pendingRequests.remove(requestId);
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  /// Solicita saude do servidor (M1.10 / PR-1).
  ///
  /// Retorna snapshot tipado [ServerHealth] com status agregado e
  /// checks individuais. Cliente deve usar para:
  /// - exibir status no dashboard;
  /// - bloquear disparo de backup quando `isUnhealthy`;
  /// - alertar operador quando `degraded`;
  /// - calcular drift de relogio.
  ///
  /// Em servidor `v1` legado que nao implementa o endpoint, a chamada
  /// retorna `Failure` (timeout). Cliente pode usar isso como sinal
  /// de "servidor antigo, fluxo legado".
  Future<rd.Result<ServerHealth>> getServerHealth() async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    try {
      await send(createHealthRequestMessage(requestId: requestId));
      final message = await completer.future.timeout(
        SocketConfig.scheduleRequestTimeout,
      );
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (!isHealthResponseMessage(message)) {
        return rd.Failure(
          Exception(
            'Resposta inesperada para health: ${message.header.type.name}',
          ),
        );
      }
      return rd.Success(readHealthFromResponse(message));
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(TimeoutException('getServerHealth timeout'));
    } on Object catch (e) {
      _pendingRequests.remove(requestId);
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  /// Solicita a sessao corrente do cliente do ponto de vista do
  /// servidor (M1.10 / PR-1).
  ///
  /// Retorna `ServerSession` com `clientId` (atribuido pelo servidor),
  /// `serverId` (declarado no auth), `isAuthenticated`, peer address
  /// e timestamps. Util para confirmar identidade, correlacionar com
  /// logs de suporte e detectar mudanca de identidade apos reconexao.
  Future<rd.Result<ServerSession>> getServerSession() async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    try {
      await send(createSessionRequestMessage(requestId: requestId));
      final message = await completer.future.timeout(
        SocketConfig.scheduleRequestTimeout,
      );
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (!isSessionResponseMessage(message)) {
        return rd.Failure(
          Exception(
            'Resposta inesperada para session: ${message.header.type.name}',
          ),
        );
      }
      return rd.Success(readSessionFromResponse(message));
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(TimeoutException('getServerSession timeout'));
    } on Object catch (e) {
      _pendingRequests.remove(requestId);
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  /// Solicita preflight de prerequisitos para execucao remota (F1.8).
  ///
  /// Servidor executa todos os checks injetados (compactacao, pasta
  /// temp, espaco em disco, etc.) e retorna status agregado. Cliente
  /// deve chamar antes de disparar backup remoto e bloquear quando
  /// `result.isBlocked == true`.
  Future<rd.Result<PreflightResult>> validateServerBackupPrerequisites() async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    try {
      await send(createPreflightRequestMessage(requestId: requestId));
      final message = await completer.future.timeout(
        SocketConfig.scheduleRequestTimeout,
      );
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (!isPreflightResponseMessage(message)) {
        return rd.Failure(
          Exception(
            'Resposta inesperada para preflight: ${message.header.type.name}',
          ),
        );
      }
      return rd.Success(readPreflightFromResponse(message));
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(
        TimeoutException('validateServerBackupPrerequisites timeout'),
      );
    } on Object catch (e) {
      _pendingRequests.remove(requestId);
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  /// Consulta status de uma execucao remota por `runId` (PR-2 base).
  ///
  /// Cliente passa o `runId` recebido em `backupProgress`/`Complete`/
  /// `Failed` (M2.3) e recebe snapshot tipado [ExecutionStatusResult].
  /// Util para reidratar UI apos reconexao ou polling alternativo.
  ///
  /// Em servidor `v1` legado que nao implementa o endpoint, a chamada
  /// retorna `Failure` (timeout). Cliente pode usar `state == notFound`
  /// como sinal de "execucao ja terminou" (registry limpou o contexto).
  Future<rd.Result<ExecutionStatusResult>> getExecutionStatus(
    String runId,
  ) async {
    if (runId.isEmpty) {
      return rd.Failure(Exception('runId must not be empty'));
    }
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    try {
      await send(
        createExecutionStatusRequestMessage(
          requestId: requestId,
          runId: runId,
        ),
      );
      final message = await completer.future.timeout(
        SocketConfig.scheduleRequestTimeout,
      );
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (!isExecutionStatusResponseMessage(message)) {
        return rd.Failure(
          Exception(
            'Resposta inesperada para executionStatus: '
            '${message.header.type.name}',
          ),
        );
      }
      return rd.Success(readExecutionStatusFromResponse(message));
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(TimeoutException('getExecutionStatus timeout'));
    } on Object catch (e) {
      _pendingRequests.remove(requestId);
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  /// Lista a fila atual de execucoes aguardando slot livre (PR-3b).
  ///
  /// Hoje (PR-1) o servidor retorna lista vazia — mutex global de 1
  /// backup ainda rejeita disparo concorrente em vez de enfileirar.
  /// Quando PR-3b habilitar fila persistida, o mesmo endpoint retornara
  /// itens reais sem mudanca no contrato (forward-compat ja garantida
  /// pelo `ExecutionQueueResult`).
  Future<rd.Result<ExecutionQueueResult>> getExecutionQueue() async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    try {
      await send(createExecutionQueueRequestMessage(requestId: requestId));
      final message = await completer.future.timeout(
        SocketConfig.scheduleRequestTimeout,
      );
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (!isExecutionQueueResponseMessage(message)) {
        return rd.Failure(
          Exception(
            'Resposta inesperada para executionQueue: '
            '${message.header.type.name}',
          ),
        );
      }
      return rd.Success(readExecutionQueueFromResponse(message));
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(TimeoutException('getExecutionQueue timeout'));
    } on Object catch (e) {
      _pendingRequests.remove(requestId);
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  /// Solicita ao servidor que sonde a conexao com um banco de dados
  /// (PR-2). Permite testar uma config persistida (`databaseConfigId`)
  /// ou uma config ad-hoc (`config`) sem precisar persistir antes.
  ///
  /// O resultado [TestDatabaseConnectionResult] traz `connected`,
  /// `latencyMs`, `error`/`errorCode` (quando falha de sondagem) e
  /// `details` (informacoes do servidor: versao do banco, charset etc.).
  ///
  /// **Importante**: o `Result.success` aqui significa "sondagem foi
  /// processada pelo servidor sem erro de comunicacao". Se a CONEXAO
  /// com o banco falhou, o cliente recebe `Success(connected=false)`,
  /// nao `Failure`. `Failure` so retorna em erros de transporte
  /// (socket nao conectado, timeout do servidor, resposta malformada).
  Future<rd.Result<TestDatabaseConnectionResult>> testRemoteDatabaseConnection({
    required RemoteDatabaseType databaseType,
    String? databaseConfigId,
    Map<String, dynamic>? config,
    Duration? timeout,
  }) async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    if (databaseConfigId == null && config == null) {
      return rd.Failure(
        Exception('testRemoteDatabaseConnection: informe id OU config'),
      );
    }
    if (databaseConfigId != null && config != null) {
      return rd.Failure(
        Exception('testRemoteDatabaseConnection: informe APENAS um (XOR)'),
      );
    }

    final requestId = _nextRequestId++;
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    try {
      await send(
        createTestDatabaseConnectionRequest(
          databaseType: databaseType,
          databaseConfigId: databaseConfigId,
          config: config,
          timeoutMs: timeout?.inMilliseconds,
          requestId: requestId,
        ),
      );
      // Timeout do CLIENTE = timeout do servidor + folga, com piso. Sem
      // isso o cliente expirava antes do servidor responder em casos
      // de banco lento/inalcancavel.
      final clientTimeout = timeout != null
          ? (timeout + const Duration(seconds: 5))
          : SocketConfig.scheduleRequestTimeout;
      final message = await completer.future.timeout(clientTimeout);
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (message.header.type !=
          MessageType.testDatabaseConnectionResponse) {
        return rd.Failure(
          Exception(
            'Resposta inesperada para testDatabaseConnection: '
            '${message.header.type.name}',
          ),
        );
      }
      return rd.Success(readTestDatabaseConnectionResponse(message));
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(
        TimeoutException('testRemoteDatabaseConnection timeout'),
      );
    } on Object catch (e) {
      _pendingRequests.remove(requestId);
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  /// `startBackup` nao-bloqueante (M2.2/PR-2). Cliente recebe IMEDIATAMENTE
  /// `runId` + `state`, sem aguardar a conclusao do backup. Eventos
  /// `backupProgress/Complete/Failed` chegam separados via stream com
  /// o mesmo `runId`.
  ///
  /// `idempotencyKey` opcional protege contra retransmissao por
  /// reconexao — mesma chave dentro do TTL retorna a mesma resposta
  /// (sem disparar backup duplicado).
  Future<rd.Result<StartBackupResult>> startRemoteBackup({
    required String scheduleId,
    String? idempotencyKey,
  }) async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    try {
      await send(
        createStartBackupRequest(
          scheduleId: scheduleId,
          idempotencyKey: idempotencyKey,
          requestId: requestId,
        ),
      );
      final message = await completer.future.timeout(
        SocketConfig.scheduleRequestTimeout,
      );
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (message.header.type != MessageType.startBackupResponse) {
        return rd.Failure(
          Exception(
            'Resposta inesperada para startBackup: '
            '${message.header.type.name}',
          ),
        );
      }
      return rd.Success(readStartBackupResponse(message));
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(TimeoutException('startRemoteBackup timeout'));
    } on Object catch (e) {
      _pendingRequests.remove(requestId);
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  /// `cancelBackup` (PR-2). Cliente envia `runId` (preferido) OU
  /// `scheduleId` (compat). Cancelamento e best-effort no servidor;
  /// estado final ainda chega via `backupFailed`/`Complete` event.
  Future<rd.Result<CancelBackupResult>> cancelRemoteBackup({
    String? runId,
    String? scheduleId,
    String? idempotencyKey,
  }) async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final hasRun = runId != null && runId.isNotEmpty;
    final hasSch = scheduleId != null && scheduleId.isNotEmpty;
    if (hasRun == hasSch) {
      return rd.Failure(
        Exception('cancelRemoteBackup: informe APENAS um (runId XOR scheduleId)'),
      );
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    try {
      await send(
        createCancelBackupRequest(
          runId: runId,
          scheduleId: scheduleId,
          idempotencyKey: idempotencyKey,
          requestId: requestId,
        ),
      );
      final message = await completer.future.timeout(
        SocketConfig.scheduleRequestTimeout,
      );
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (message.header.type != MessageType.cancelBackupResponse) {
        return rd.Failure(
          Exception(
            'Resposta inesperada para cancelBackup: '
            '${message.header.type.name}',
          ),
        );
      }
      return rd.Success(readCancelBackupResponse(message));
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(TimeoutException('cancelRemoteBackup timeout'));
    } on Object catch (e) {
      _pendingRequests.remove(requestId);
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  /// CRUD remoto de schedule (PR-2). Helper unificado que envia uma
  /// mensagem mutavel (`create`/`delete`/`pause`/`resume`) e aguarda
  /// `scheduleMutationResponse`.
  Future<rd.Result<ScheduleMutationResult>> _runScheduleMutation(
    Message Function(int requestId) build, {
    required String operationName,
  }) async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    try {
      await send(build(requestId));
      final message = await completer.future.timeout(
        SocketConfig.scheduleRequestTimeout,
      );
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (!isScheduleMutationResponseMessage(message)) {
        return rd.Failure(
          Exception(
            'Resposta inesperada para $operationName: '
            '${message.header.type.name}',
          ),
        );
      }
      return rd.Success(readScheduleMutationResponse(message));
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(TimeoutException('$operationName timeout'));
    } on Object catch (e) {
      _pendingRequests.remove(requestId);
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  Future<rd.Result<ScheduleMutationResult>> createRemoteSchedule({
    required Schedule schedule,
    String? idempotencyKey,
  }) {
    return _runScheduleMutation(
      (requestId) => createCreateScheduleMessage(
        requestId: requestId,
        schedule: schedule,
        idempotencyKey: idempotencyKey,
      ),
      operationName: 'createSchedule',
    );
  }

  Future<rd.Result<ScheduleMutationResult>> deleteRemoteSchedule({
    required String scheduleId,
    String? idempotencyKey,
  }) {
    return _runScheduleMutation(
      (requestId) => createDeleteScheduleMessage(
        requestId: requestId,
        scheduleId: scheduleId,
        idempotencyKey: idempotencyKey,
      ),
      operationName: 'deleteSchedule',
    );
  }

  Future<rd.Result<ScheduleMutationResult>> pauseRemoteSchedule({
    required String scheduleId,
    String? idempotencyKey,
  }) {
    return _runScheduleMutation(
      (requestId) => createPauseScheduleMessage(
        requestId: requestId,
        scheduleId: scheduleId,
        idempotencyKey: idempotencyKey,
      ),
      operationName: 'pauseSchedule',
    );
  }

  Future<rd.Result<ScheduleMutationResult>> resumeRemoteSchedule({
    required String scheduleId,
    String? idempotencyKey,
  }) {
    return _runScheduleMutation(
      (requestId) => createResumeScheduleMessage(
        requestId: requestId,
        scheduleId: scheduleId,
        idempotencyKey: idempotencyKey,
      ),
      operationName: 'resumeSchedule',
    );
  }

  Future<rd.Result<Map<String, dynamic>>> getServerMetrics() async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    try {
      await send(createMetricsRequestMessage(requestId: requestId));
      final message = await completer.future.timeout(
        SocketConfig.scheduleRequestTimeout,
      );
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (message.header.type != MessageType.metricsResponse) {
        return rd.Failure(
          Exception(
            'Resposta inesperada: ${message.header.type.name}',
          ),
        );
      }
      return rd.Success(getMetricsFromPayload(message));
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(TimeoutException('getServerMetrics timeout'));
    } on Object catch (e) {
      _pendingRequests.remove(requestId);
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  Future<rd.Result<void>> cancelSchedule(String scheduleId) async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    try {
      await send(
        createCancelScheduleMessage(
          requestId: requestId,
          scheduleId: scheduleId,
        ),
      );
      final message = await completer.future.timeout(
        SocketConfig.scheduleRequestTimeout,
      );
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (message.header.type != MessageType.scheduleCancelled) {
        return rd.Failure(
          Exception(
            'Resposta inesperada: ${message.header.type.name}',
          ),
        );
      }
      return const rd.Success(rd.unit);
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(TimeoutException('cancelSchedule timeout'));
    } on Object catch (e) {
      _pendingRequests.remove(requestId);
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  Future<void> send(Message message) async {
    final client = _client;
    if (client == null || !client.isConnected) {
      throw StateError('ConnectionManager not connected');
    }
    await client.send(message);
  }

  Future<List<ServerConnectionsTableData>> getSavedConnections() async {
    if (_serverConnectionDao == null) {
      return <ServerConnectionsTableData>[];
    }
    return _serverConnectionDao.getAll();
  }

  Future<void> connectToSavedConnection(
    String connectionId, {
    bool enableAutoReconnect = false,
  }) async {
    final dao = _serverConnectionDao;
    if (dao == null) {
      throw StateError(
        'ConnectionManager has no ServerConnectionDao; cannot connect to saved connection',
      );
    }
    final connection = await dao.getById(connectionId);
    if (connection == null) {
      throw StateError('Saved connection not found: $connectionId');
    }
    await connect(
      host: connection.host,
      port: connection.port,
      serverId: connection.serverId,
      password: connection.password,
      enableAutoReconnect: enableAutoReconnect,
    );
  }
}

class _FileTransferState {
  _FileTransferState({
    required this.completer,
    required this.outputPath,
    required this.partFilePath,
    required this.sourceFilePath,
    required this.scheduleId,
    required this.transferChunkSize,
    required this.fileSink,
    this.onProgress,
  });

  final Completer<rd.Result<void>> completer;
  final String outputPath;
  final String partFilePath;
  final String sourceFilePath;
  final String? scheduleId;
  final IOSink fileSink;
  final void Function(int currentChunk, int totalChunks)? onProgress;
  String fileName = '';
  int totalChunks = 0;
  int expectedSize = 0;
  String? expectedHash;
  bool isCompressed = false;
  int transferChunkSize;
}

class _BackupProgressState {
  _BackupProgressState({
    required this.completer,
    this.onProgress,
  });

  final Completer<rd.Result<String>> completer;
  final BackupProgressCallback? onProgress;

  /// `runId` da execucao remota associada, capturado da primeira mensagem
  /// do servidor que o popular (`backupProgress`/`Complete`/`Failed`). Em
  /// servidores `v1` permanece `null` (comportamento legado preservado).
  /// Pre-requisito para uso futuro em re-sync por reconexao (PR-3c) e
  /// `getExecutionStatus(runId)` (PR-2).
  String? runId;
}
