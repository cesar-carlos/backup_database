import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_channel.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_peer_guard.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_v1_codec.dart';
import 'package:backup_database/infrastructure/external/system/ipc/named_pipe_ffi.dart';
import 'package:backup_database/infrastructure/external/system/mutex_security_descriptor.dart';

const Duration _connectionStopPoll = Duration(milliseconds: 20);
const Duration _pipeAcceptRetryDelay = Duration(milliseconds: 50);
const Duration _connectionShutdownGrace = Duration(seconds: 2);
const Duration _serverStopGrace = Duration(seconds: 5);

class WindowsNamedPipeTransport implements IIpcTransport {
  WindowsNamedPipeTransport({
    String? pipeName,
    this._peerGuard,
    String? expectedImagePath,
  }) : _pipeName = pipeName ?? SingleInstanceConfig.ipcPipeName,
       _expectedImagePath =
           expectedImagePath ??
           (Platform.isWindows ? Platform.resolvedExecutable : '');

  final String _pipeName;
  final IpcPeerGuard? _peerGuard;
  final String _expectedImagePath;

  Isolate? _serverIsolate;
  SendPort? _serverCmd;
  ReceivePort? _fromServer;
  Completer<void>? _serverStopped;
  bool _serverExitObserved = false;
  bool _running = false;
  Future<void> Function(IIpcChannel channel)? _onConnection;

  @override
  bool get isServerRunning => _running;

  @override
  Future<bool> startServer({
    required Future<void> Function(IIpcChannel channel) onConnection,
  }) async {
    if (!Platform.isWindows) {
      return false;
    }
    if (_running) {
      return true;
    }

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
          if (!listening.isCompleted) {
            listening.complete(false);
          }
        } else if (type == 'stopped') {
          _serverExitObserved = true;
          final pending = _serverStopped;
          if (pending != null && !pending.isCompleted) {
            pending.complete();
          }
        } else if (type == 'conn') {
          unawaited(_acceptConnection(message));
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
      await stopServer();
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
  Future<void> stopServer() async {
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
    if (!Platform.isWindows) {
      return null;
    }
    try {
      final handle = await Isolate.run(
        () => NamedPipeFfi.connectClient(
          pipeName: _pipeName,
          timeout: timeout,
        ),
      ).timeout(timeout);
      if (handle == null || !NamedPipeFfi.handleIsValid(handle)) {
        return null;
      }
      final serverPid = NamedPipeFfi.serverPid(handle);
      final guard =
          _peerGuard ??
          NamedPipeFfi.platformGuard(expectedImagePath: _expectedImagePath);
      if (serverPid == null || !guard.allowPeer(serverPid)) {
        LoggerService.warning(
          'event=ipc_peer_rejected side=client pid=$serverPid',
        );
        NamedPipeFfi.disconnectAndClose(handle);
        return null;
      }
      return _NamedPipeClientChannel(handle: handle);
    } on Object catch (e) {
      LoggerService.debug('ipc_named_pipe_connect_failed error=$e');
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

class _NamedPipeClientChannel implements IIpcChannel {
  _NamedPipeClientChannel({required this.handle});

  final int handle;
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
      return;
    }
    final framed = IpcV1Codec.stripLine(line);
    await Isolate.run(() => NamedPipeFfi.writeLine(handle, framed));
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
  });

  final SendPort toMain;
  final String pipeName;
  final String expectedImagePath;
  final int maxInstances;
  final int maxLineBytes;
}

final class _NamedPipeConnSpawn {
  const _NamedPipeConnSpawn({
    required this.handle,
    required this.toMain,
    required this.toServer,
    required this.donePort,
    required this.expectedImagePath,
    required this.maxLineBytes,
  });

  final int handle;
  final SendPort toMain;
  final SendPort toServer;
  final SendPort donePort;
  final String expectedImagePath;
  final int maxLineBytes;
}

final class _LivePipeConnection {
  _LivePipeConnection({required this.isolate, required this.handle});

  final Isolate isolate;
  final int handle;
  SendPort? commandPort;
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

  final doneSlots = ReceivePort();
  final finishedHandles = <int>{};
  var active = 0;
  doneSlots.listen((Object? message) {
    if (message is int) {
      finishedHandles.add(message);
    }
    if (active > 0) {
      active--;
    }
  });

