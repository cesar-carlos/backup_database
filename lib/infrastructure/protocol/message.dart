import 'package:backup_database/infrastructure/protocol/message_types.dart';

const int _magicNumber = 0xFA000000;
const int _protocolVersion = 0x01;

class MessageHeader {
  MessageHeader({
    required this.type,
    required this.length,
    this.magic = _magicNumber,
    this.version = _protocolVersion,
    this.requestId = 0,
    List<int>? flags,
    List<int>? reserved,
  }) : flags = flags ?? List.filled(3, 0),
       reserved = reserved ?? List.filled(7, 0);

  final int magic;
  final int version;
  final int length;
  final MessageType type;
  final int requestId;
  final List<int> flags;
  final List<int> reserved;

  Map<String, dynamic> toJson() => {
    'magic': magic,
    'version': version,
    'length': length,
    'type': type.name,
    'requestId': requestId,
    'flags': flags,
    'reserved': reserved,
  };

  factory MessageHeader.fromJson(Map<String, dynamic> json) {
    return MessageHeader(
      magic: json['magic'] as int? ?? _magicNumber,
      version: json['version'] as int? ?? _protocolVersion,
      length: json['length'] as int,
      type: MessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MessageType.error,
      ),
      requestId: json['requestId'] as int? ?? 0,
      flags:
          (json['flags'] as List<dynamic>?)?.map((e) => e as int).toList() ??
          List.filled(3, 0),
      reserved:
          (json['reserved'] as List<dynamic>?)?.map((e) => e as int).toList() ??
          List.filled(7, 0),
    );
  }
}

class Message {
  Message({
    required this.header,
    required this.payload,
    required this.checksum,
  });

  final MessageHeader header;
  final Map<String, dynamic> payload;
  final int checksum;

  Map<String, dynamic> toJson() => {
    'header': header.toJson(),
    'payload': payload,
    'checksum': checksum,
  };

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      header: MessageHeader.fromJson(
        json['header'] as Map<String, dynamic>,
      ),
      payload: Map<String, dynamic>.from(
        json['payload'] as Map<String, dynamic>,
      ),
      checksum: json['checksum'] as int,
    );
  }

  bool validateChecksum(int calculatedChecksum) =>
      checksum == calculatedChecksum;
}
