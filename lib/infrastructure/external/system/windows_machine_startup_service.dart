import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_windows_machine_startup_service.dart';
import 'package:backup_database/infrastructure/external/system/machine_startup_task_xml.dart';
import 'package:path/path.dart' as p;

class WindowsMachineStartupService implements IWindowsMachineStartupService {
  static const String _fullTaskPath = machineLogonStartupTaskPath;
  static const String _hkcuRunKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _runValueName = 'BackupDatabase';

  @override
  Future<WindowsMachineStartupOutcome> apply({
    required bool enabled,
    required bool installScheduledTask,
    required String executablePath,
    required String taskArguments,
  }) async {
    if (!Platform.isWindows) {
      return const WindowsMachineStartupOutcome(ok: true);
    }

    await _removeHkcuRun();
    await _deleteScheduledTask();

    if (!enabled) {
      return const WindowsMachineStartupOutcome(ok: true);
    }

    if (!installScheduledTask) {
      LoggerService.info(
        'Modo servidor: início automático via Windows Service; '
        'tarefa de logon não instalada.',
      );
      return const WindowsMachineStartupOutcome(ok: true);
    }

    final xml = buildMachineLogonStartupTaskXml(
      command: executablePath,
      arguments: taskArguments.trim(),
    );

    Directory? tempDir;
    try {
      tempDir = Directory.systemTemp.createTempSync('bd_machine_startup_');
      final xmlFile = File(p.join(tempDir.path, 'task.xml'));
      xmlFile.writeAsStringSync(xml, flush: true);

      final result = await Process.run(
        'schtasks',
        ['/Create', '/TN', _fullTaskPath, '/XML', xmlFile.path, '/F'],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        LoggerService.info(
          'Tarefa de início na máquina criada: $_fullTaskPath',
        );
        return const WindowsMachineStartupOutcome(ok: true);
      }

      final err = '${result.stderr}${result.stdout}'.trim();
      LoggerService.error(
        'Falha ao criar tarefa de início (schtasks exit=${result.exitCode})',
        Exception(err.isEmpty ? 'empty schtasks output' : err),
      );
      return WindowsMachineStartupOutcome(ok: false, diagnostics: err);
    } on Object catch (e, s) {
      LoggerService.error('Erro ao criar tarefa de início na máquina', e, s);
      return WindowsMachineStartupOutcome(ok: false, diagnostics: '$e');
    } finally {
      try {
        tempDir?.deleteSync(recursive: true);
      } on Object catch (_) {}
    }
  }

  Future<void> _removeHkcuRun() async {
    final result = await Process.run('reg', [
      'delete',
      _hkcuRunKey,
      '/v',
      _runValueName,
      '/f',
    ]);
    if (result.exitCode != 0 && result.exitCode != 1) {
      LoggerService.debug(
        'reg delete Run/BackupDatabase: exit=${result.exitCode} '
        'stderr=${result.stderr}',
      );
    }
  }

  Future<void> _deleteScheduledTask() async {
    final result = await Process.run(
      'schtasks',
      ['/Delete', '/TN', _fullTaskPath, '/F'],
      runInShell: true,
    );
    if (result.exitCode != 0) {
      LoggerService.debug(
        'schtasks delete $_fullTaskPath: exit=${result.exitCode}',
      );
    }
  }
}
