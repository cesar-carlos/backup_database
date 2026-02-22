import 'dart:typed_data';

import 'package:backup_database/infrastructure/protocol/compression.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PayloadCompression compression;

  setUp(() {
    compression = PayloadCompression();
  });

  group('PayloadCompression', () {
    test('compress then decompress returns original data', () {
      final original = Uint8List.fromList(
        List<int>.generate(2000, (i) => i % 256),
      );
      final compressed = compression.compress(original);
      final decompressed = compression.decompress(compressed);
      expect(decompressed, orderedEquals(original));
    });

    test('compressed data is smaller for repetitive content', () {
      final repetitive = Uint8List.fromList(List<int>.filled(5000, 0x41));
      final compressed = compression.compress(repetitive);
      expect(compressed.length, lessThan(repetitive.length));
    });

    test('decompress(compress(data)) preserves length', () {
      final data = Uint8List.fromList(
        [1, 2, 3, 4, 5] + List<int>.filled(1500, 10),
      );
      final roundTrip = compression.decompress(compression.compress(data));
      expect(roundTrip.length, data.length);
      expect(roundTrip, orderedEquals(data));
    });
  });

  group('PayloadCompression.shouldCompress', () {
    test('returns false for size <= 1024', () {
      expect(PayloadCompression.shouldCompress(0), isFalse);
      expect(PayloadCompression.shouldCompress(1024), isFalse);
      expect(PayloadCompression.shouldCompress(512), isFalse);
    });

    test('returns true for size > 1024', () {
      expect(PayloadCompression.shouldCompress(1025), isTrue);
      expect(PayloadCompression.shouldCompress(2048), isTrue);
    });
  });
}
