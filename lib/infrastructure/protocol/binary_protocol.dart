import 'dart:convert';
import 'dart:typed_data';

import 'package:backup_database/core/utils/crc32.dart';
import 'package:backup_database/infrastructure/protocol/compression.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';

const int _headerSize = 16;
const int _checksumSize = 4;
const int _magicNumber = 0xFA000000;
const int _protocolVersion = 0x01;
const int _flagCompressed = 0x01;

class BinaryProtocol {
  BinaryProtocol({this.compression});

  final PayloadCompression? compression;

  Uint8List serializeMessage(Message message) {
    final rawPayload = utf8.encode(jsonEncode(message.payload));
    var flag0 = message.header.flags.isNotEmpty ? message.header.flags[0] : 0;
    final flag1 = message.header.flags.length > 1 ? message.header.flags[1] : 0;

    final Uint8List payloadBytes;
    if (compression != null &&
        PayloadCompression.shouldCompress(rawPayload.length)) {
      payloadBytes = compression!.compress(Uint8List.fromList(rawPayload));
      flag0 |= _flagCompressed;
    } else {
      payloadBytes = Uint8List.fromList(rawPayload);
    }

    final payloadLength = payloadBytes.length;
    final checksum = Crc32.calculate(payloadBytes);

    final buffer = ByteData(_headerSize + payloadLength + _checksumSize);
    var offset = 0;

    buffer.setUint32(offset, message.header.magic);
    offset += 4;
    buffer.setUint8(offset, message.header.version);
    offset += 1;
    buffer.setUint32(offset, payloadLength);
    offset += 4;
    buffer.setUint8(offset, message.header.type.index);
    offset += 1;
    buffer.setUint32(offset, message.header.requestId);
    offset += 4;
    buffer.setUint8(offset, flag0);
    offset += 1;
    buffer.setUint8(offset, flag1);
    offset += 1;
    buffer.buffer.asUint8List().setRange(
          _headerSize,
          _headerSize + payloadLength,
          payloadBytes,
        );
    buffer.setUint32(_headerSize + payloadLength, checksum);

    return buffer.buffer.asUint8List();
  }

  Message deserializeMessage(Uint8List data) {
    if (data.length < _headerSize + _checksumSize) {
      throw ProtocolException('Message too short');
    }

    final headerData = ByteData.sublistView(data, 0, _headerSize);
    final magic = headerData.getUint32(0);
    if (magic != _magicNumber) {
      throw ProtocolException('Invalid magic: 0x${magic.toRadixString(16)}');
    }
    final version = headerData.getUint8(4);
    if (version != _protocolVersion) {
      throw ProtocolException('Unsupported version: $version');
    }
    final length = headerData.getUint32(5);
    if (data.length < _headerSize + length + _checksumSize) {
      throw ProtocolException(
        'Incomplete message: expected ${_headerSize + length + _checksumSize} bytes, got ${data.length}',
      );
    }

    final payloadBytes = Uint8List.sublistView(
      data,
      _headerSize,
      _headerSize + length,
    );
    final checksumOffset = _headerSize + length;
    final expectedChecksum = ByteData.sublistView(
      data,
      checksumOffset,
      checksumOffset + _checksumSize,
    ).getUint32(0);
    final calculatedChecksum = Crc32.calculate(payloadBytes);
    if (calculatedChecksum != expectedChecksum) {
      throw ProtocolException(
        'Checksum mismatch: expected $expectedChecksum, got $calculatedChecksum',
      );
    }

    final typeIndex = headerData.getUint8(9);
    final type = typeIndex < MessageType.values.length
        ? MessageType.values[typeIndex]
        : MessageType.error;
    final requestId = headerData.getUint32(10);

    final flags = <int>[
      headerData.getUint8(14),
      headerData.getUint8(15),
      0,
    ];
    const reserved = [0, 0, 0, 0, 0, 0, 0];

    var bytesToDecode = payloadBytes;
    if ((flags[0] & _flagCompressed) != 0) {
      if (compression == null) {
        throw ProtocolException(
          'Message is compressed but BinaryProtocol has no compression',
        );
      }
      bytesToDecode = compression!.decompress(payloadBytes);
    }

    final payloadJson = utf8.decode(bytesToDecode);
    final payload = Map<String, dynamic>.from(
      jsonDecode(payloadJson) as Map<String, dynamic>,
    );

    final header = MessageHeader(
      magic: magic,
      version: version,
      length: length,
      type: type,
      requestId: requestId,
      flags: flags,
      reserved: reserved,
    );

    return Message(
      header: header,
      payload: payload,
      checksum: expectedChecksum,
    );
  }

  int calculateChecksum(Uint8List data) => Crc32.calculate(data);

  bool validateChecksum(Uint8List data, int expectedChecksum) =>
      Crc32.calculate(data) == expectedChecksum;
}

class ProtocolException implements Exception {
  ProtocolException(this.message);
  final String message;
  @override
  String toString() => 'ProtocolException: $message';
}
