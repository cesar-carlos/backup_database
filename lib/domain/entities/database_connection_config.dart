import 'package:backup_database/domain/entities/schedule.dart'
    show DatabaseType;
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';

abstract class DatabaseConnectionConfig {
  DatabaseConnectionConfig({
    required this.id,
    required this.name,
    required this.port,
    required this.username,
    required this.password,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final PortNumber port;
  final String username;
  final String password;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  DatabaseType get databaseType;
  String get host;
  DatabaseName get primaryDatabase;

  String? get backupTarget => null;

  int get portValue => port.value;
}
