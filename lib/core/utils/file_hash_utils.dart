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
    final blockDigests = BytesBuilder(copy: false);
    final block = Uint8List(_dropboxHashBlockSizeBytes);
    var filled = 0;
    await for (final chunk in file.openRead()) {
      var offset = 0;
      while (offset < chunk.length) {
        final available = _dropboxHashBlockSizeBytes - filled;
        final remaining = chunk.length - offset;
        final count = remaining < available ? remaining : available;
        block.setRange(filled, filled + count, chunk, offset);
        filled += count;
        offset += count;
        if (filled == _dropboxHashBlockSizeBytes) {
          blockDigests.add(sha256.convert(block).bytes);
          filled = 0;
        }
      }
    }
    if (filled > 0) {
      blockDigests.add(
        sha256.convert(Uint8List.sublistView(block, 0, filled)).bytes,
      );
    }

    final finalDigest = sha256.convert(blockDigests.takeBytes());
    return finalDigest.toString();
  }
}
