import 'package:drift/drift.dart';

class EmailConfigsTable extends Table {
  TextColumn get id => text()();
  TextColumn get senderName => text().withDefault(const Constant('Sistema de Backup'))();
  TextColumn get fromEmail => text().withDefault(const Constant('backup@example.com'))();
  TextColumn get fromName => text().withDefault(const Constant('Sistema de Backup'))();
  TextColumn get smtpServer => text().withDefault(const Constant('smtp.gmail.com'))();
  IntColumn get smtpPort => integer().withDefault(const Constant(587))();
  TextColumn get username => text().withDefault(const Constant(''))();
  TextColumn get password => text().withDefault(const Constant(''))();
  BoolColumn get useSsl => boolean().withDefault(const Constant(true))();
  TextColumn get recipients => text().withDefault(const Constant('[]'))(); // JSON array
  BoolColumn get notifyOnSuccess =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get notifyOnError => boolean().withDefault(const Constant(true))();
  BoolColumn get notifyOnWarning =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get attachLog => boolean().withDefault(const Constant(false))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

