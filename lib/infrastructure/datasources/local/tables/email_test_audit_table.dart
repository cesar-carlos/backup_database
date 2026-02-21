import 'package:drift/drift.dart';

class EmailTestAuditTable extends Table {
  TextColumn get id => text()();
  TextColumn get configId => text()();
  TextColumn get correlationId => text()();
  TextColumn get recipientEmail => text()();
  TextColumn get senderEmail => text()();
  TextColumn get smtpServer => text()();
  IntColumn get smtpPort => integer()();
  TextColumn get status => text()();
  TextColumn get errorType => text().nullable()();
  TextColumn get errorMessage => text().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
