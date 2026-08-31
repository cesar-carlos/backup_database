import 'dart:async';
import 'dart:convert';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_channel.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_v1_codec.dart';

class InMemoryIpcTransport implements IIpcTransport {
  InMemoryIpcTransport({
    this.maxInstances,
    this.failStart = false,
    this.throwOnStop = false,
  });

  final int? maxInstances;
  final bool failStart;
  final bool throwOnStop;

  Future<void> Function(IIpcChannel channel)? _onConnection;
  bool _running = false;
  int _active = 0;

  @override
  bool get isServerRunning => _running;

  @override
  Future<bool> startServer({
    required Future<void> Function(IIpcChannel channel) onConnection,
  }) async {
    if (_running) {
      return true;
    }
    if (failStart) {
      return false;
    }
    _onConnection = onConnection;
    _running = true;
    return true;
  }

  @override
  Future<void> stopServer() async {
    _running = false;
    _onConnection = null;
    if (throwOnStop) {
      throw StateError('close failed');
    }
  }

  @override
  Future<IIpcChannel?> connect({required Duration timeout}) async {
    final handler = _onConnection;
    if (!_running || handler == null) {
      return null;
    }
    final limit = maxInstances ?? SingleInstanceConfig.ipcMaxPipeInstances;
    if (_active >= limit) {
      return null;
    }

    final pair = _InMemoryChannelPair.open();
    _active++;
    unawaited(() async {
      try {
        await handler(pair.server);
      } finally {
        await pair.server.close();
        _active--;
      }
    }());
    return pair.client;
  }
}

class _InMemoryChannelPair {
  _InMemoryChannelPair._({required this.client, required this.server});

  factory _InMemoryChannelPair.open() {
    final toServer = _LineMailbox();
    final toClient = _LineMailbox();
    return _InMemoryChannelPair._(
      client: _InMemoryChannel(incoming: toClient, outgoing: toServer),
      server: _InMemoryChannel(incoming: toServer, outgoing: toClient),
    );
  }

  final IIpcChannel client;
  final IIpcChannel server;
}

class _LineMailbox {
  final List<String> _queue = <String>[];
  Completer<String>? _waiter;
  bool closed = false;

  void add(String line) {
    if (closed) {
      return;
    }
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(line);
      _waiter = null;
      return;
    }
    _queue.add(line);
  }

  Future<String?> take({required Duration timeout}) async {
    if (closed) {
      return null;
    }
    if (_queue.isNotEmpty) {
      return _queue.removeAt(0);
    }
    final waiter = Completer<String>();
    _waiter = waiter;
    try {
      return await waiter.future.timeout(timeout);
    } on TimeoutException {
      if (identical(_waiter, waiter)) {
        _waiter = null;
      }
      return null;
    }
  }

  void close() {
    closed = true;
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(StateError('channel closed'));
    }
    _waiter = null;
    _queue.clear();
  }
}

class _InMemoryChannel implements IIpcChannel {
  _InMemoryChannel({
    required this.incoming,
    required this.outgoing,
  });

  final _LineMailbox incoming;
  final _LineMailbox outgoing;
  bool _closed = false;

  @override
  Future<String?> readLine({required Duration timeout}) async {
    if (_closed) {
      return null;
    }
    try {
      final line = await incoming.take(timeout: timeout);
      if (line == null) {
        return null;
      }
      final bytes = utf8.encode(line);
      if (IpcV1Codec.exceedsMaxLineBytes(bytes)) {
        await close();
        return null;
      }
      return IpcV1Codec.stripLine(line);
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
    final bytes = utf8.encode(framed);
    if (IpcV1Codec.exceedsMaxLineBytes(bytes)) {
      await close();
      return;
    }
    outgoing.add(framed);
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    incoming.close();
    outgoing.close();
  }
}
