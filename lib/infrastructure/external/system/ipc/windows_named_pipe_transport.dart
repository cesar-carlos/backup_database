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
          expectedBasename: IpcPeerGuard.basename(_expectedImagePath),
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
      cmd.send(const {'t': 'close'});
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
    _running = false;
    _onConnection = null;
    try {
      _serverCmd?.send('stop');
      if (Platform.isWindows) {
        NamedPipeFfi.wakeServer(_pipeName);
      }
    } on Object catch (e, s) {
      LoggerService.warning('ipc_named_pipe_stop_signal_failed', e, s);
    }
    _serverIsolate?.kill(priority: Isolate.immediate);
    _serverIsolate = null;
    _serverCmd = null;
    _fromServer?.close();
    _fromServer = null;
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
    commandPort.send({'t': 'write', 'v': IpcV1Codec.stripLine(line)});
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    commandPort.send(const {'t': 'close'});
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
    required this.expectedBasename,
    required this.maxInstances,
    required this.maxLineBytes,
  });

  final SendPort toMain;
  final String pipeName;
  final String expectedBasename;
  final int maxInstances;
  final int maxLineBytes;
}

final class _NamedPipeConnSpawn {
  const _NamedPipeConnSpawn({
    required this.handle,
    required this.toMain,
    required this.donePort,
    required this.expectedBasename,
    required this.maxLineBytes,
  });

  final int handle;
  final SendPort toMain;
  final SendPort donePort;
  final String expectedBasename;
  final int maxLineBytes;
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
  var active = 0;
  doneSlots.listen((Object? _) {
    if (active > 0) {
      active--;
    }
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
        await Future<void>.delayed(const Duration(milliseconds: 20));
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
        await Future<void>.delayed(const Duration(milliseconds: 50));
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
        await Isolate.spawn(
          _runNamedPipeConnectionIsolate,
          _NamedPipeConnSpawn(
            handle: handle,
            toMain: args.toMain,
            donePort: doneSlots.sendPort,
            expectedBasename: args.expectedBasename,
            maxLineBytes: args.maxLineBytes,
          ),
        );
      } on Object {
        NamedPipeFfi.disconnectAndClose(handle);
        active--;
      }
    }
  } finally {
    security?.dispose();
    cmd.close();
    doneSlots.close();
  }
}

Future<void> _runNamedPipeConnectionIsolate(_NamedPipeConnSpawn args) async {
  final handle = args.handle;
  final cmd = ReceivePort();
  try {
    final clientPid = NamedPipeFfi.clientPid(handle);
    final guard = IpcPeerGuard(
      expectedImagePath: () => args.expectedBasename,
      resolveImagePath: NamedPipeFfi.imagePathForPid,
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
    args.donePort.send('done');
  }
}
