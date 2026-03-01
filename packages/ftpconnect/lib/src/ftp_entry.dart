import 'package:intl/intl.dart';

import 'ftp_exceptions.dart';
import 'ftpconnect_base.dart';

class FTPEntry {
  FTPEntry._(
    this.name,
    this.modifyTime,
    this.permission,
    this.type,
    this.size,
    this.unique,
    this.group,
    this.gid,
    this.mode,
    this.owner,
    this.uid,
    this.additionalProperties,
  );

  final String name;
  final DateTime? modifyTime;
  final String? permission;
  final FTPEntryType type;
  final int? size;
  final String? unique;
  final String? group;
  final int? gid;
  final String? mode;
  final String? owner;
  final int? uid;
  final Map<String, String>? additionalProperties;

  static final RegExp regexpLIST = RegExp(
    r"^([\-ld])"
    r"([\-rwxs]{9})\s+"
    r"(\d+)\s+"
    r"(\w+)\s+"
    r"(\w+)\s+"
    r"(\d+)\s+"
    r"(\w{3}\s+\d{1,2}\s+(?:\d{1,2}:\d{1,2}|\d{4}))\s+"
    r"(.+)$",
  );

  static final RegExp regexpLISTSiiServers = RegExp(
    r"^(.{8}\s+.{7})\s+"
    r"(.{0,5})\s+"
    r"(\d{0,24})\s+"
    r"(.+)$",
  );

  factory FTPEntry.parse(String responseLine, ListCommand cmd) {
    if (responseLine.trim().isEmpty) {
      throw FTPConnectException("Can't parse a null or blank response line");
    }
    if (cmd == ListCommand.list) {
      return FTPEntry._parseListCommand(responseLine);
    } else if (cmd == ListCommand.nlst) {
      return FTPEntry._(
        responseLine,
        null,
        null,
        FTPEntryType.unknown,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
      );
    } else {
      return FTPEntry._parseMLSDCommand(responseLine);
    }
  }

  factory FTPEntry._parseMLSDCommand(final String responseLine) {
    var name = '';
    DateTime? modifyTime;
    String? permission;
    var type = FTPEntryType.unknown;
    var size = 0;
    String? unique;
    String? group;
    var gid = -1;
    String? mode;
    String? owner;
    var uid = -1;
    final additional = <String, String>{};

    for (final property in responseLine.trim().split(';')) {
      final prop = property
          .split('=')
          .map((part) => part.trim())
          .toList(growable: false);

      if (prop.length == 1) {
        name = prop[0];
      } else {
        switch (prop[0].toLowerCase()) {
          case 'modify':
            final date = '${prop[1].substring(0, 8)}T${prop[1].substring(8)}';
            modifyTime = DateTime.tryParse(prop[1]) ?? DateTime.tryParse(date);
            break;
          case 'perm':
            permission = prop[1];
            break;
          case 'size':
            size = int.parse(prop[1]);
            break;
          case 'type':
            if (prop[1] == 'dir') {
              type = FTPEntryType.dir;
            } else if (prop[1] == 'file') {
              type = FTPEntryType.file;
            } else {
              type = FTPEntryType.link;
            }
            break;
          case 'unique':
            unique = prop[1];
            break;
          case 'unix.group':
            group = prop[1];
            break;
          case 'unix.gid':
            gid = int.parse(prop[1]);
            break;
          case 'unix.mode':
            mode = prop[1];
            break;
          case 'unix.owner':
            owner = prop[1];
            break;
          case 'unix.uid':
            uid = int.parse(prop[1]);
            break;
          default:
            additional.putIfAbsent(prop[0], () => prop[1]);
            break;
        }
      }
    }

    return FTPEntry._(
      name,
      modifyTime,
      permission,
      type,
      size,
      unique,
      group,
      gid,
      mode,
      owner,
      uid,
      Map.unmodifiable(additional),
    );
  }

  factory FTPEntry._parseListCommand(final String responseLine) {
    if (regexpLIST.hasMatch(responseLine)) {
      return FTPEntry._parseLIST(responseLine);
    } else if (regexpLISTSiiServers.hasMatch(responseLine)) {
      return FTPEntry._parseLISTiis(responseLine);
    } else {
      throw FTPConnectException(
        'Invalid format <$responseLine> for LIST command response !',
      );
    }
  }

  factory FTPEntry._parseLIST(final String responseLine) {
    var name = '';
    DateTime? modifyTime;
    String? persmission;
    var type = FTPEntryType.unknown;
    var size = 0;
    String? unique;
    String? group;
    var gid = -1;
    String? mode;
    String? owner;
    var uid = -1;

    for (final match in regexpLIST.allMatches(responseLine)) {
      if (match.group(1) == '-') {
        type = FTPEntryType.file;
      } else if (match.group(1) == 'd') {
        type = FTPEntryType.dir;
      } else {
        type = FTPEntryType.link;
      }
      persmission = match.group(2);
      owner = match.group(4);
      group = match.group(5);
      size = int.tryParse(match.group(6)!) ?? 0;
      var date = (match.group(7)!.split(' ')..removeWhere((i) => i.isEmpty))
          .join(' ');
      if (date.contains(':')) date = '$date ${DateTime.now().year}';
      final format = date.contains(':') ? 'MMM dd hh:mm yyyy' : 'MMM dd yyyy';
      modifyTime = DateFormat(format, 'en_US').parse(date);
      name = match.group(8)!;
    }
    return FTPEntry._(
      name,
      modifyTime,
      persmission,
      type,
      size,
      unique,
      group,
      gid,
      mode,
      owner,
      uid,
      {},
    );
  }

  factory FTPEntry._parseLISTiis(final String responseLine) {
    var name = '';
    DateTime? modifyTime;
    String? persmission;
    var type = FTPEntryType.unknown;
    var size = 0;
    String? unique;
    String? group;
    var gid = -1;
    String? mode;
    String? owner;
    var uid = -1;

    for (final match in regexpLISTSiiServers.allMatches(responseLine)) {
      final date = match.group(1)!.split(' ').fold('', (prev, element) {
        if (element.isEmpty) return prev;
        if (prev.isEmpty) {
          return element.length <= 8
              ? element.substring(0, 6) +
                  DateTime.now().year.toString().substring(0, 2) +
                  element.substring(6, 8)
              : element;
        }
        return '$prev $element';
      });
      modifyTime = DateFormat('MM-dd-yyyy hh:mma').parse(date);

      if (match.group(2)!.trim().isEmpty) {
        type = FTPEntryType.file;
      } else if (match.group(2)!.toLowerCase().contains('dir')) {
        type = FTPEntryType.dir;
      } else {
        type = FTPEntryType.link;
      }
      size = int.tryParse(match.group(3)!) ?? 0;
      name = match.group(4)!;
    }
    return FTPEntry._(
      name,
      modifyTime,
      persmission,
      type,
      size,
      unique,
      group,
      gid,
      mode,
      owner,
      uid,
      {},
    );
  }

  @override
  String toString() =>
      'name=$name;modify=$modifyTime;perm=$permission;type=${type.describeEnum.toLowerCase()};size=$size;unique=$unique;unix.group=$group;unix.mode=$mode;unix.owner=$owner;unix.uid=$uid;unix.gid=$gid';
}

enum FTPEntryType { file, dir, link, unknown }

extension FtpEntryTypeEnum on FTPEntryType {
  String get describeEnum => toString().substring(toString().indexOf('.') + 1);
}
