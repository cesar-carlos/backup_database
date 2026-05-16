import 'package:backup_database/core/theme/tokens/app_palette.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:flutter/material.dart';

class DatabaseTypeMetadata {
  const DatabaseTypeMetadata({
    required this.chipLabel,
    required this.titleLabel,
    required this.accentColor,
  });

  final String chipLabel;
  final String titleLabel;
  final Color accentColor;

  static const Map<DatabaseType, DatabaseTypeMetadata> entries = {
    DatabaseType.sqlServer: DatabaseTypeMetadata(
      chipLabel: 'SQL Server',
      titleLabel: 'SQL Server',
      accentColor: AppPalette.databaseSqlServer,
    ),
    DatabaseType.sybase: DatabaseTypeMetadata(
      chipLabel: 'Sybase',
      titleLabel: 'Sybase SQL Anywhere',
      accentColor: AppPalette.databaseSybase,
    ),
    DatabaseType.postgresql: DatabaseTypeMetadata(
      chipLabel: 'PostgreSQL',
      titleLabel: 'PostgreSQL',
      accentColor: AppPalette.databasePostgresql,
    ),
    DatabaseType.firebird: DatabaseTypeMetadata(
      chipLabel: 'Firebird',
      titleLabel: 'Firebird',
      accentColor: AppPalette.databaseFirebird,
    ),
  };

  static DatabaseTypeMetadata of(DatabaseType type) => entries[type]!;
}
