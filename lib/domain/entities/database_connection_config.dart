import 'package:backup_database/domain/entities/schedule.dart'
    show DatabaseType;
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';

abstract interface class DatabaseConnectionConfig {
  String get id;
  String get name;
  PortNumber get port;
  String get username;
  String get password;
  bool get enabled;
  DateTime get createdAt;
  DateTime get updatedAt;

  DatabaseType get databaseType;
  String get host;
  DatabaseName get primaryDatabase;

  String? get backupTarget;
  int get portValue;
}
