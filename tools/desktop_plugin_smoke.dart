// Run with: flutter run -d windows -t tools/desktop_plugin_smoke.dart
// This entrypoint never starts the backup scheduler or opens the app database.
import 'dart:async';
import 'dart:io';

import 'package:backup_database/presentation/managers/tray_manager_service.dart';
import 'package:backup_database/presentation/managers/window_manager_service.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('Desktop plugin smoke test')),
    ),
  );
  final window = WindowManagerService();
  final tray = TrayManagerService();
  var result = 0;
  try {
    await Future<void>(() async {
      await window.initialize(title: 'Backup Database - plugin smoke test');
      if (!await window.isVisible()) throw StateError('Window did not show');
      await tray.initialize();
      await window.setCloseToTray(true);
      await window.close();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (await window.isVisible()) throw StateError('Close did not hide');
      await window.restore();
      if (!await window.isVisible()) throw StateError('Restore failed');
      await window.setMinimizeToTray(true);
      await window.minimize();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (await window.isVisible()) throw StateError('Minimize did not hide');
      await window.restore();
      if (!await window.isVisible()) throw StateError('Second restore failed');
      await tray.dispose();
      await tray.initialize();
      stdout.writeln('DESKTOP_SMOKE_OK');
    }).timeout(const Duration(seconds: 30));
  } on Object catch (error, stack) {
    stderr.writeln('DESKTOP_SMOKE_FAILED: $error\n$stack');
    result = 1;
  } finally {
    await tray.dispose();
    window.dispose();
  }
  exit(result);
}
