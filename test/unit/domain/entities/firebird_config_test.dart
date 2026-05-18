import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/schedule.dart'
    show DatabaseType;
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/firebird_config_enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FirebirdConfig', () {
    test('blank host becomes localhost', () {
      final cfg = FirebirdConfig(
        name: 'n',
        host: '   ',
        databaseFile: 'x.fdb',
        username: 'u',
        password: 'p',
      );
      expect(cfg.host, 'localhost');
    });

    test('primaryDatabase prefers non-empty alias over file stem', () {
      final withAlias = FirebirdConfig(
        name: 'n',
        host: 'h',
        databaseFile: r'C:\ignored\path.fdb',
        username: 'u',
        password: 'p',
        aliasName: '  myalias  ',
      );
      expect(withAlias.primaryDatabase, DatabaseName('myalias'));
    });

    test('primaryDatabase falls back to stem when alias is blank', () {
      final noAlias = FirebirdConfig(
        name: 'n',
        host: 'h',
        databaseFile: r'D:\db\production.fdb',
        username: 'u',
        password: 'p',
        aliasName: '   ',
      );
      expect(noAlias.primaryDatabase, DatabaseName('production'));
    });

    test('primaryDatabase uses firebird_db when path empty and no alias', () {
      final cfg = FirebirdConfig(
        name: 'n',
        host: 'h',
        databaseFile: '   ',
        username: 'u',
        password: 'p',
      );
      expect(cfg.primaryDatabase, DatabaseName('firebird_db'));
    });

    test('primaryDatabase sanitizes invalid file stem characters', () {
      final cfg = FirebirdConfig(
        name: 'n',
        host: 'h',
        databaseFile: r'C:\bad*name?.fdb',
        username: 'u',
        password: 'p',
      );
      expect(cfg.primaryDatabase.value, 'bad_name_');
    });

    test('equality and hashCode use id only', () {
      const id = 'same-id';
      final a = FirebirdConfig(
        id: id,
        name: 'a',
        host: 'h1',
        databaseFile: 'f1.fdb',
        username: 'u',
        password: 'p1',
      );
      final b = FirebirdConfig(
        id: id,
        name: 'b',
        host: 'h2',
        databaseFile: 'f2.fdb',
        username: 'u',
        password: 'p2',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith overrides selected fields', () {
      final original = FirebirdConfig(
        id: 'id-1',
        name: 'old',
        host: 'h',
        databaseFile: 'd.fdb',
        username: 'u',
        password: 'p',
      );
      final next = original.copyWith(
        name: 'new',
        serverVersionHint: FirebirdServerVersionHint.v40,
        cryptKey: 'k',
        enabled: false,
      );
      expect(next.id, original.id);
      expect(next.name, 'new');
      expect(next.serverVersionHint, FirebirdServerVersionHint.v40);
      expect(next.cryptKey, 'k');
      expect(next.enabled, isFalse);
      expect(next.databaseFile, original.databaseFile);
    });

    test('databaseType is firebird', () {
      final cfg = FirebirdConfig(
        name: 'n',
        host: 'h',
        databaseFile: 'x.fdb',
        username: 'u',
        password: 'p',
      );
      expect(cfg.databaseType, DatabaseType.firebird);
    });
  });
}
