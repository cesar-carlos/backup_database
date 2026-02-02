import 'dart:convert';

import 'package:backup_database/application/providers/providers.dart';
import 'package:backup_database/application/services/initial_setup_service.dart';
import 'package:backup_database/application/services/service_health_checker.dart';
import 'package:backup_database/application/services/services.dart';
import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/utils/clipboard_service.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/services.dart';
import 'package:backup_database/domain/use_cases/use_cases.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/external/external.dart';
import 'package:backup_database/infrastructure/http/api_client.dart';
import 'package:backup_database/infrastructure/repositories/repositories.dart';
import 'package:backup_database/infrastructure/security/secure_credential_service.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:backup_database/infrastructure/socket/server/client_manager.dart';
import 'package:backup_database/infrastructure/socket/server/file_transfer_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/metrics_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/schedule_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/socket_server_service.dart';
import 'package:backup_database/infrastructure/socket/server/tcp_socket_server.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:result_dart/result_dart.dart' as rd;

final GetIt getIt = GetIt.instance;

Future<void> setupServiceLocator() async {
  getIt.registerLazySingleton<LoggerService>(LoggerService.new);
  getIt.registerLazySingleton<ClipboardService>(ClipboardService.new);
  getIt.registerLazySingleton<ISingleInstanceService>(
    SingleInstanceService.new,
  );

  getIt.registerLazySingleton<Dio>(Dio.new);
  getIt.registerLazySingleton<ApiClient>(() => ApiClient(getIt<Dio>()));

  getIt.registerLazySingleton<AppDatabase>(AppDatabase.new);

  getIt.registerLazySingleton<ISqlServerConfigRepository>(
    () => SqlServerConfigRepository(
      getIt<AppDatabase>(),
      getIt<ISecureCredentialService>(),
    ),
  );
  getIt.registerLazySingleton<ISybaseConfigRepository>(
    () => SybaseConfigRepository(
      getIt<AppDatabase>(),
      getIt<ISecureCredentialService>(),
    ),
  );
  getIt.registerLazySingleton<IPostgresConfigRepository>(
    () => PostgresConfigRepository(
      getIt<AppDatabase>(),
      getIt<ISecureCredentialService>(),
    ),
  );
  getIt.registerLazySingleton<IBackupDestinationRepository>(
    () => BackupDestinationRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IScheduleRepository>(
    () => ScheduleRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IBackupHistoryRepository>(
    () => CachedBackupHistoryRepository(
      repository: BackupHistoryRepository(getIt<AppDatabase>()),
    ),
  );
  getIt.registerLazySingleton<IBackupLogRepository>(
    () => BackupLogRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IEmailConfigRepository>(
    () => EmailConfigRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<ILicenseRepository>(
    () => LicenseRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IServerCredentialRepository>(
    () => ServerCredentialRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<InitialSetupService>(
    () => InitialSetupService(
      getIt<IServerCredentialRepository>(),
      getIt<ISecureCredentialService>(),
    ),
  );
  getIt.registerLazySingleton<IConnectionLogRepository>(
    () => ConnectionLogRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IServerConnectionRepository>(
    () => ServerConnectionRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<ConnectionManager>(
    () => ConnectionManager(
      serverConnectionDao: getIt<AppDatabase>().serverConnectionDao,
    ),
  );
  getIt.registerLazySingleton<ClientManager>(ClientManager.new);
  getIt.registerLazySingleton<ScheduleMessageHandler>(
    () => ScheduleMessageHandler(
      scheduleRepository: getIt<IScheduleRepository>(),
      updateSchedule: getIt<UpdateSchedule>(),
      executeBackup: getIt<ExecuteScheduledBackup>(),
    ),
  );
  final appDir = await getApplicationDocumentsDirectory();
  final transferBasePath = p.join(appDir.path, 'backups');
  getIt.registerLazySingleton<FileTransferMessageHandler>(
    () => FileTransferMessageHandler(allowedBasePath: transferBasePath),
  );
  getIt.registerLazySingleton<MetricsMessageHandler>(
    () => MetricsMessageHandler(
      backupHistoryRepository: getIt<IBackupHistoryRepository>(),
      scheduleRepository: getIt<IScheduleRepository>(),
    ),
  );
  getIt.registerLazySingleton<TcpSocketServer>(
    () => TcpSocketServer(
      serverCredentialDao: getIt<AppDatabase>().serverCredentialDao,
      clientManager: getIt<ClientManager>(),
      connectionLogDao: getIt<AppDatabase>().connectionLogDao,
      scheduleHandler: getIt<ScheduleMessageHandler>(),
      fileTransferHandler: getIt<FileTransferMessageHandler>(),
      metricsHandler: getIt<MetricsMessageHandler>(),
    ),
  );
  getIt.registerLazySingleton<SocketServerService>(getIt.get<TcpSocketServer>);

  getIt.registerLazySingleton<IDeviceKeyService>(DeviceKeyService.new);

  final deviceKeyResult = await getIt<IDeviceKeyService>().getDeviceKey();
  if (deviceKeyResult.isSuccess()) {
    final deviceKey = deviceKeyResult.getOrNull()!;
    EncryptionService.initializeWithDeviceKey(deviceKey);
    LoggerService.info(
      'EncryptionService initialized with device-specific key',
    );
  } else {
    LoggerService.warning(
      'Failed to get device key, EncryptionService using legacy key',
    );
  }

  getIt.registerLazySingleton<ISecureCredentialService>(
    SecureCredentialService.new,
  );

  getIt.registerLazySingleton<ILicenseValidationService>(
    () => LicenseValidationService(
      licenseRepository: getIt<ILicenseRepository>(),
      deviceKeyService: getIt<IDeviceKeyService>(),
    ),
  );

  final licenseSecretKeyResult = await _getOrCreateLicenseSecretKey();
  if (licenseSecretKeyResult.isError()) {
    final error = licenseSecretKeyResult.exceptionOrNull();
    LoggerService.error(
      'Failed to get license secret key: $error',
    );
  }

  getIt.registerLazySingleton<LicenseGenerationService>(() {
    final secretKey = licenseSecretKeyResult.getOrElse(
      (_) => 'BACKUP_DATABASE_LICENSE_SECRET_2024',
    );
    return LicenseGenerationService(secretKey: secretKey);
  });

  getIt.registerLazySingleton<ProcessService>(ProcessService.new);

  getIt.registerLazySingleton<ToolVerificationService>(
    () => ToolVerificationService(getIt<ProcessService>()),
  );

  getIt.registerLazySingleton<IWindowsServiceService>(
    () => WindowsServiceService(getIt<ProcessService>()),
  );

  getIt.registerLazySingleton<ISqlServerBackupService>(
    () => SqlServerBackupService(getIt<ProcessService>()),
  );

  getIt.registerLazySingleton<ISybaseBackupService>(
    () => SybaseBackupService(getIt<ProcessService>()),
  );

  getIt.registerLazySingleton<IPostgresBackupService>(
    () => PostgresBackupService(getIt<ProcessService>()),
  );

  getIt.registerLazySingleton<ICompressionService>(
    () => CompressionService(getIt<ProcessService>()),
  );

  getIt.registerLazySingleton<ISqlScriptExecutionService>(
    () => SqlScriptExecutionService(getIt<ProcessService>()),
  );

  getIt.registerLazySingleton<ILocalDestinationService>(
    LocalDestinationService.new,
  );

  getIt.registerLazySingleton<IFtpService>(
    FtpDestinationService.new,
  );

  getIt.registerLazySingleton<GoogleAuthService>(
    () => GoogleAuthService(getIt<ISecureCredentialService>()),
  );

  getIt.registerLazySingleton<IGoogleDriveDestinationService>(
    () => GoogleDriveDestinationService(getIt<GoogleAuthService>()),
  );

  getIt.registerLazySingleton<DropboxAuthService>(
    () => DropboxAuthService(getIt<ISecureCredentialService>()),
  );

  getIt.registerLazySingleton<IDropboxDestinationService>(
    () => DropboxDestinationService(getIt<DropboxAuthService>()),
  );

  getIt.registerLazySingleton<INextcloudDestinationService>(
    NextcloudDestinationService.new,
  );

  getIt.registerLazySingleton<ExecuteSqlServerBackup>(
    () => ExecuteSqlServerBackup(getIt<ISqlServerBackupService>()),
  );

  getIt.registerLazySingleton<ExecuteSybaseBackup>(
    () => ExecuteSybaseBackup(getIt<ISybaseBackupService>()),
  );

  getIt.registerLazySingleton<SendToLocal>(
    () => SendToLocal(getIt<ILocalDestinationService>()),
  );

  getIt.registerLazySingleton<SendToFtp>(
    () => SendToFtp(getIt<IFtpService>()),
  );

  getIt.registerLazySingleton<SendToGoogleDrive>(
    () => SendToGoogleDrive(getIt<IGoogleDriveDestinationService>()),
  );

  getIt.registerLazySingleton<SendToDropbox>(
    () => SendToDropbox(getIt<IDropboxDestinationService>()),
  );

  getIt.registerLazySingleton<SendToNextcloud>(
    () => SendToNextcloud(getIt<INextcloudDestinationService>()),
  );

  getIt.registerLazySingleton<CleanOldBackups>(
    () => CleanOldBackups(
      localService: getIt<ILocalDestinationService>(),
      ftpService: getIt<IFtpService>(),
      googleDriveService: getIt<IGoogleDriveDestinationService>(),
      dropboxService: getIt<IDropboxDestinationService>(),
      nextcloudService: getIt<INextcloudDestinationService>(),
    ),
  );

  getIt.registerLazySingleton<EmailService>(EmailService.new);

  getIt.registerLazySingleton<INotificationService>(
    () => NotificationService(
      emailConfigRepository: getIt<IEmailConfigRepository>(),
      backupLogRepository: getIt<IBackupLogRepository>(),
      emailService: getIt<EmailService>(),
    ),
  );

  getIt.registerLazySingleton<LogService>(
    () => LogService(getIt<IBackupLogRepository>()),
  );

  getIt.registerLazySingleton<SendEmailNotification>(
    () => SendEmailNotification(getIt<INotificationService>()),
  );

  getIt.registerLazySingleton<ConfigureEmail>(
    () => ConfigureEmail(getIt<IEmailConfigRepository>()),
  );

  getIt.registerLazySingleton<TestEmailConfiguration>(
    () => TestEmailConfiguration(getIt<INotificationService>()),
  );

  getIt.registerLazySingleton<BackupOrchestratorService>(
    () => BackupOrchestratorService(
      sqlServerConfigRepository: getIt<ISqlServerConfigRepository>(),
      sybaseConfigRepository: getIt<ISybaseConfigRepository>(),
      postgresConfigRepository: getIt<IPostgresConfigRepository>(),
      backupHistoryRepository: getIt<IBackupHistoryRepository>(),
      backupLogRepository: getIt<IBackupLogRepository>(),
      sqlServerBackupService: getIt<ISqlServerBackupService>(),
      sybaseBackupService: getIt<ISybaseBackupService>(),
      postgresBackupService: getIt<IPostgresBackupService>(),
      compressionService: getIt<ICompressionService>(),
      sqlScriptExecutionService: getIt<ISqlScriptExecutionService>(),
      notificationService: getIt<INotificationService>(),
    ),
  );

  getIt.registerLazySingleton<ISchedulerService>(
    () => SchedulerService(
      scheduleRepository: getIt<IScheduleRepository>(),
      destinationRepository: getIt<IBackupDestinationRepository>(),
      backupHistoryRepository: getIt<IBackupHistoryRepository>(),
      backupLogRepository: getIt<IBackupLogRepository>(),
      backupOrchestratorService: getIt<BackupOrchestratorService>(),
      localDestinationService: getIt<ILocalDestinationService>(),
      sendToFtp: getIt<SendToFtp>(),
      ftpDestinationService: getIt<IFtpService>(),
      googleDriveDestinationService: getIt<IGoogleDriveDestinationService>(),
      dropboxDestinationService: getIt<IDropboxDestinationService>(),
      sendToDropbox: getIt<SendToDropbox>(),
      nextcloudDestinationService: getIt<INextcloudDestinationService>(),
      sendToNextcloud: getIt<SendToNextcloud>(),
      notificationService: getIt<INotificationService>(),
      licenseValidationService: getIt<ILicenseValidationService>(),
    ),
  );

  getIt.registerLazySingleton<ISendFileToDestinationService>(
    () => SendFileToDestinationService(
      localDestinationService: getIt<ILocalDestinationService>(),
      sendToFtp: getIt<SendToFtp>(),
      googleDriveDestinationService: getIt<IGoogleDriveDestinationService>(),
      sendToDropbox: getIt<SendToDropbox>(),
      sendToNextcloud: getIt<SendToNextcloud>(),
      licenseValidationService: getIt<ILicenseValidationService>(),
    ),
  );

  getIt.registerLazySingleton<ServiceHealthChecker>(
    () => ServiceHealthChecker(
      backupHistoryRepository: getIt<IBackupHistoryRepository>(),
      processService: getIt<ProcessService>(),
    ),
  );

  getIt.registerLazySingleton<WindowsEventLogService>(
    () => WindowsEventLogService(
      processService: getIt<ProcessService>(),
    ),
  );

  getIt.registerLazySingleton<ITaskSchedulerService>(
    WindowsTaskSchedulerService.new,
  );

  getIt.registerLazySingleton<AutoUpdateService>(AutoUpdateService.new);

  getIt.registerLazySingleton<CreateSchedule>(
    () => CreateSchedule(
      getIt<IScheduleRepository>(),
      getIt<ISchedulerService>(),
    ),
  );

  getIt.registerLazySingleton<UpdateSchedule>(
    () => UpdateSchedule(
      getIt<IScheduleRepository>(),
      getIt<ISchedulerService>(),
    ),
  );

  getIt.registerLazySingleton<DeleteSchedule>(
    () => DeleteSchedule(getIt<IScheduleRepository>()),
  );

  getIt.registerLazySingleton<ExecuteScheduledBackup>(
    () => ExecuteScheduledBackup(getIt<ISchedulerService>()),
  );

  getIt.registerLazySingleton<BackupProgressProvider>(
    BackupProgressProvider.new,
  );

  getIt.registerFactory<SchedulerProvider>(
    () => SchedulerProvider(
      repository: getIt<IScheduleRepository>(),
      schedulerService: getIt<ISchedulerService>(),
      createSchedule: getIt<CreateSchedule>(),
      updateSchedule: getIt<UpdateSchedule>(),
      deleteSchedule: getIt<DeleteSchedule>(),
      executeBackup: getIt<ExecuteScheduledBackup>(),
      progressProvider: getIt<BackupProgressProvider>(),
    ),
  );

  getIt.registerFactory<LogProvider>(() => LogProvider(getIt<LogService>()));

  getIt.registerFactory<NotificationProvider>(
    () => NotificationProvider(
      emailConfigRepository: getIt<IEmailConfigRepository>(),
      testEmailConfiguration: getIt<TestEmailConfiguration>(),
    ),
  );

  getIt.registerFactory<SqlServerConfigProvider>(
    () => SqlServerConfigProvider(
      getIt<ISqlServerConfigRepository>(),
      getIt<IScheduleRepository>(),
      getIt<ToolVerificationService>(),
    ),
  );

  getIt.registerFactory<SybaseConfigProvider>(
    () => SybaseConfigProvider(
      getIt<ISybaseConfigRepository>(),
      getIt<IScheduleRepository>(),
      getIt<ToolVerificationService>(),
    ),
  );

  getIt.registerFactory<PostgresConfigProvider>(
    () => PostgresConfigProvider(
      getIt<IPostgresConfigRepository>(),
      getIt<IScheduleRepository>(),
    ),
  );

  getIt.registerFactory<DestinationProvider>(
    () => DestinationProvider(
      getIt<IBackupDestinationRepository>(),
      getIt<IScheduleRepository>(),
    ),
  );

  getIt.registerFactory<DashboardProvider>(
    () => DashboardProvider(
      getIt<IBackupHistoryRepository>(),
      getIt<IScheduleRepository>(),
      connectionManager: getIt<ConnectionManager>(),
    ),
  );

  getIt.registerLazySingleton<GoogleAuthProvider>(
    () => GoogleAuthProvider(getIt<GoogleAuthService>()),
  );

  getIt.registerLazySingleton<DropboxAuthProvider>(
    () => DropboxAuthProvider(getIt<DropboxAuthService>()),
  );

  getIt.registerFactory<AutoUpdateProvider>(
    () => AutoUpdateProvider(autoUpdateService: getIt<AutoUpdateService>()),
  );

  getIt.registerFactory<LicenseProvider>(
    () => LicenseProvider(
      validationService: getIt<ILicenseValidationService>(),
      generationService: getIt<LicenseGenerationService>(),
      licenseRepository: getIt<ILicenseRepository>(),
      deviceKeyService: getIt<IDeviceKeyService>(),
    ),
  );

  getIt.registerFactory<WindowsServiceProvider>(
    () => WindowsServiceProvider(getIt<IWindowsServiceService>()),
  );
  getIt.registerFactory<ServerCredentialProvider>(
    () => ServerCredentialProvider(
      getIt<IServerCredentialRepository>(),
      getIt<ISecureCredentialService>(),
    ),
  );
  getIt.registerFactory<ConnectedClientProvider>(
    () => ConnectedClientProvider(getIt<SocketServerService>()),
  );
  getIt.registerFactory<ConnectionLogProvider>(
    () => ConnectionLogProvider(getIt<IConnectionLogRepository>()),
  );
  getIt.registerFactory<RemoteSchedulesProvider>(
    () => RemoteSchedulesProvider(getIt<ConnectionManager>()),
  );
  getIt.registerFactory<RemoteFileTransferProvider>(
    () => RemoteFileTransferProvider(
      getIt<ConnectionManager>(),
      getIt<IBackupDestinationRepository>(),
      getIt<ISendFileToDestinationService>(),
      fileTransferDao: getIt<AppDatabase>().fileTransferDao,
    ),
  );
  getIt.registerFactory<ServerConnectionProvider>(
    () => ServerConnectionProvider(
      getIt<IServerConnectionRepository>(),
      getIt<ConnectionManager>(),
    ),
  );
}

Future<rd.Result<String>> _getOrCreateLicenseSecretKey() async {
  const licenseSecretKey = 'license_secret_key';

  final secureCredentialService = getIt<ISecureCredentialService>();
  final deviceKeyService = getIt<IDeviceKeyService>();

  final existingKeyResult = await secureCredentialService.getPassword(
    key: licenseSecretKey,
  );

  if (existingKeyResult.isSuccess()) {
    final existingKey = existingKeyResult.getOrNull()!;
    if (existingKey.isNotEmpty) {
      LoggerService.info(
        'Using existing license secret key from secure storage',
      );
      return rd.Success(existingKey);
    }
  }

  final deviceKeyResult = await deviceKeyService.getDeviceKey();
  if (deviceKeyResult.isError()) {
    return rd.Failure(deviceKeyResult.exceptionOrNull()!);
  }

  final deviceKey = deviceKeyResult.getOrNull()!;
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final randomBytes = List<int>.generate(32, (i) => (i + timestamp) % 256);
  final combined = '$deviceKey:$timestamp:${randomBytes.join()}';

  final keyBytes = utf8.encode(combined);
  final digest = sha256.convert(keyBytes);
  final generatedKey = digest.toString();

  final storeResult = await secureCredentialService.storePassword(
    key: licenseSecretKey,
    password: generatedKey,
  );

  if (storeResult.isError()) {
    return rd.Failure(storeResult.exceptionOrNull()!);
  }

  LoggerService.info('Generated and stored new license secret key');
  return rd.Success(generatedKey);
}
