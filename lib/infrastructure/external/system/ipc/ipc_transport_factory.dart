import 'dart:io';

import 'package:backup_database/infrastructure/external/system/ipc/in_memory_ipc_transport.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_channel.dart';
import 'package:backup_database/infrastructure/external/system/ipc/windows_named_pipe_transport.dart';

class IpcTransportFactory {
  IpcTransportFactory._();

  static IIpcTransport create() {
    if (Platform.isWindows) {
      return WindowsNamedPipeTransport();
    }
    return InMemoryIpcTransport();
  }
}
