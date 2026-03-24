import 'package:drift/drift.dart';

class MachineSettingsTable extends Table {
  IntColumn get id => integer()();

  BoolColumn get startWithWindows =>
      boolean().withDefault(const Constant(false))();

  BoolColumn get startMinimized =>
      boolean().withDefault(const Constant(false))();

  TextColumn get customTempDownloadsPath => text().nullable()();

  TextColumn get receivedBackupsDefaultPath => text().nullable()();

  TextColumn get scheduleTransferDestinationsJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
