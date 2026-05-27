import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_nextcloud_destination_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:backup_database/domain/use_cases/destinations/destination_use_case.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SendToNextcloud {
  SendToNextcloud(this._service);
  final INextcloudDestinationService _service;

  Future<rd.Result<NextcloudUploadResult>> call({
    required String sourceFilePath,
    required NextcloudDestinationConfig config,
    String? customFileName,
    UploadProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    final checks = <(String, String)>[
      (sourceFilePath, 'Caminho do arquivo'),
      (config.serverUrl, 'URL do Nextcloud'),
      (config.username, 'Usuário do Nextcloud'),
      (config.appPassword, 'App Password do Nextcloud'),
      (config.folderName, 'Nome da pasta do Nextcloud'),
    ];
    for (final (value, label) in checks) {
      final check = DestinationUseCase.notEmptyOrFailure(value, label);
      if (check.isError()) return rd.Failure(check.exceptionOrNull()!);
    }

    return _service.upload(
      sourceFilePath: sourceFilePath,
      config: config,
      customFileName: customFileName,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }
}
