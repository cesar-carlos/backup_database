import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_channel.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_peer_guard.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_v1_codec.dart';
import 'package:backup_database/infrastructure/external/system/ipc/named_pipe_ffi.dart';
import 'package:backup_database/infrastructure/external/system/ipc/pending_pipe_connection.dart';
import 'package:backup_database/infrastructure/external/system/ipc/pipe_connection_registry.dart';
import 'package:backup_database/infrastructure/external/system/ipc/process_query_access.dart';
import 'package:backup_database/infrastructure/external/system/mutex_security_descriptor.dart';

const Duration _connectionStopPoll = Duration(milliseconds: 20);
const Duration _pipeAcceptRetryDelay = Duration(milliseconds: 50);
const Duration _connectionShutdownGrace = Duration(seconds: 2);
const Duration _serverStopGrace = Duration(seconds: 5);

// Only transferable values may enter the worker. Capturing a transport also
// captures its ReceivePorts/Futures when it is already serving connections.
Future<int?> _openNativePipe(String pipeName, Duration timeout) => Isolate.run(
  () => NamedPipeFfi.connectClient(pipeName: pipeName, timeout: timeout),
);

Future<bool> _acceptNativePipe(int handle) =>
    Isolate.run(() => NamedPipeFfi.connectServerPipe(handle));

