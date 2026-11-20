import 'package:backup_database/core/errors/google_drive_failure.dart';
import 'package:googleapis/drive/v3.dart' as drive;

Future<List<drive.File>> listAllGoogleDriveFiles(
  drive.DriveApi api, {
  required String query,
  required String fields,
  String? orderBy,
}) async {
  final files = <drive.File>[];
  final seenTokens = <String>{};
  String? pageToken;
  do {
    final page = await api.files.list(
      q: query,
      spaces: 'drive',
      orderBy: orderBy,
      pageToken: pageToken,
      $fields: 'nextPageToken,incompleteSearch,files($fields)',
    );
    if (page.incompleteSearch ?? false) {
      throw const GoogleDriveFailure(
        message: 'Google Drive retornou uma busca incompleta. Operação interrompida.',
      );
    }
    files.addAll(page.files ?? const <drive.File>[]);
    pageToken = page.nextPageToken;
    if (pageToken != null && !seenTokens.add(pageToken)) {
      throw const GoogleDriveFailure(
        message:
            'Google Drive repetiu o token de paginação. Operação interrompida.',
      );
    }
  } while (pageToken != null);
  return files;
}
