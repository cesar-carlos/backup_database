import 'dart:convert';

import 'package:backup_database/infrastructure/datasources/daos/idempotency_dao.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';

/// Persistencia de respostas idempotentes (sobrevive a restart do servidor).
abstract class IdempotencyStore {
  Future<Message?> loadValid(String key, DateTime now);

  Future<void> save({
    required String key,
    required Message response,
    required DateTime expiresAt,
    required DateTime createdAt,
  });

  Future<void> purgeExpiredBefore(DateTime now);
}

class DriftIdempotencyStore implements IdempotencyStore {
  DriftIdempotencyStore(this._dao);

  final IdempotencyDao _dao;

  @override
  Future<Message?> loadValid(String key, DateTime now) async {
    final row = await _dao.getByKey(key);
    if (row == null) return null;
    if (row.expiresAtMicros <= now.microsecondsSinceEpoch) {
      await _dao.deleteByKey(key);
      return null;
    }
    final decoded = jsonDecode(row.responseJson) as Map<String, dynamic>;
    return Message.fromJson(decoded);
  }

  @override
  Future<void> save({
    required String key,
    required Message response,
    required DateTime expiresAt,
    required DateTime createdAt,
  }) async {
    final json = jsonEncode(response.toJson());
    await _dao.upsert(
      key: key,
      responseJson: json,
      createdAtMicros: createdAt.microsecondsSinceEpoch,
      expiresAtMicros: expiresAt.microsecondsSinceEpoch,
    );
  }

  @override
  Future<void> purgeExpiredBefore(DateTime now) {
    return _dao.deleteExpiredBefore(now.microsecondsSinceEpoch);
  }
}
