// Barrel **enxuto** da camada utils. Política: exportamos aqui apenas
// helpers usados de forma transversal pelo app (logger, modo serviço,
// usuário Windows, metadados de tipo de SGBD) — quem precisa de um
// utilitário específico (`ByteFormat`, `RetryUtils`, `ToolPathHelp`,
// etc.) deve importá-lo diretamente para evitar pull-in transitivo
// pesado em pages/widgets que só queriam `LoggerService`.

export 'package:result_dart/result_dart.dart' hide Failure;

export 'database_type_metadata.dart';
export 'logger_service.dart';
export 'service_mode_detector.dart';
export 'windows_user_service.dart';
