import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/errors/google_drive_failure.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_file_listing.dart';
import 'package:googleapis/drive/v3.dart' as drive;

Future<drive.File?> findCompletedGoogleDriveUpload(
  drive.DriveApi api, {
  required String parentId,
  required String fileName,
  required int fileSize,
  required String md5,
}) async {
  String escape(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
  final files = await listAllGoogleDriveFiles(
    api,
    query:
        "name = '${escape(fileName)}' and '${escape(parentId)}' in parents "
        "and trashed = false and mimeType != 'application/vnd.google-apps.folder'",
    fields: 'id,name,size,md5Checksum',
  );
  for (final file in files) {
    if (file.id == null ||
        file.id!.isEmpty ||
        file.size == null ||
        int.tryParse(file.size!) == null ||
        file.md5Checksum == null ||
        !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(file.md5Checksum!)) {
      throw const GoogleDriveFailure(
        message:
            'Não foi possível validar o arquivo existente no Google Drive.',
        code: FailureCodes.integrityValidationInconclusive,
      );
    }
    if (file.name == fileName &&
        int.parse(file.size!) == fileSize &&
        file.md5Checksum!.toLowerCase() == md5.toLowerCase()) {
      return file;
    }
  }
  return null;
}
