import 'dart:typed_data';

class Crc32 {
  Crc32._();

  static const int _poly = 0xEDB88320;

  static final List<int> _table = _buildTable();

  static List<int> _buildTable() {
    final table = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      var crc = i;
      for (var j = 0; j < 8; j++) {
        crc = (crc & 1) == 1 ? (_poly ^ (crc >> 1)) : (crc >> 1);
      }
      table[i] = crc;
    }
    return table;
  }

  static int calculate(List<int> data) {
    var crc = 0xFFFFFFFF;
    for (var i = 0; i < data.length; i++) {
      crc = _table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static int calculateUint8List(Uint8List data) => calculate(data);
}
