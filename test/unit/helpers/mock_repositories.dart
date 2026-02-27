import 'package:backup_database/application/services/license_generation_service.dart';
import 'package:backup_database/domain/repositories/i_backup_destination_repository.dart';
import 'package:backup_database/domain/repositories/i_license_repository.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/repositories/i_sql_server_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sybase_config_repository.dart';
import 'package:backup_database/domain/services/i_device_key_service.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:backup_database/domain/services/i_license_validation_service.dart';
import 'package:backup_database/infrastructure/external/process/tool_verification_service.dart';
import 'package:mocktail/mocktail.dart';

class MockSqlServerConfigRepository extends Mock
    implements ISqlServerConfigRepository {}

class MockSybaseConfigRepository extends Mock implements ISybaseConfigRepository {}

class MockPostgresConfigRepository extends Mock
    implements IPostgresConfigRepository {}

class MockBackupDestinationRepository extends Mock
    implements IBackupDestinationRepository {}

class MockScheduleRepository extends Mock implements IScheduleRepository {}

class MockToolVerificationService extends Mock
    implements ToolVerificationService {}

class MockLicensePolicyService extends Mock implements ILicensePolicyService {}

class MockLicenseValidationService extends Mock
    implements ILicenseValidationService {}

class MockLicenseRepository extends Mock implements ILicenseRepository {}

class MockDeviceKeyService extends Mock implements IDeviceKeyService {}

class MockLicenseGenerationService extends Mock
    implements LicenseGenerationService {}
