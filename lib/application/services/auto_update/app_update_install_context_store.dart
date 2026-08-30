import 'dart:convert';
import 'dart:io';

import 'package:backup_database/application/services/auto_update/app_update_types.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:path/path.dart' as p;

class AppUpdateInstallContextStore {
  AppUpdateInstallContextStore({
    required this.updatesDirectoryResolver,
  });

  final DirectoryResolver updatesDirectoryResolver;

  Future<AppUpdateInstallContext> persist({
    required AppcastRelease release,
    required String currentVersion,
    UpdateInstallContextProvider? installContextProvider,
  }) async {
    final updatesDir = await updatesDirectoryResolver();
    await updatesDir.create(recursive: true);
    await cleanupIfExpired(
      File(
        p.join(updatesDir.path, AppUpdateConstants.updateContextFileName),
      ),
    );
    final context =
        await installContextProvider?.call(release) ??
        AppUpdateInstallContext(
          origin: AppUpdateLaunchOrigin.ui,
          appMode: currentAppMode,
          currentVersion: currentVersion,
          targetVersion: release.targetVersion,
          relaunchArguments: List<String>.of(Platform.executableArguments),
          executablePath: Platform.resolvedExecutable,
          createdAt: DateTime.now(),
        );

    final file = File(
      p.join(updatesDir.path, AppUpdateConstants.updateContextFileName),
    );
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      '${encoder.convert(context.toJson())}\n',
      flush: true,
    );
    return context;
  }

  /// Remove `update_context.json` when the pipeline aborts before the
  /// installer is confirmed alive. After a confirmed spawn the installer
  /// owns the context — do not delete it.
  Future<void> removeOnEarlyFailure(
    AppUpdateStage failureStage, {
    required bool installerSpawnConfirmed,
  }) async {
    if (installerSpawnConfirmed || failureStage == AppUpdateStage.completed) {
      return;
    }
    try {
      final updatesDir = await updatesDirectoryResolver();
      final file = File(
        p.join(updatesDir.path, AppUpdateConstants.updateContextFileName),
      );
      if (await file.exists()) {
        await file.delete();
        LoggerService.info(
          'AutoUpdateService: update_context.json removido apos falha em '
          '${failureStage.token}.',
        );
      }
    } on Object catch (e, s) {
      LoggerService.warning(
        'Falha ao remover update_context.json apos erro pre-launch',
        e,
        s,
      );
    }
  }

  Future<void> cleanupIfExpired(File file) async {
    if (!await file.exists()) {
      return;
    }

    if (!await isExpired(file)) {
      return;
    }

    try {
      await file.delete();
      LoggerService.info(
        'AutoUpdateService: update_context.json expirado removido de '
        '${file.path}',
      );
    } on Object catch (e, s) {
      LoggerService.warning(
        'Falha ao remover update_context.json expirado',
        e,
        s,
      );
    }
  }

  static Future<bool> isExpired(
    File file, {
    DateTime? now,
  }) async {
    final reference = (now ?? DateTime.now()).toUtc();
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return true;
      }
      final expiresAt =
          _tryParseIsoDateTime(decoded['expiresAt']) ??
          _tryParseIsoDateTime(decoded['createdAt'])?.add(
            AppUpdateConstants.updateContextTtl,
          );
      if (expiresAt == null) {
        final modified = (await file.stat()).modified.toUtc();
        return reference.isAfter(
          modified.add(AppUpdateConstants.updateContextTtl),
        );
      }
      return reference.isAfter(expiresAt.toUtc());
    } on Object {
      return true;
    }
  }
}

DateTime? _tryParseIsoDateTime(Object? raw) {
  final value = raw?.toString().trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}
