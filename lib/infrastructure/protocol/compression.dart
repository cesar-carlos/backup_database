import 'dart:io';
import 'dart:typed_data';

const int _defaultCompressionLevel = 6;
const int _minSizeToCompress = 1024; // 1KB

class PayloadCompression {
  PayloadCompression({this.level = _defaultCompressionLevel});

  final int level;

  static const int minSizeToCompress = _minSizeToCompress;

  Uint8List compress(Uint8List data) {
    final codec = ZLibCodec(level: level);
    final compressed = codec.encode(data);
    return Uint8List.fromList(compressed);
  }

  Uint8List decompress(Uint8List data) {
    final codec = ZLibCodec();
    final decompressed = codec.decode(data);
    return Uint8List.fromList(decompressed);
  }

  static bool shouldCompress(int size) => size > _minSizeToCompress;
}
