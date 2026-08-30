enum RemoteDbKind {
  sybase('sybase'),
  sqlServer('sqlServer'),
  postgres('postgres'),
  firebird('firebird');

  const RemoteDbKind(this.wireName);

  final String wireName;

  static RemoteDbKind? fromWire(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    for (final kind in values) {
      if (kind.wireName == raw) {
        return kind;
      }
    }
    return null;
  }
}

String remoteDatabaseTypeLabel(RemoteDbKind kind) => switch (kind) {
  RemoteDbKind.sybase => 'Sybase',
  RemoteDbKind.sqlServer => 'SQL Server',
  RemoteDbKind.postgres => 'PostgreSQL',
  RemoteDbKind.firebird => 'Firebird',
};
