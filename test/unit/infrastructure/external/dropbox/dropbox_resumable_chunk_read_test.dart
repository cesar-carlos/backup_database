import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Valida a **primitiva** que substituiu o bug do
/// `DropboxDestinationService._uploadResumable` (chunked upload via
/// `upload_session`).
///
/// **O bug anterior** (`fileStream.take(N).toList()` em loop sobre
/// `File.openRead()`):
/// - `take(N)` em `Stream<List<int>>` conta **eventos**, não bytes;
/// - `File.openRead()` é single-subscription, então o stream fecha após
///   o primeiro `take().toList()`;
/// - A 2ª iteração do loop crashava com
///   "Bad state: Stream has already been listened to".
///
/// **A correção** (esta primitiva): abrir um `RandomAccessFile` uma vez
/// e ler chunks consecutivos via `readInto(buffer, 0, bytesToRead)`,
/// avançando o ponteiro implicitamente.
///
/// Este teste reproduz o cenário de 256 chunks de 4 MB (1 GB total) em
/// escala reduzida e prova que o conteúdo bate byte-a-byte.
void main() {
  group('RandomAccessFile chunked read (Dropbox resumable primitive)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dropbox_chunk_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<File> writeDeterministicFile(int sizeBytes) async {
      final file = File(p.join(tempDir.path, 'fixture.bin'));
      final raf = await file.open(mode: FileMode.write);
      try {
        // Padrão determinístico: byte N = (N % 251)
        const writeBufSize = 64 * 1024;
        var written = 0;
        final writeBuf = Uint8List(writeBufSize);
        while (written < sizeBytes) {
          final remaining = sizeBytes - written;
          final n = remaining < writeBufSize ? remaining : writeBufSize;
          for (var i = 0; i < n; i++) {
            writeBuf[i] = (written + i) % 251;
          }
          await raf.writeFrom(writeBuf, 0, n);
          written += n;
        }
      } finally {
        await raf.close();
      }
      return file;
    }

    test(
      'reads file completely in fixed-size chunks (replays the resumable '
      'upload loop pattern)',
      () async {
        const fileSize = 1 * 1024 * 1024; // 1 MB para teste rápido
        const chunkSize = 4 * 1024; // chunks de 4 KB → ~256 iterações

        final file = await writeDeterministicFile(fileSize);
        final raf = await file.open();
        try {
          var offset = 0;
          var iterations = 0;
          final assembled = BytesBuilder(copy: false);

          while (offset < fileSize) {
            final remaining = fileSize - offset;
            final bytesToRead = remaining < chunkSize ? remaining : chunkSize;
            final buffer = Uint8List(bytesToRead);

            var totalRead = 0;
            while (totalRead < bytesToRead) {
              final n = await raf.readInto(buffer, totalRead, bytesToRead);
              expect(
                n,
                greaterThan(0),
                reason: 'readInto deve sempre retornar > 0 enquanto há bytes',
              );
              totalRead += n;
            }
            assembled.add(buffer);
            offset += bytesToRead;
            iterations++;
          }

          expect(offset, fileSize);
          expect(iterations, fileSize ~/ chunkSize);
          final result = assembled.takeBytes();
          expect(result.length, fileSize);
          for (var i = 0; i < fileSize; i++) {
            if (result[i] != i % 251) {
              fail('Byte $i incorreto: got ${result[i]}, want ${i % 251}');
            }
          }
        } finally {
          await raf.close();
        }
      },
    );

    test(
      'handles partial final chunk (file size not multiple of chunk size)',
      () async {
        const fileSize = 100 * 1024 + 123; // 100 KB + 123 bytes
        const chunkSize = 32 * 1024;

        final file = await writeDeterministicFile(fileSize);
        final raf = await file.open();
        try {
          var offset = 0;
          final chunkSizes = <int>[];

          while (offset < fileSize) {
            final remaining = fileSize - offset;
            final bytesToRead = remaining < chunkSize ? remaining : chunkSize;
            final buffer = Uint8List(bytesToRead);
            var totalRead = 0;
            while (totalRead < bytesToRead) {
              totalRead += await raf.readInto(buffer, totalRead, bytesToRead);
            }
            chunkSizes.add(bytesToRead);
            offset += bytesToRead;
          }

          expect(offset, fileSize);
          // Todos exceto o último são chunkSize completos.
          for (var i = 0; i < chunkSizes.length - 1; i++) {
            expect(chunkSizes[i], chunkSize);
          }
          // Último é o resto (123 bytes do "100KB+123").
          expect(chunkSizes.last, fileSize % chunkSize);
        } finally {
          await raf.close();
        }
      },
    );

    test(
      'single-chunk file (size < chunkSize) is read in one iteration',
      () async {
        const fileSize = 500;
        const chunkSize = 4 * 1024;

        final file = await writeDeterministicFile(fileSize);
        final raf = await file.open();
        try {
          const remaining = fileSize - 0;
          const bytesToRead = remaining < chunkSize ? remaining : chunkSize;
          expect(bytesToRead, fileSize);
          final buffer = Uint8List(bytesToRead);
          var totalRead = 0;
          while (totalRead < bytesToRead) {
            totalRead += await raf.readInto(buffer, totalRead, bytesToRead);
          }
          expect(totalRead, fileSize);
        } finally {
          await raf.close();
        }
      },
    );
  });
}
