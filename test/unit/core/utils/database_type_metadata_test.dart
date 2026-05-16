import 'package:backup_database/core/theme/tokens/app_palette.dart';
import 'package:backup_database/core/utils/database_type_metadata.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DatabaseTypeMetadata', () {
    test('should define metadata for every DatabaseType value', () {
      for (final type in DatabaseType.values) {
        expect(
          DatabaseTypeMetadata.entries.containsKey(type),
          isTrue,
          reason: 'Missing DatabaseTypeMetadata entry for $type',
        );
      }
    });

    test('should expose expected labels and colors', () {
      final sql = DatabaseTypeMetadata.of(
        DatabaseType.sqlServer,
      );
      expect(sql.chipLabel, 'SQL Server');
      expect(sql.titleLabel, 'SQL Server');
      expect(sql.accentColor, AppPalette.databaseSqlServer);

      final sybase = DatabaseTypeMetadata.of(
        DatabaseType.sybase,
      );
      expect(sybase.chipLabel, 'Sybase');
      expect(sybase.titleLabel, 'Sybase SQL Anywhere');
      expect(sybase.accentColor, AppPalette.databaseSybase);

      final pg = DatabaseTypeMetadata.of(
        DatabaseType.postgresql,
      );
      expect(pg.chipLabel, 'PostgreSQL');
      expect(pg.titleLabel, 'PostgreSQL');
      expect(pg.accentColor, AppPalette.databasePostgresql);

      final fb = DatabaseTypeMetadata.of(
        DatabaseType.firebird,
      );
      expect(fb.chipLabel, 'Firebird');
      expect(fb.titleLabel, 'Firebird');
      expect(fb.accentColor, AppPalette.databaseFirebird);
    });
  });
}
