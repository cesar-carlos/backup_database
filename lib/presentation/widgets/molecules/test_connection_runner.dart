import 'package:backup_database/core/errors/failure.dart';

sealed class TestConnectionOutcome {
  const TestConnectionOutcome();
}

final class TestConnectionSucceeded extends TestConnectionOutcome {
  const TestConnectionSucceeded({
    this.databases = const <String>[],
    this.listWarning,
  });

  final List<String> databases;
  final String? listWarning;
}

final class TestConnectionFailed extends TestConnectionOutcome {
  const TestConnectionFailed(this.message);
  final String message;
}

typedef TestConnectionValidate = String? Function();
typedef TestConnectionBuildConfig<TConfig> = TConfig Function();
typedef TestConnectionRunTest<TConfig> =
    Future<TestConnectionOutcome> Function(TConfig config);

String testConnectionUserMessage(
  Object? failure, {
  required String fallback,
}) {
  if (failure == null) {
    return fallback;
  }
  if (failure is Failure) {
    final m = failure.message;
    return m.isNotEmpty ? m : fallback;
  }
  final s = failure.toString();
  return s.isNotEmpty ? s : fallback;
}

class TestConnectionRunner<TConfig> {
  TestConnectionRunner({
    required this.validate,
    required this.buildConfig,
    required this.runTest,
  });

  final TestConnectionValidate validate;
  final TestConnectionBuildConfig<TConfig> buildConfig;
  final TestConnectionRunTest<TConfig> runTest;

  Future<TestConnectionOutcome> execute({
    void Function()? afterValidation,
  }) async {
    final validationError = validate();
    if (validationError != null) {
      return TestConnectionFailed(validationError);
    }
    afterValidation?.call();
    final config = buildConfig();
    return runTest(config);
  }
}
