import 'package:backup_database/infrastructure/datasources/local/tables/email_configs_table.dart';
import 'package:drift/drift.dart';

class EmailNotificationTargetsTable extends Table {
  TextColumn get id => text()();
  TextColumn get emailConfigId => text().references(
    EmailConfigsTable,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get recipientEmail => text()();
  BoolColumn get notifyOnSuccess =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get notifyOnError => boolean().withDefault(const Constant(true))();
  BoolColumn get notifyOnWarning =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {emailConfigId, recipientEmail},
  ];
}
