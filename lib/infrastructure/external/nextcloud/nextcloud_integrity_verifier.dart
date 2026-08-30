import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/errors/nextcloud_failure.dart';
import 'package:backup_database/core/utils/file_hash_utils.dart';
import 'package:dio/dio.dart';
import 'package:result_dart/result_dart.dart' as rd;

class NextcloudIntegrityVerifier {
  const NextcloudIntegrityVerifier();

  static const _integrityReadBackAttempts = 2;
  static const _integrityReadBackDelay = Duration(seconds: 1);

  /// Validação de integridade do arquivo recém-enviado.
  ///
  /// **Camadas (gating por config)**:
  /// 1. Sempre: `HEAD content-length` igual ao local (`size` check).
  /// 2. `enableStrongIntegrityValidation == true`: requer hash forte.
  ///    Nextcloud não expõe SHA-256 em propriedade WebDAV padrão, então
  ///    só conseguimos via **read-back** (download de validação).
  /// 3. `enableReadBackValidation == true`: faz download e compara hash.
  ///
  /// Para arquivos de banco grandes, é razoável manter as duas flags em
  /// `false` (a checagem de tamanho já pega ~95% dos truncamentos), em
  /// troca de evitar dobrar o tráfego de rede do backup.
  Future<rd.Result<void>> validateUploadedFile({
    required Dio dio,
    required Uri uploadUrl,
    required int fileSize,
    required String localSha256,
    required bool enableStrongIntegrityValidation,
    required bool enableReadBackValidation,
  }) async {
    final headSizeResult = await _validateRemoteContentLength(
      dio: dio,
      uploadUrl: uploadUrl,
      expectedSize: fileSize,
    );
    if (headSizeResult.isError()) {
      return rd.Failure(headSizeResult.exceptionOrNull()!);
    }

    if (!enableStrongIntegrityValidation) {
      return const rd.Success(());
    }
    if (!enableReadBackValidation) {
      return const rd.Failure(
        NextcloudFailure(
          message:
              'Validação forte de integridade Nextcloud habilitada, mas '
              'read-back está desabilitado. Sem outra fonte de hash '
              'remoto, integridade não pôde ser confirmada.',
          code: FailureCodes.integrityValidationInconclusive,
        ),
      );
    }

    for (var attempt = 0; attempt < _integrityReadBackAttempts; attempt++) {
      try {
        final response = await dio.getUri(
          uploadUrl,
          options: Options(responseType: ResponseType.stream),
        );
        final body = response.data;
        if (body is! ResponseBody) {
          throw Exception('Resposta inválida no read-back Nextcloud');
        }
        final remoteSha256 = await FileHashUtils.computeSha256FromStream(
          body.stream,
        );
        if (remoteSha256.toLowerCase() == localSha256.toLowerCase()) {
          return const rd.Success(());
        }
        return rd.Failure(
          NextcloudFailure(
            message:
                'Falha de integridade no Nextcloud: hash remoto difere '
                'do arquivo local (SHA-256).',
            code: FailureCodes.integrityValidationFailed,
            originalError: Exception(
              'Nextcloud SHA-256 mismatch: '
              'local=$localSha256 remote=$remoteSha256',
            ),
          ),
        );
      } on Object catch (e) {
        if (attempt < _integrityReadBackAttempts - 1) {
          await Future.delayed(_integrityReadBackDelay);
          continue;
        }
        return rd.Failure(
          NextcloudFailure(
            message:
                'Não foi possível confirmar integridade no Nextcloud por '
                'read-back (download de validação).',
            code: FailureCodes.integrityValidationInconclusive,
            originalError: e,
          ),
        );
      }
    }

    return const rd.Failure(
      NextcloudFailure(
        message: 'Não foi possível confirmar integridade no Nextcloud.',
        code: FailureCodes.integrityValidationInconclusive,
      ),
    );
  }

  Future<rd.Result<void>> _validateRemoteContentLength({
    required Dio dio,
    required Uri uploadUrl,
    required int expectedSize,
  }) async {
    try {
      final headResponse = await dio.headUri(uploadUrl);
      final contentLengthStr = headResponse.headers.value('content-length');
      if (contentLengthStr == null || contentLengthStr.isEmpty) {
        return const rd.Failure(
          NextcloudFailure(
            message:
                'Não foi possível validar integridade no Nextcloud '
                '(content-length ausente no HEAD).',
            code: FailureCodes.integrityValidationInconclusive,
          ),
        );
      }
      final remoteSize = int.tryParse(contentLengthStr);
      if (remoteSize == null) {
        return const rd.Failure(
          NextcloudFailure(
            message:
                'Não foi possível validar integridade no Nextcloud '
                '(content-length inválido no HEAD).',
            code: FailureCodes.integrityValidationInconclusive,
          ),
        );
      }
      if (remoteSize != expectedSize) {
        return rd.Failure(
          NextcloudFailure(
            message:
                'Falha de integridade no Nextcloud: tamanho remoto '
                'diverge do arquivo local. Local: $expectedSize, '
                'Remoto: $remoteSize',
            code: FailureCodes.integrityValidationFailed,
            originalError: Exception(
              'Nextcloud content-length mismatch: '
              'local=$expectedSize remote=$remoteSize',
            ),
          ),
        );
      }
      return const rd.Success(());
    } on Object catch (e) {
      return rd.Failure(
        NextcloudFailure(
          message:
              'Não foi possível validar integridade no Nextcloud '
              '(falha na consulta HEAD).',
          code: FailureCodes.integrityValidationInconclusive,
          originalError: e,
        ),
      );
    }
  }
}
