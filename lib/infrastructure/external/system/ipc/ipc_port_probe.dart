import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_v1_codec.dart';

class IpcPortProbe {
  IpcPortProbe._();

  static int? _cachedActivePort;
  static DateTime? _cachedActivePortAt;
  static List<int>? portsOverrideForTests;

  static void resetForTests() {
    _cachedActivePort = null;
    _cachedActivePortAt = null;
    portsOverrideForTests = null;
  }

  static List<int> portsToTry() {
    final defaultPorts =
        portsOverrideForTests ??
        [
          SingleInstanceConfig.ipcBasePort,
          ...SingleInstanceConfig.ipcAlternativePorts,
        ];
    final cachedPort = _cachedActivePortIfFresh();
    if (cachedPort == null) {
      return defaultPorts;
    }

    return [cachedPort, ...defaultPorts.where((port) => port != cachedPort)];
  }

  static int? _cachedActivePortIfFresh() {
    final cachedPort = _cachedActivePort;
    final cachedAt = _cachedActivePortAt;
    if (cachedPort == null || cachedAt == null) {
      return null;
    }

    final cacheAge = DateTime.now().difference(cachedAt);
    if (cacheAge <= SingleInstanceConfig.ipcPortCacheTtl) {
      LoggerService.debug(
        'ipc_port_cache_hit port=$cachedPort '
        'age_ms=${cacheAge.inMilliseconds}',
      );
      return cachedPort;
    }

    _cachedActivePort = null;
    _cachedActivePortAt = null;
    return null;
  }

  static void markActive(int port) {
    _cachedActivePort = port;
    _cachedActivePortAt = DateTime.now();
  }

  static Future<void> closeClientResources({Socket? socket}) async {
    if (socket != null) {
      try {
        await socket.close();
      } on Object catch (_) {
        try {
          socket.destroy();
        } on Object catch (_) {}
      }
    }
  }

  static Future<bool> checkServerRunning() async {
    final ports = portsToTry();
    final firstRoundCount = ports.length > 2 ? 2 : ports.length;
    final firstRoundPorts = ports.take(firstRoundCount).toList();

    final firstRoundResult = await checkPortsWithTimeout(
      ports: firstRoundPorts,
      timeout: SingleInstanceConfig.ipcDiscoveryFastTimeout,
    );
    if (firstRoundResult) {
      return true;
    }

    final remainingPorts = ports.skip(firstRoundCount).toList();
    if (remainingPorts.isEmpty) {
      return false;
    }

    return checkPortsWithTimeout(
      ports: remainingPorts,
      timeout: SingleInstanceConfig.ipcDiscoverySlowTimeout,
    );
  }

  static Future<bool> checkPortsWithTimeout({
    required List<int> ports,
    required Duration timeout,
  }) async {
    final results = await Future.wait(
      ports.map((port) => probeServerPort(port: port, timeout: timeout)),
    );
    return results.any((bool isActive) => isActive);
  }

  static Future<bool> probeServerPort({
    required int port,
    required Duration timeout,
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: timeout,
      );

      socket.add(utf8.encode(SingleInstanceConfig.ipcPingMessage));
      await socket.flush();

      final data = await socket.first.timeout(timeout);
      final response = utf8.decode(data).trim();
      if (IpcV1Codec.isValidV1Pong(response)) {
        markActive(port);
        LoggerService.debug('ipc_probe_ok port=$port');
        return true;
      }

      LoggerService.debug('ipc_probe_invalid_pong port=$port');
      return false;
    } on Object catch (_) {
      return false;
    } finally {
      await closeClientResources(socket: socket);
    }
  }
}
