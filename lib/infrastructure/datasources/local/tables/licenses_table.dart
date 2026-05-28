import 'package:drift/drift.dart';

class LicensesTable extends Table {
  TextColumn get id => text()();
  TextColumn get deviceKey => text()();
  TextColumn get licenseKey => text()();
  DateTimeColumn get expiresAt => dateTime().nullable()();

  /// Janela "not before" — licença ainda não passou a valer. Persistir
  /// (em vez de só validar no decode) evita o bypass de "renove agora,
  /// reabra o app antes do horário e use".
  DateTimeColumn get notBefore => dateTime().nullable()();

  TextColumn get allowedFeatures =>
      text().withDefault(const Constant('[]'))(); // JSON array
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {deviceKey},
  ];
}
