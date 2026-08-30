import 'dart:io';

import 'package:backup_database/application/services/auto_update/app_update_diagnostics_store.dart';
import 'package:backup_database/application/services/auto_update/app_update_install_context_store.dart';
import 'package:backup_database/application/services/auto_update/app_update_types.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

typedef AppUpdateNetworkRetry = Future<T> Function<T>({
  required String label,
  required Future<T> Function() action,
});

class AppUpdateArtifactStore {
  AppUpdateArtifactStore({
    required this.dio,
    required this.updatesDirectoryResolver,
    required this.freeDiskSpaceProbe,
    required this.runWithRetry,
    required this.installContextStore,
    required this.diagnosticsStore,
  });

  static const int minFreeSpaceFactor = 2;
  static const Duration stagedInstallerRetention = Duration(days: 7);

  final Dio dio;
  final DirectoryResolver updatesDirectoryResolver;
  final FreeDiskSpaceProbe freeDiskSpaceProbe;
  final AppUpdateNetworkRetry runWithRetry;
  final AppUpdateInstallContextStore installContextStore;
  final AppUpdateDiagnosticsStore diagnosticsStore;

  Future<File> downloadInstaller(AppcastRelease release) async {
    final updatesDir = await updatesDirectoryResolver();
    await updatesDir.create(recursive: true);
    await cleanupStagedInstallers(
      preserveInstallerName: release.installerFileName,
    );

    await ensureSufficientDiskSpace(
      updatesDir: updatesDir,
      release: release,
    );

    final targetFile = File(p.join(updatesDir.path, release.installerFileName));
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    await runWithRetry<void>(
      label: 'download do instalador',
      action: () {
        return dio.download(
          release.downloadUrl,
          targetFile.path,
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: true,
          ),
        );
      },
    );

    return targetFile;
  }

  Future<void> ensureSufficientDiskSpace({
    required Directory updatesDir,
    required AppcastRelease release,
  }) async {
    final freeBytes = await freeDiskSpaceProbe(updatesDir);
    if (freeBytes == null) {
      // Probe nao suportado nesta plataforma/instalacao; nao bloqueia.
      return;
    }
    final required = release.fileSizeBytes * minFreeSpaceFactor;
    if (freeBytes < required) {
      throw StateError(
        'Espaco insuficiente em ${updatesDir.path} para baixar '
        '${release.installerFileName}. '
        'Livre: $freeBytes B, necessario aproximado: $required B '
        '(${minFreeSpaceFactor}x o tamanho do instalador).',
      );
    }
  }

  Future<void> cleanupStaleUpdateArtifacts() async {
    final updatesDir = await updatesDirectoryResolver();
    if (!await updatesDir.exists()) {
      return;
    }

    final contextFile = File(
      p.join(updatesDir.path, AppUpdateConstants.updateContextFileName),
    );
    await installContextStore.cleanupIfExpired(contextFile);

    final diagnosticsFile = File(
      p.join(updatesDir.path, AppUpdateConstants.updateDiagnosticsFileName),
    );
    await diagnosticsStore.rotateIfNeeded(diagnosticsFile);
  }

  Future<void> cleanupStagedInstallers({
    String? preserveInstallerName,
  }) async {
    final updatesDir = await updatesDirectoryResolver();
    if (!await updatesDir.exists()) {
      return;
    }

    final now = DateTime.now();
    final installers = <File>[];
    await for (final entity in updatesDir.list()) {
      if (entity is File && p.extension(entity.path).toLowerCase() == '.exe') {
        installers.add(entity);
      }
    }

    installers.sort((a, b) {
      final aModified = a.statSync().modified;
      final bModified = b.statSync().modified;
      return bModified.compareTo(aModified);
    });

    var keptRecentCount = 0;
    final maxRecentKeep = preserveInstallerName == null ? 2 : 1;
    for (final installer in installers) {
      final name = p.basename(installer.path);
      final modified = (await installer.stat()).modified;
      final isPreservedTarget =
          preserveInstallerName != null && name == preserveInstallerName;
      final canKeepAsPrevious =
          !isPreservedTarget &&
          keptRecentCount < maxRecentKeep &&
          now.difference(modified) <= stagedInstallerRetention;

      if (isPreservedTarget) {
        continue;
      }
      if (canKeepAsPrevious) {
        keptRecentCount++;
        continue;
      }
      try {
        await installer.delete();
      } on Object catch (e, s) {
        LoggerService.warning(
          'Falha ao remover instalador antigo de staging: ${installer.path}',
          e,
          s,
        );
      }
    }
  }
}