class WindowsNamedPipeTransport
    implements IIpcTransport, IpcConnectionDiagnostics {
  WindowsNamedPipeTransport({
    String? pipeName,
    this._peerGuard,
    String? expectedImagePath,
    String? Function()? prepareProcessQueryAccess,
    Duration? handshakeTimeout,
  }) : _pipeName = pipeName ?? SingleInstanceConfig.ipcPipeName,
       _prepareProcessQueryAccess =
           prepareProcessQueryAccess ?? ProcessQueryAccess.prepare,
       _handshakeTimeout =
           handshakeTimeout ?? SingleInstanceConfig.ipcConnectTimeout,
       _expectedImagePath =
           expectedImagePath ??
           (Platform.isWindows ? Platform.resolvedExecutable : '');

  final String _pipeName;
  final IpcPeerGuard? _peerGuard;
  final String _expectedImagePath;
  final Duration _handshakeTimeout;
  final String? Function() _prepareProcessQueryAccess;
  bool _queryAccessReady = false;

  bool _preparePeerVerification() {
    if (_queryAccessReady) return true;
    try {
      final failure = _prepareProcessQueryAccess();
      if (failure == null) {
        _queryAccessReady = true;
        return true;
      }
      lastConnectionFailure = 'process_query_access_failed $failure';
    } on Object catch (e) {
      lastConnectionFailure = 'process_query_access_failed error=$e';
    }
    LoggerService.warning(
      'event=ipc_security_setup_failed $lastConnectionFailure',
    );
    return false;
  }

  @override
  String? lastConnectionFailure;

  Isolate? _serverIsolate;
  SendPort? _serverCmd;
  ReceivePort? _fromServer;
  Completer<void>? _serverStopped;
  bool _serverExitObserved = false;
  bool _running = false;
  Future<void> Function(IIpcChannel channel)? _onConnection;
  Future<void> _lifecycle = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _lifecycle.then((_) => action());
    _lifecycle = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  @override
  bool get isServerRunning => _running;

  @override
  Future<bool> startServer({
    required Future<void> Function(IIpcChannel channel) onConnection,
  }) => _serialize(() => _startServer(onConnection: onConnection));

  Future<bool> _startServer({
    required Future<void> Function(IIpcChannel channel) onConnection,
  }) async {
    if (!Platform.isWindows) {
      return false;
    }
    if (_running) {
      return true;
    }
    if (!_preparePeerVerification()) return false;

    _onConnection = onConnection;
    _serverExitObserved = false;
    _serverStopped = null;
    final fromServer = ReceivePort();
    _fromServer = fromServer;
    final listening = Completer<bool>();

    fromServer.listen((Object? message) {
      if (message is Map) {
        final type = message['t'];
        if (type == 'cmd' && message['p'] is SendPort) {
          _serverCmd = message['p'] as SendPort;
        } else if (type == 'listening') {
          if (!listening.isCompleted) {
            listening.complete(true);
          }
        } else if (type == 'failed') {
          LoggerService.warning(
            'event=ipc_server_start_failed pipe=$_pipeName error=${message['error']}',
          );
          if (!listening.isCompleted) {
            listening.complete(false);
          }
        } else if (type == 'stopped') {
          _running = false;
          _serverExitObserved = true;
          final pending = _serverStopped;
          if (pending != null && !pending.isCompleted) {
            pending.complete();
          }
        } else if (type == 'conn') {
          unawaited(_acceptConnection(message));
        } else if (type == 'diagnostic') {
          LoggerService.warning(
            'event=ipc_server_connection_failed pipe=$_pipeName reason=${message['reason']} pid=${message['pid']}',
          );
        }
      }
    });

    try {
      _serverIsolate = await Isolate.spawn(
        _runNamedPipeServerIsolate,
        _NamedPipeServerSpawn(
          toMain: fromServer.sendPort,
          pipeName: _pipeName,
          expectedImagePath: _expectedImagePath,
          maxInstances: SingleInstanceConfig.ipcMaxPipeInstances,
          maxLineBytes: SingleInstanceConfig.ipcMaxLineBytes,
          handshakeTimeout: _handshakeTimeout,
        ),
      );
    } on Object catch (e, s) {
      LoggerService.error('ipc_named_pipe_spawn_failed', e, s);
      fromServer.close();
      _fromServer = null;
      return false;
    }

    final started = await listening.future.timeout(
      SingleInstanceConfig.ipcConnectTimeout,
      onTimeout: () => false,
    );
    if (!started) {
      await _stopServer();
      return false;
    }
    _running = true;
    LoggerService.infoWithContext(
      'event=ipc_server_started transport=named_pipe '
      'pipe=$_pipeName',
    );
    return true;
  }

  Future<void> _acceptConnection(Map<dynamic, dynamic> message) async {
    final line = message['line'];
    final cmd = message['p'];
    if (line is! String || cmd is! SendPort) {
      return;
    }
    final handler = _onConnection;
    if (handler == null) {
      try {
        cmd.send(const {'t': 'close'});
      } on Object {
        // Connection isolate already closed its port during shutdown.
      }
      return;
    }
    final channel = _NamedPipeServerChannel(
      initialLine: IpcV1Codec.stripLine(line),
      commandPort: cmd,
    );
    try {
      await handler(channel);
    } finally {
      await channel.close();
    }
  }

  @override
  Future<void> stopServer() => _serialize(_stopServer);

  Future<void> _stopServer() async {
    final isolate = _serverIsolate;
    final commandPort = _serverCmd;
    final fromServer = _fromServer;
    _running = false;
    _onConnection = null;
    _serverIsolate = null;
    _serverCmd = null;

    if (isolate == null && commandPort == null && fromServer == null) {
      return;
    }

    final stopped = Completer<void>();
    _serverStopped = stopped;
    if (_serverExitObserved) {
      stopped.complete();
    } else {
      try {
        commandPort?.send('stop');
        if (Platform.isWindows) {
          NamedPipeFfi.wakeServer(_pipeName);
        }
      } on Object catch (e, s) {
        LoggerService.warning('ipc_named_pipe_stop_signal_failed', e, s);
      }
      if (isolate != null) {
        try {
          await stopped.future.timeout(_serverStopGrace);
        } on TimeoutException {
          isolate.kill(priority: Isolate.immediate);
        }
      }
    }

    _serverStopped = null;
    fromServer?.close();
    if (identical(_fromServer, fromServer)) {
      _fromServer = null;
    }
  }

  @override
  Future<IIpcChannel?> connect({required Duration timeout}) async {
    lastConnectionFailure = null;
    if (!Platform.isWindows) {
      return null;
    }
    if (!_preparePeerVerification()) return null;
    try {
      final handle = await awaitPipeConnection(
        connection: _openNativePipe(_pipeName, timeout),
        timeout: timeout,
        close: NamedPipeFfi.disconnectAndClose,
      );
      if (handle == null || !NamedPipeFfi.handleIsValid(handle)) {
        lastConnectionFailure = 'pipe_unavailable pipe=$_pipeName';
        return null;
      }
      var transferred = false;
      try {
        final serverPid = NamedPipeFfi.serverPid(handle);
        final guard =
            _peerGuard ??
            NamedPipeFfi.platformGuard(expectedImagePath: _expectedImagePath);
        final rejection = guard.rejectionReason(serverPid ?? 0);
        if (rejection != null) {
          lastConnectionFailure =
              'peer_rejected reason=$rejection pid=$serverPid pipe=$_pipeName'
              '${_peerGuard == null && NamedPipeFfi.lastImageQueryFailure != null ? ' native=${NamedPipeFfi.lastImageQueryFailure}' : ''}';
          LoggerService.warning(
            'event=ipc_peer_rejected side=client $lastConnectionFailure',
          );
          return null;
        }
        transferred = true;
        return WindowsPipeClientChannel(handle: handle);
      } finally {
        if (!transferred) NamedPipeFfi.disconnectAndClose(handle);
      }
    } on Object catch (e) {
      lastConnectionFailure = 'pipe=$_pipeName error=$e';
      LoggerService.warning(
        'event=ipc_named_pipe_connect_failed $lastConnectionFailure',
      );
      return null;
    }
  }
}

