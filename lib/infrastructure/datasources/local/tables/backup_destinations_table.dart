import 'package:drift/drift.dart';

class BackupDestinationsTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // 'local', 'ftp', 'googleDrive'
  TextColumn get config => text()(); // JSON
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get tempPath => text().nullable()(); // Pasta temp para cliente
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
