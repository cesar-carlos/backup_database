import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/presentation/boot/app_cleanup.dart';
import 'package:backup_database/presentation/managers/window_manager_service.dart';

/// Both UI exit commands share one bounded shutdown, including repeated clicks.
class AppExitCoordinator {
  AppExitCoordinator({
    required this.cleanup,
    required this.exitProcess,
    required this.onStart,
    this.timeout = const Duration(seconds: 30),
  });

  static final instance = AppExitCoordinator(
    cleanup: AppCleanup.cleanup,
    exitProcess: exit,
    onStart: WindowManagerService().beginShutdown,
  );

  final Future<void> Function() cleanup;
  final void Function(int) exitProcess;
  final void Function() onStart;
  final Duration timeout;
  Future<void>? _shutdown;
  bool get isExiting => _shutdown != null;

  Future<void> requestExit() {
    final pending = _shutdown;
    if (pending != null) return pending;
    // Publish before callbacks: onStart/cleanup can synchronously request exit.
    final completion = Completer<void>();
    _shutdown = completion.future;
    completion.complete(_performExit());
    return completion.future;
  }

  Future<void> _performExit() async {
    try {
      onStart();
      await cleanup().timeout(timeout);
    } on Object catch (error, stackTrace) {
      LoggerService.error(
        'Falha ou timeout ao encerrar aplicativo',
        error,
        stackTrace,
      );
    } finally {
      // Even a failed cleanup must not leave a hidden process holding the lock.
      exitProcess(0);
    }
  }
}
