import 'package:drift/drift.dart';

class LicensesTable extends Table {
  TextColumn get id => text()();
  TextColumn get deviceKey => text()();
  TextColumn get licenseKey => text()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  TextColumn get allowedFeatures =>
      text().withDefault(const Constant('[]'))(); // JSON array
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
