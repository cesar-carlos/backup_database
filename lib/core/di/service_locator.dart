import 'package:backup_database/core/compatibility/feature_availability_bootstrap.dart';
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
/// 2. Feature availability (compat policy decisions)
/// 3. Domain (repositories, use cases)
/// 4. Infrastructure (external services)
/// 5. Application (orchestrators)
/// 6. Presentation (UI state)
Future<void> setupServiceLocator() async {
  await setupCoreModule(getIt);
  // Antes ficava em `main.dart` como linha solta; movido para dentro do
  // setup do service locator para respeitar "DI lives in DI" e garantir
  // que ambos os pontos de entrada (UI e service mode) tenham o serviço
  // disponível.
  await registerFeatureAvailability(getIt);
  await setupDomainModule(getIt);
  await setupInfrastructureModule(getIt);
  await setupApplicationModule(getIt);
  await setupPresentationModule(getIt);
}

/// Sets up service locator modules for Windows service mode (headless).
///
/// Excludes presentation dependencies to reduce startup surface and avoid
/// unnecessary UI-related initializations in Session 0.
Future<void> setupServiceLocatorForServiceMode() async {
  await setupCoreModule(getIt);
  await registerFeatureAvailability(getIt);
  await setupDomainModule(getIt);
  await setupInfrastructureModule(getIt);
  await setupApplicationModule(getIt);
}
