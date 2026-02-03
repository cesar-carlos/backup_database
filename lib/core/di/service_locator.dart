import 'package:backup_database/core/di/application_module.dart';
import 'package:backup_database/core/di/core_module.dart';
import 'package:backup_database/core/di/domain_module.dart';
import 'package:backup_database/core/di/infrastructure_module.dart';
import 'package:backup_database/core/di/presentation_module.dart';
import 'package:get_it/get_it.dart';

final GetIt getIt = GetIt.instance;

/// Sets up all service locator modules.
///
/// This function initializes all dependency injection modules
/// in the correct order to ensure dependencies are available
/// when needed.
///
/// Order of initialization:
/// 1. Core (fundamental services)
/// 2. Domain (repositories, use cases)
/// 3. Infrastructure (external services)
/// 4. Application (orchestrators)
/// 5. Presentation (UI state)
Future<void> setupServiceLocator() async {
  await setupCoreModule(getIt);
  await setupDomainModule(getIt);
  await setupInfrastructureModule(getIt);
  await setupApplicationModule(getIt);
  await setupPresentationModule(getIt);
}
