import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class FileHashUtils {
  FileHashUtils._();

  static const int _dropboxHashBlockSizeBytes = 4 * 1024 * 1024;

  static Future<String> computeSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  static Future<String> computeMd5(File file) async {
    final digest = await md5.bind(file.openRead()).first;
    return digest.toString();
  }

  static Future<String> computeSha256FromStream(
    Stream<List<int>> stream,
  ) async {
    final digest = await sha256.bind(stream).first;
    return digest.toString();
  }

  static Future<String> computeDropboxContentHash(File file) async {
    final raf = await file.open();
    final blockDigests = BytesBuilder(copy: false);

    try {
      while (true) {
        final chunk = await raf.read(_dropboxHashBlockSizeBytes);
        if (chunk.isEmpty) {
          break;
        }
        final blockDigest = sha256.convert(chunk);
        blockDigests.add(blockDigest.bytes);
      }
    } finally {
      await raf.close();
    }

    final finalDigest = sha256.convert(blockDigests.takeBytes());
    return finalDigest.toString();
  }
}
