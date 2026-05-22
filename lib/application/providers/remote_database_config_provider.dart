import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:flutter/foundation.dart';

class RemoteDatabaseConfigEntry {
  const RemoteDatabaseConfigEntry({
    required this.id,
    required this.name,
    required this.databaseType,
  });

  final String id;
  final String name;
  final RemoteDatabaseType databaseType;

  String get listKey => '${databaseType.wireName}|$id';

  static RemoteDatabaseConfigEntry? fromMap(
    RemoteDatabaseType type,
    Map<String, dynamic> map,
  ) {
    final id = map['id'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    final name = map['name'] is String ? map['name'] as String : id;
    return RemoteDatabaseConfigEntry(
      id: id,
      name: name,
      databaseType: type,
    );
  }
}

String remoteDatabaseTypeLabel(RemoteDatabaseType type) => switch (type) {
  RemoteDatabaseType.sybase => 'Sybase',
  RemoteDatabaseType.sqlServer => 'SQL Server',
  RemoteDatabaseType.postgres => 'PostgreSQL',
  RemoteDatabaseType.firebird => 'Firebird',
};

class RemoteDatabaseConfigProvider extends ChangeNotifier with AsyncStateMixin {
  RemoteDatabaseConfigProvider(this._connectionManager);

  final ConnectionManager _connectionManager;

  List<RemoteDatabaseConfigEntry> _entries = <RemoteDatabaseConfigEntry>[];
  final Set<String> _testingKeys = <String>{};
  final Set<String> _deletingKeys = <String>{};

  List<RemoteDatabaseConfigEntry> get entries => _entries;
  bool get isConnected => _connectionManager.isConnected;

  bool isTesting(String listKey) => _testingKeys.contains(listKey);

  bool isDeleting(String listKey) => _deletingKeys.contains(listKey);

  Iterable<RemoteDatabaseType> get _typesToLoad sync* {
    for (final type in RemoteDatabaseType.values) {
      if (type == RemoteDatabaseType.firebird &&
          !_connectionManager.isFirebirdSupported) {
        continue;
      }
      yield type;
    }
  }

  Future<void> loadConfigs() async {
    if (!_connectionManager.isConnected) {
      setErrorManual('Conecte-se a um servidor para ver os bancos.');
      return;
    }
    await runAsync<void>(
      genericErrorMessage: 'Erro ao carregar bancos do servidor',
      action: () async {
        final merged = <RemoteDatabaseConfigEntry>[];
        for (final type in _typesToLoad) {
          final result = await _connectionManager.listRemoteDatabaseConfigs(
            type,
          );
          result.fold(
            (list) {
              for (final map in list.configs) {
                final entry = RemoteDatabaseConfigEntry.fromMap(type, map);
                if (entry != null) {
                  merged.add(entry);
                }
              }
            },
            (failure) => throw failure,
          );
        }
        merged.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        _entries = merged;
      },
    );
  }

  Future<String?> testConnection(RemoteDatabaseConfigEntry entry) async {
    if (!_connectionManager.isConnected) {
      return 'Conecte-se a um servidor.';
    }
    _testingKeys.add(entry.listKey);
    notifyListeners();
    try {
      final result = await _connectionManager.testRemoteDatabaseConnection(
        databaseType: entry.databaseType,
        databaseConfigId: entry.id,
      );
      return result.fold(
        (test) {
          if (test.connected) {
            return null;
          }
          final message = test.error?.trim();
          return message != null && message.isNotEmpty
              ? message
              : 'Falha ao testar conexão.';
        },
        AsyncStateMixin.extractFailureMessage,
      );
    } finally {
      _testingKeys.remove(entry.listKey);
      notifyListeners();
    }
  }

  Future<bool> deleteConfig(RemoteDatabaseConfigEntry entry) async {
    if (!_connectionManager.isConnected) {
      setErrorManual('Conecte-se a um servidor para excluir bancos.');
      return false;
    }
    _deletingKeys.add(entry.listKey);
    notifyListeners();
    try {
      final ok = await runAsync<bool>(
        genericErrorMessage: 'Erro ao excluir banco do servidor',
        action: () async {
          final result = await _connectionManager.deleteRemoteDatabaseConfig(
            databaseType: entry.databaseType,
            configId: entry.id,
          );
          return result.fold(
            (mutation) {
              if (!mutation.isDeleted) {
                return false;
              }
              _entries = _entries
                  .where((e) => e.listKey != entry.listKey)
                  .toList();
              return true;
            },
            (failure) => throw failure,
          );
        },
      );
      return ok ?? false;
    } finally {
      _deletingKeys.remove(entry.listKey);
      notifyListeners();
    }
  }
}
