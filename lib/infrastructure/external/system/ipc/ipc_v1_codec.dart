import 'dart:convert';
import 'dart:io' show pid;

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/uuid_validator.dart';
import 'package:backup_database/domain/services/i_single_instance_ipc_client.dart';

class IpcV1Codec {
  IpcV1Codec._();

  static final RegExp _protocolVersionField = RegExp(
    r'(?:^|\|)'
    'v=${SingleInstanceConfig.ipcProtocolVersion}'
    r'(?:\||$)',
  );

  static final RegExp _runSchedulePrefix = RegExp(
    '^${RegExp.escape(SingleInstanceConfig.ipcProtocolId)}\\|'
    '${RegExp.escape(SingleInstanceConfig.ipcRunScheduleCommand)}\\|',
  );

  static String normalizeRole(String role) {
    final normalized = role.trim().toLowerCase();
    if (normalized == SingleInstanceConfig.ipcInstanceRoleService) {
      return SingleInstanceConfig.ipcInstanceRoleService;
    }
    return SingleInstanceConfig.ipcInstanceRoleUi;
  }

  static String stripLine(String raw) {
    return raw.replaceAll('\r', '').replaceAll('\n', '').trim();
  }

  static bool exceedsMaxLineBytes(List<int> bytes) {
    return bytes.length > SingleInstanceConfig.ipcMaxLineBytes;
  }

  static bool hasProtocolVersion(String message) {
    return _protocolVersionField.hasMatch(message);
  }

  static bool isOkAck(String? message) {
    return message == SingleInstanceConfig.ipcOkAckMessage;
  }

  static String? parseRunScheduleRequest(String message) {
    if (!_runSchedulePrefix.hasMatch(message)) {
      return null;
    }
    if (!hasProtocolVersion(message)) {
      return null;
    }
    final match = RegExp(r'(?:^|\|)scheduleId=([^|\s]+)').firstMatch(message);
    final scheduleId = match?.group(1);
    if (scheduleId == null || !UuidValidator.isValid(scheduleId)) {
      return null;
    }
    return scheduleId;
  }

  static String buildRunScheduleResultLine({
    required int exitCode,
    String? message,
  }) {
    final buffer =
        StringBuffer(SingleInstanceConfig.ipcRunScheduleResultLinePrefix)
          ..write('v=${SingleInstanceConfig.ipcProtocolVersion}|')
          ..write('exitCode=$exitCode');
    if (message != null && message.isNotEmpty) {
      buffer.write('|message64=${base64Url.encode(utf8.encode(message))}');
    }
    return buffer.toString();
  }

  static SingleInstanceScheduledDelegationResult? parseRunScheduleResult(
    String message,
  ) {
    if (!message.startsWith(
      SingleInstanceConfig.ipcRunScheduleResultLinePrefix,
    )) {
      return null;
    }
    if (!hasProtocolVersion(message)) {
      return null;
    }
    final exitMatch = RegExp(r'(?:^|\|)exitCode=(-?\d+)').firstMatch(message);
    final exitCode = int.tryParse(exitMatch?.group(1) ?? '');
    if (exitCode == null) {
      return null;
    }
    String? decodedMessage;
    final messageMatch = RegExp(
      r'(?:^|\|)message64=([^|\s]+)',
    ).firstMatch(message);
    if (messageMatch != null) {
      try {
        decodedMessage = utf8.decode(base64Url.decode(messageMatch.group(1)!));
      } on Object {
        decodedMessage = null;
      }
    }
    return SingleInstanceScheduledDelegationResult(
      exitCode: exitCode,
      message: decodedMessage,
    );
  }

  static String buildV1PongLine({
    required String role,
    required bool canRunSchedule,
  }) {
    return '${SingleInstanceConfig.ipcPongLinePrefix}'
        'v=${SingleInstanceConfig.ipcProtocolVersion}|'
        'role=$role|'
        'canRunSchedule=$canRunSchedule|'
        'pid=$pid';
  }

  static String buildV1UserInfoLine({
    required String username,
    required String role,
  }) {
    final u64 = base64Url.encode(utf8.encode(username));
    return '${SingleInstanceConfig.ipcUserInfoLinePrefix}'
        'v=${SingleInstanceConfig.ipcProtocolVersion}|'
        'role=$role|'
        'pid=$pid|'
        'u64=$u64';
  }

  static bool isValidV1Pong(String response) {
    if (!response.startsWith(SingleInstanceConfig.ipcPongLinePrefix)) {
      return false;
    }
    if (!hasProtocolVersion(response)) {
      return false;
    }
    if (parseRoleFromV1Line(response) == null) {
      return false;
    }
    if (!response.contains('pid=')) {
      return false;
    }
    return true;
  }

  static SingleInstanceOwnerInfo? parseOwnerInfoFromV1Pong(String response) {
    if (!isValidV1Pong(response)) {
      return null;
    }
    final role = parseRoleFromV1Line(response);
    if (role == null) {
      return null;
    }
    return SingleInstanceOwnerInfo(
      role: role,
      canRunSchedule: parseBoolField(
        response,
        'canRunSchedule',
        defaultValue: false,
      ),
    );
  }

  static String? parseUserInfoResponse(String message) {
    if (!message.startsWith(SingleInstanceConfig.ipcUserInfoLinePrefix)) {
      return null;
    }
    if (!hasProtocolVersion(message)) {
      return null;
    }
    if (parseRoleFromV1Line(message) == null) {
      return null;
    }
    final match = RegExp(r'u64=([^|\s]+)').firstMatch(message);
    if (match == null) {
      return null;
    }
    try {
      return utf8.decode(base64Url.decode(match.group(1)!));
    } on Object {
      return null;
    }
  }

  static String? parseRoleFromV1Line(String message) {
    final match = RegExp(r'(?:^|\|)role=([^|\s]+)').firstMatch(message);
    final role = match?.group(1);
    if (role == SingleInstanceConfig.ipcInstanceRoleUi ||
        role == SingleInstanceConfig.ipcInstanceRoleService) {
      return role;
    }
    return null;
  }

  static bool parseBoolField(
    String message,
    String fieldName, {
    required bool defaultValue,
  }) {
    final match = RegExp(
      '(?:^|\\|)$fieldName=([^|\\s]+)',
    ).firstMatch(message);
    final value = match?.group(1)?.toLowerCase();
    if (value == 'true') {
      return true;
    }
    if (value == 'false') {
      return false;
    }
    return defaultValue;
  }
}