  final childEvents = ReceivePort();
  final connections = <_LivePipeConnection>[];
  final pendingCommandPorts = <int, SendPort>{};
  childEvents.listen((Object? message) {
    _rememberConnectionCommand(
      message: message,
      connections: connections,
      pendingCommandPorts: pendingCommandPorts,
    );
  });

  final security = Win32SecurityDescriptor.fromSddl(
    Win32SecurityDescriptor.namedPipeEveryoneGenericAllSddl,
  );
  try {
    var firstInstance = true;
    var announced = false;
    while (running) {
      await Future<void>.delayed(Duration.zero);
      while (active >= args.maxInstances && running) {
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
          args.toMain.send(const {'t': 'failed'});
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
      final connected = NamedPipeFfi.connectServerPipe(handle);
      await Future<void>.delayed(Duration.zero);
      if (!running) {
        NamedPipeFfi.disconnectAndClose(handle);
        break;
      }
      if (!connected) {
        NamedPipeFfi.disconnectAndClose(handle);
        continue;
      }
      active++;
      try {
        final child = await Isolate.spawn(
          _runNamedPipeConnectionIsolate,
          _NamedPipeConnSpawn(
            handle: handle,
            toMain: args.toMain,
            toServer: childEvents.sendPort,
            donePort: doneSlots.sendPort,
            expectedImagePath: args.expectedImagePath,
            maxLineBytes: args.maxLineBytes,
          ),
        );
        connections.add(
          _LivePipeConnection(isolate: child, handle: handle)
            ..commandPort = pendingCommandPorts.remove(handle),
        );
      } on Object {
        NamedPipeFfi.disconnectAndClose(handle);
        active--;
      }
    }
  } finally {
    await _shutdownConnectionIsolates(
      connections: connections,
      finishedHandles: finishedHandles,
      activeCount: () => active,
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
  required List<_LivePipeConnection> connections,
  required Map<int, SendPort> pendingCommandPorts,
}) {
  if (message is! Map) {
    return;
  }
  final handle = message['h'];
  final port = message['p'];
  if (handle is! int || port is! SendPort) {
    return;
  }
  for (final connection in connections) {
    if (connection.handle != handle) {
      continue;
    }
    connection.commandPort = port;
    return;
  }
  pendingCommandPorts[handle] = port;
}

Future<void> _shutdownConnectionIsolates({
  required List<_LivePipeConnection> connections,
  required Set<int> finishedHandles,
  required int Function() activeCount,
}) async {
  if (connections.isEmpty) {
    return;
  }
  final deadline = DateTime.now().add(_connectionShutdownGrace);
  while (_hasUnregisteredCommand(connections, finishedHandles) &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(_connectionStopPoll);
  }
  for (final connection in connections) {
    if (finishedHandles.contains(connection.handle)) {
      continue;
    }
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
  while (activeCount() > 0 && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(_connectionStopPoll);
  }
  for (final connection in connections) {
    if (finishedHandles.contains(connection.handle)) {
      continue;
    }
    connection.isolate.kill(priority: Isolate.immediate);
    NamedPipeFfi.disconnectAndClose(connection.handle);
  }
}

bool _hasUnregisteredCommand(
  List<_LivePipeConnection> connections,
  Set<int> finishedHandles,
) {
  for (final connection in connections) {
    if (finishedHandles.contains(connection.handle)) {
      continue;
    }
    if (connection.commandPort == null) {
      return true;
    }
  }
  return false;
}

Future<void> _runNamedPipeConnectionIsolate(_NamedPipeConnSpawn args) async {
  final handle = args.handle;
  final cmd = ReceivePort();
  try {
    args.toServer.send({'h': handle, 'p': cmd.sendPort});
    final clientPid = NamedPipeFfi.clientPid(handle);
    final guard = IpcPeerGuard(
      expectedImagePath: () => args.expectedImagePath,
      resolveImagePath: NamedPipeFfi.imagePathForPid,
      expandLongPath: NamedPipeFfi.longPathName,
    );
    if (clientPid == null || !guard.allowPeer(clientPid)) {
      return;
    }
    final line = NamedPipeFfi.readLine(
      handle,
      maxBytes: args.maxLineBytes,
    );
    if (line == null) {
      return;
    }
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
    NamedPipeFfi.disconnectAndClose(handle);
    try {
      args.donePort.send(handle);
    } on Object {
      // Server isolate already finished waiting for this connection.
    }
  }
}
