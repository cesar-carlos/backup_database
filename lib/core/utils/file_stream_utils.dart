import 'dart:io';

Stream<List<int>> chunkedFileStream(File file, int chunkSize) async* {
  final raf = await file.open();
  try {
    final fileSize = await raf.length();
    var offset = 0;
    while (offset < fileSize) {
      final toRead = offset + chunkSize <= fileSize
          ? chunkSize
          : fileSize - offset;
      final buffer = List<int>.filled(toRead, 0);
      final read = await raf.readInto(buffer, 0, toRead);
      if (read > 0) {
        yield buffer.sublist(0, read);
        offset += read;
      } else {
        break;
      }
    }
  } finally {
    await raf.close();
  }
}
