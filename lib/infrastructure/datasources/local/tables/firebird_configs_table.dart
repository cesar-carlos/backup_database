import 'package:drift/drift.dart';

class FirebirdConfigsTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get host => text()();
  IntColumn get port => integer().withDefault(const Constant(3050))();
  TextColumn get databaseFile => text()();
  TextColumn get aliasName => text().nullable()();
  BoolColumn get useEmbedded => boolean().withDefault(const Constant(false))();
  TextColumn get clientLibraryPath => text().nullable()();
  TextColumn get serverVersionHint =>
      text().withDefault(const Constant('auto'))();
  TextColumn get serviceManagerMode =>
      text().withDefault(const Constant('auto'))();
  TextColumn get username => text()();
  TextColumn get password => text()();
  TextColumn get cryptKey => text().withDefault(const Constant(''))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
