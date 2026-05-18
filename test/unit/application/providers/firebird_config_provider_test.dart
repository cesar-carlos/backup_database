// mocktail `when(() => ...)` stubs use statement-style closures.
// ignore_for_file: unnecessary_lambdas

import 'package:backup_database/application/providers/firebird_config_provider.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_firebird_config_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/value_objects/firebird_config_enums.dart';
import 'package:backup_database/infrastructure/external/process/tool_verification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockFirebirdRepo extends Mock implements IFirebirdConfigRepository {}

class _MockScheduleRepo extends Mock implements IScheduleRepository {}

class _MockToolVerification extends Mock implements ToolVerificationService {}

FirebirdConfig _sampleFirebird({String? id, String name = 'fb-main'}) {
  return FirebirdConfig(
    id: id,
    name: name,
    host: 'localhost',
    databaseFile: r'C:\data\app.fdb',
    username: 'SYSDBA',
    password: 'pw',
    serverVersionHint: FirebirdServerVersionHint.v30,
    cryptKey: 'ck',
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_sampleFirebird());
    registerFallbackValue(
      Schedule(
        name: 's',
        databaseConfigId: 'x',
        databaseType: DatabaseType.firebird,
        scheduleType: 'daily',
        scheduleConfig: '{}',
        destinationIds: const <String>[],
        backupFolder: 'bf',
      ),
    );
  });

  group('FirebirdConfigProvider', () {
    test('duplicateConfigCopy appends copy suffix and preserves fields', () {
      final repo = _MockFirebirdRepo();
      final schedules = _MockScheduleRepo();
      final tools = _MockToolVerification();
      when(() => repo.getAll()).thenAnswer(
        (_) async => const rd.Success(<FirebirdConfig>[]),
      );
      when(
        () => tools.verifyFirebirdCliTools(),
      ).thenAnswer((_) async => const rd.Success(true));

      final provider = FirebirdConfigProvider(repo, schedules, tools);
      addTearDown(provider.dispose);

      final source = _sampleFirebird(name: 'prod');
      final copy = provider.duplicateConfigCopy(source);

      expect(copy.name, 'prod (cópia)');
      expect(copy.host, source.host);
      expect(copy.databaseFile, source.databaseFile);
      expect(copy.serverVersionHint, source.serverVersionHint);
      expect(copy.serviceManagerMode, source.serviceManagerMode);
      expect(copy.cryptKey, source.cryptKey);
      expect(copy.id, isNot(equals(source.id)));
    });

    test('withEnabled toggles enabled via copyWith', () {
      final repo = _MockFirebirdRepo();
      final schedules = _MockScheduleRepo();
      final tools = _MockToolVerification();
      when(() => repo.getAll()).thenAnswer(
        (_) async => const rd.Success(<FirebirdConfig>[]),
      );
      when(
        () => tools.verifyFirebirdCliTools(),
      ).thenAnswer((_) async => const rd.Success(true));

      final provider = FirebirdConfigProvider(repo, schedules, tools);
      addTearDown(provider.dispose);

      final cfg = _sampleFirebird();
      final disabled = provider.withEnabled(cfg, false);
      expect(disabled.enabled, isFalse);
    });

    test(
      'createConfig invokes verifyFirebirdCliTools before repository.create',
      () async {
        final repo = _MockFirebirdRepo();
        final schedules = _MockScheduleRepo();
        final tools = _MockToolVerification();
        when(() => repo.getAll()).thenAnswer(
          (_) async => const rd.Success(<FirebirdConfig>[]),
        );
        when(
          () => tools.verifyFirebirdCliTools(),
        ).thenAnswer((_) async => const rd.Success(true));
        when(() => repo.create(any())).thenAnswer(
          (_) async => rd.Success(_sampleFirebird(id: 'new-id')),
        );

        final provider = FirebirdConfigProvider(repo, schedules, tools);
        addTearDown(provider.dispose);
        await Future<void>.delayed(Duration.zero);

        final cfg = _sampleFirebird();
        final ok = await provider.createConfig(cfg);

        expect(ok, isTrue);
        verify(() => tools.verifyFirebirdCliTools()).called(1);
        verify(() => repo.create(cfg)).called(1);
      },
    );

    test(
      'createConfig returns false when verifyFirebirdCliTools fails',
      () async {
        final repo = _MockFirebirdRepo();
        final schedules = _MockScheduleRepo();
        final tools = _MockToolVerification();
        when(() => repo.getAll()).thenAnswer(
          (_) async => const rd.Success(<FirebirdConfig>[]),
        );
        when(() => tools.verifyFirebirdCliTools()).thenAnswer(
          (_) async => const rd.Failure(
            ValidationFailure(message: 'gbak missing'),
          ),
        );

        final provider = FirebirdConfigProvider(repo, schedules, tools);
        addTearDown(provider.dispose);
        await Future<void>.delayed(Duration.zero);

        final ok = await provider.createConfig(_sampleFirebird());

        expect(ok, isFalse);
        expect(provider.error, contains('gbak missing'));
        verifyNever(() => repo.create(any()));
      },
    );

    test(
      'updateConfig invokes verifyFirebirdCliTools before repository.update',
      () async {
        final repo = _MockFirebirdRepo();
        final schedules = _MockScheduleRepo();
        final tools = _MockToolVerification();
        final existing = _sampleFirebird(id: 'e1', name: 'old');
        var listed = <FirebirdConfig>[existing];
        when(() => repo.getAll()).thenAnswer((_) async => rd.Success(listed));
        when(
          () => tools.verifyFirebirdCliTools(),
        ).thenAnswer((_) async => const rd.Success(true));
        when(() => repo.update(any())).thenAnswer((invocation) async {
          final next = invocation.positionalArguments.first as FirebirdConfig;
          listed = <FirebirdConfig>[next];
          return rd.Success(next);
        });

        final provider = FirebirdConfigProvider(repo, schedules, tools);
        addTearDown(provider.dispose);
        await Future<void>.delayed(Duration.zero);

        final revised = existing.copyWith(name: 'new');
        final ok = await provider.updateConfig(revised);

        expect(ok, isTrue);
        verify(() => tools.verifyFirebirdCliTools()).called(1);
        verify(() => repo.update(revised)).called(1);
        expect(provider.configs.single.name, 'new');
      },
    );
  });
}
