import 'dart:io';
import 'dart:typed_data';

const int _defaultCompressionLevel = 6;
const int _minSizeToCompress = 1024; // 1KB

class PayloadCompression {
  PayloadCompression({
    this.level = _defaultCompressionLevel,
    this.maxDecompressedBytes = defaultMaxDecompressedBytes,
  });

  final int level;

  final int maxDecompressedBytes;

  static const int minSizeToCompress = _minSizeToCompress;

  static const int defaultMaxDecompressedBytes = 64 * 1024 * 1024;

  Uint8List compress(Uint8List data) {
    final codec = ZLibCodec(level: level);
    final compressed = codec.encode(data);
    return Uint8List.fromList(compressed);
  }

  Uint8List decompress(Uint8List data) {
    final output = BytesBuilder(copy: false);
    var total = 0;
    final sink = ZLibDecoder().startChunkedConversion(
      _CappedByteSink(
        maxBytes: maxDecompressedBytes,
        onChunk: (List<int> chunk) {
          total += chunk.length;
          output.add(chunk);
        },
      ),
    );
    sink.add(data);
    sink.close();
    if (total > maxDecompressedBytes) {
      throw StateError(
        'Decompressed payload exceeds $maxDecompressedBytes bytes',
      );
    }
    return output.toBytes();
  }

  static bool shouldCompress(int size) => size > _minSizeToCompress;
}

class _CappedByteSink implements Sink<List<int>> {
  _CappedByteSink({required this.maxBytes, required this.onChunk});

  final int maxBytes;
  final void Function(List<int> chunk) onChunk;
  var _total = 0;

  @override
  void add(List<int> data) {
    _total += data.length;
    if (_total > maxBytes) {
      throw StateError('Decompressed payload exceeds $maxBytes bytes');
    }
    onChunk(data);
  }

  @override
  void close() {}
}