class _NamedPipeServerChannel implements IIpcChannel {
  _NamedPipeServerChannel({
    required this.initialLine,
    required this.commandPort,
  });

  final String initialLine;
  final SendPort commandPort;
  bool _consumed = false;
  bool _closed = false;

  @override
  Future<String?> readLine({required Duration timeout}) async {
    if (_closed) {
      return null;
    }
    if (_consumed) {
      return null;
    }
    _consumed = true;
    return initialLine;
  }

  @override
  Future<void> writeLine(String line) async {
    if (_closed) {
      return;
    }
    try {
      commandPort.send({'t': 'write', 'v': IpcV1Codec.stripLine(line)});
    } on Object {
      _closed = true;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    try {
      commandPort.send(const {'t': 'close'});
    } on Object {
      // Connection isolate already exited and closed its port.
    }
  }
}

class WindowsPipeClientChannel implements IIpcChannel {
  WindowsPipeClientChannel({required this.handle, this.writeNative});

  final int handle;
  final Future<bool> Function(int handle, String line)? writeNative;
  bool _closed = false;

  @override
  Future<String?> readLine({required Duration timeout}) async {
    if (_closed) {
      return null;
    }
    try {
      final line = await Isolate.run(
        () => NamedPipeFfi.readLine(
          handle,
          maxBytes: SingleInstanceConfig.ipcMaxLineBytes,
        ),
      ).timeout(timeout);
      if (line == null) {
        return null;
      }
      return IpcV1Codec.stripLine(line);
    } on TimeoutException {
      return null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> writeLine(String line) async {
    if (_closed) {
      throw StateError('IPC channel closed before write');
    }
    final framed = IpcV1Codec.stripLine(line);
    final pipeHandle = handle;
    final writer = writeNative;
    final written = writer != null
        ? await writer(pipeHandle, framed)
        : await Isolate.run(() => NamedPipeFfi.writeLine(pipeHandle, framed));
    if (!written) {
      // A failed/partial write is uncertain: never classify it as an unopened
      // channel, which would discard the idempotency key and allow a new run.
      throw StateError('IPC request write failed or incomplete');
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    NamedPipeFfi.disconnectAndClose(handle);
  }
}

final class _NamedPipeServerSpawn {
  const _NamedPipeServerSpawn({
    required this.toMain,
    required this.pipeName,
    required this.expectedImagePath,
    required this.maxInstances,
    required this.maxLineBytes,
    required this.handshakeTimeout,
  });

  final SendPort toMain;
  final String pipeName;
  final String expectedImagePath;
  final int maxInstances;
  final int maxLineBytes;
  final Duration handshakeTimeout;
}

final class _NamedPipeConnSpawn {
  const _NamedPipeConnSpawn({
    required this.connectionId,
    required this.handle,
    required this.toMain,
    required this.toServer,
    required this.donePort,
    required this.expectedImagePath,
    required this.maxLineBytes,
  });

  final int handle;
  final int connectionId;
  final SendPort toMain;
  final SendPort toServer;
  final SendPort donePort;
  final String expectedImagePath;
  final int maxLineBytes;
}

final class _LivePipeConnection {
  _LivePipeConnection({required this.handle});

  Isolate? isolate;
  final int handle;
  SendPort? commandPort;
  Timer? handshakeTimer;
}

Future<void> _runNamedPipeServerIsolate(_NamedPipeServerSpawn args) {
  return _namedPipeServerIsolateMainAsync(args);
}

Future<void> _namedPipeServerIsolateMainAsync(
  _NamedPipeServerSpawn args,
) async {
  final cmd = ReceivePort();
  args.toMain.send({'t': 'cmd', 'p': cmd.sendPort});
  var running = true;
  cmd.listen((Object? message) {
    if (message == 'stop') {
      running = false;
    }
  });

  final connections = PipeConnectionRegistry<_LivePipeConnection>();
  final doneSlots = ReceivePort();
  doneSlots.listen((Object? message) {
    if (message is int) {
      final connection = connections.finish(message);
      if (connection != null) {
        connection.handshakeTimer?.cancel();
        NamedPipeFfi.disconnectAndClose(connection.handle);
      }
    }
  });

  final childEvents = ReceivePort();
  childEvents.listen((Object? message) {
    _rememberConnectionCommand(
      message: message,
      connections: connections,
    );
  });

  final security = Win32SecurityDescriptor.fromSddl(
    Win32SecurityDescriptor.namedPipeEveryoneGenericAllSddl,
  );
  try {
    if (security == null) {
      args.toMain.send(const {
        't': 'failed',
        'error': 'pipe_security_descriptor_unavailable',
      });
      return;
    }
    var firstInstance = true;
    var announced = false;
    while (running) {
      await Future<void>.delayed(Duration.zero);
      while (connections.length >= args.maxInstances && running) {
        await Future<void>.delayed(_connectionStopPoll);
      }
      if (!running) {
        break;
      }
      final handle = NamedPipeFfi.createServerPipe(
        pipeName: args.pipeName,
        firstInstance: firstInstance,
        security: security,
      );
      if (!NamedPipeFfi.handleIsValid(handle)) {
        if (firstInstance && !announced) {
          args.toMain.send({'t': 'failed', 'error': NamedPipeFfi.lastError});
          break;
        }
        await Future<void>.delayed(_pipeAcceptRetryDelay);
        continue;
      }
      firstInstance = false;
      if (!announced) {
        announced = true;
        args.toMain.send(const {'t': 'listening'});
      }
      final connected = await _acceptNativePipe(handle);
      await Future<void>.delayed(Duration.zero);
      if (!running) {
        NamedPipeFfi.disconnectAndClose(handle);
        break;
      }
      if (!connected) {
        NamedPipeFfi.disconnectAndClose(handle);
        continue;
      }
      final connection = _LivePipeConnection(handle: handle);
      final connectionId = connections.reserve(connection);
      connection.handshakeTimer = Timer(args.handshakeTimeout, () {
        if (connections[connectionId] == null) return;
        args.toMain.send(const {
          't': 'diagnostic',
          'reason': 'request_read_timeout',
        });
        // Parent retains ownership until the worker reports completion.
        NamedPipeFfi.disconnect(handle);
      });
      try {
        final child = await Isolate.spawn(
          _runNamedPipeConnectionIsolate,
          _NamedPipeConnSpawn(
            connectionId: connectionId,
            handle: handle,
            toMain: args.toMain,
            toServer: childEvents.sendPort,
            donePort: doneSlots.sendPort,
            expectedImagePath: args.expectedImagePath,
            maxLineBytes: args.maxLineBytes,
          ),
        );
        connection.isolate = child;
      } on Object {
        connection.handshakeTimer?.cancel();
        if (connections.finish(connectionId) != null) {
          NamedPipeFfi.disconnectAndClose(handle);
        }
      }
    }
  } finally {
    await _shutdownConnectionIsolates(
      connections: connections,
    );
    security?.dispose();
    cmd.close();
    doneSlots.close();
    childEvents.close();
    try {
      args.toMain.send(const {'t': 'stopped'});
    } on Object {
      // Main already closed its receive port after the stop grace.
    }
  }
}

void _rememberConnectionCommand({
  required Object? message,
  required PipeConnectionRegistry<_LivePipeConnection> connections,
}) {
  if (message is! Map) {
    return;
  }
  final id = message['id'];
  if (id is int && message['t'] == 'request_read') {
    connections[id]?.handshakeTimer?.cancel();
    return;
  }
  final port = message['p'];
  if (id is! int || port is! SendPort) {
    return;
  }
  final connection = connections[id];
  if (connection != null) {
    connection.commandPort = port;
  }
}

Future<void> _shutdownConnectionIsolates({
  required PipeConnectionRegistry<_LivePipeConnection> connections,
}) async {
  if (connections.length == 0) {
    return;
  }
  final deadline = DateTime.now().add(_connectionShutdownGrace);
  while (connections.snapshot.any((c) => c.commandPort == null) &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(_connectionStopPoll);
  }
  for (final connection in connections.snapshot) {
    connection.handshakeTimer?.cancel();
    NamedPipeFfi.disconnect(connection.handle);
    final port = connection.commandPort;
    if (port == null) {
      continue;
    }
    try {
      port.send(const {'t': 'close'});
    } on Object {
      // Connection isolate already closed its command port.
    }
  }
  while (connections.length > 0 && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(_connectionStopPoll);
  }
  for (final connection in connections.snapshot) {
    connection.isolate?.kill(priority: Isolate.immediate);
    NamedPipeFfi.disconnectAndClose(connection.handle);
  }
}

Future<void> _runNamedPipeConnectionIsolate(_NamedPipeConnSpawn args) async {
  final handle = args.handle;
  final cmd = ReceivePort();
  try {
    args.toServer.send({'id': args.connectionId, 'p': cmd.sendPort});
    final clientPid = NamedPipeFfi.clientPid(handle);
    final guard = IpcPeerGuard(
      expectedImagePath: () => args.expectedImagePath,
      resolveImagePath: NamedPipeFfi.imagePathForPid,
      expandLongPath: NamedPipeFfi.longPathName,
    );
    final rejection = guard.rejectionReason(clientPid ?? 0);
    if (rejection != null) {
      args.toMain.send({
        't': 'diagnostic',
        'reason': '$rejection native=${NamedPipeFfi.lastImageQueryFailure}',
        'pid': clientPid,
      });
      return;
    }
    final line = NamedPipeFfi.readLine(
      handle,
      maxBytes: args.maxLineBytes,
    );
    if (line == null) {
      return;
    }
    args.toServer.send({'t': 'request_read', 'id': args.connectionId});
    final closed = Completer<void>();
    cmd.listen((Object? message) {
      if (message is Map && message['t'] == 'write') {
        final value = message['v'];
        if (value is String) {
          NamedPipeFfi.writeLine(handle, value);
        }
      }
      if (message is Map && message['t'] == 'close') {
        if (!closed.isCompleted) {
          closed.complete();
        }
      }
    });
    args.toMain.send({
      't': 'conn',
      'line': line,
      'p': cmd.sendPort,
    });
    await closed.future.timeout(
      SingleInstanceConfig.scheduledDelegationTimeout +
          const Duration(seconds: 30),
      onTimeout: () {},
    );
  } finally {
    cmd.close();
    // The parent owns the handle and closes it after processing completion.
    // This prevents a recycled handle from being closed during shutdown.
    try {
      args.donePort.send(args.connectionId);
    } on Object {
      // Server isolate already finished waiting for this connection.
    }
  }
}
