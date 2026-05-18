// mocktail `when(() => ...)` stubs use statement-style closures.
// ignore_for_file: unnecessary_lambdas

import 'package:backup_database/application/providers/database_config_provider_base.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_database_config_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockRepo extends Mock
    implements IDatabaseConfigRepository<PostgresConfig> {}

class _MockScheduleRepo extends Mock implements IScheduleRepository {}

class _TestPgProvider extends DatabaseConfigProviderBase<PostgresConfig> {
  _TestPgProvider(
    IDatabaseConfigRepository<PostgresConfig> repository,
    IScheduleRepository scheduleRepository,
  ) : super(
        repository: repository,
        scheduleRepository: scheduleRepository,
      );

  int verifyToolsCallCount = 0;

  @override
  Future<void> verifyToolsOrThrow() async {
    verifyToolsCallCount++;
  }

  @override
  PostgresConfig duplicateConfigCopy(PostgresConfig source) {
    return PostgresConfig(
      name: '${source.name} (cópia)',
      host: source.host,
      database: source.database,
      username: source.username,
      password: source.password,
      port: source.port,
      enabled: source.enabled,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  PostgresConfig withEnabled(PostgresConfig config, bool enabled) =>
      config.copyWith(enabled: enabled);
}

PostgresConfig _samplePostgres({String? id, String name = 'main'}) {
  return PostgresConfig(
    id: id,
    name: name,
    host: 'localhost',
    database: DatabaseName('db'),
    username: 'u',
    password: 'p',
    port: PortNumber(5432),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_samplePostgres());
    registerFallbackValue(
      Schedule(
        name: 's',
        databaseConfigId: 'x',
        databaseType: DatabaseType.postgresql,
        scheduleType: 'daily',
        scheduleConfig: '{}',
        destinationIds: const <String>[],
        backupFolder: 'bf',
      ),
    );
  });

  group('DatabaseConfigProviderBase', () {
    test('loadConfigs does not invoke verifyToolsOrThrow', () async {
      final repo = _MockRepo();
      final schedules = _MockScheduleRepo();
      when(() => repo.getAll()).thenAnswer(
        (_) async => rd.Success(<PostgresConfig>[_samplePostgres()]),
      );

      final provider = _TestPgProvider(repo, schedules);
      await Future<void>.delayed(Duration.zero);
      await provider.loadConfigs();

      expect(provider.verifyToolsCallCount, 0);
      expect(provider.configs, hasLength(1));
      verify(() => repo.getAll()).called(2);
    });

    test(
      'createConfig invokes verifyToolsOrThrow then repository.create',
      () async {
        final repo = _MockRepo();
        final schedules = _MockScheduleRepo();
        when(() => repo.getAll()).thenAnswer(
          (_) async => const rd.Success(<PostgresConfig>[]),
        );
        when(
          () => repo.create(any()),
        ).thenAnswer((_) async => rd.Success(_samplePostgres(id: 'new-id')));

        final provider = _TestPgProvider(repo, schedules);
        await Future<void>.delayed(Duration.zero);

        final cfg = _samplePostgres();
        final ok = await provider.createConfig(cfg);

        expect(ok, isTrue);
        expect(provider.verifyToolsCallCount, 1);
        verify(() => repo.create(cfg)).called(1);
      },
    );

    test(
      'createConfig returns false when reload after create fails',
      () async {
        final repo = _MockRepo();
        final schedules = _MockScheduleRepo();
        var getAllCalls = 0;
        when(() => repo.getAll()).thenAnswer((_) async {
          getAllCalls++;
          if (getAllCalls == 1) {
            return const rd.Success(<PostgresConfig>[]);
          }
          return rd.Failure(Exception('reload failed'));
        });
        when(() => repo.create(any())).thenAnswer(
          (_) async => rd.Success(_samplePostgres(id: 'after-create')),
        );

        final provider = _TestPgProvider(repo, schedules);
        await Future<void>.delayed(Duration.zero);

        final ok = await provider.createConfig(_samplePostgres());

        expect(ok, isFalse);
        expect(provider.error, contains('Erro ao criar configuração'));
        expect(provider.error, contains('reload failed'));
        verify(() => repo.create(any())).called(1);
      },
    );

    test('deleteConfig blocks when schedules are linked', () async {
      final repo = _MockRepo();
      final schedules = _MockScheduleRepo();
      when(() => repo.getAll()).thenAnswer(
        (_) async => const rd.Success(<PostgresConfig>[]),
      );
      final linked = <Schedule>[
        Schedule(
          name: 'linked',
          databaseConfigId: 'cfg-1',
          databaseType: DatabaseType.postgresql,
          scheduleType: 'daily',
          scheduleConfig: '{}',
          destinationIds: const <String>[],
          backupFolder: 'bf',
        ),
      ];
      when(
        () => schedules.getByDatabaseConfig('cfg-1'),
      ).thenAnswer((_) async => rd.Success(linked));
      when(() => repo.delete(any())).thenAnswer(
        (_) async => const rd.Success(unit),
      );

      final provider = _TestPgProvider(repo, schedules);
      await Future<void>.delayed(Duration.zero);

      final ok = await provider.deleteConfig('cfg-1');

      expect(ok, isFalse);
      verifyNever(() => repo.delete(any()));
    });

    test('deleteConfig removes config when no linked schedules', () async {
      final repo = _MockRepo();
      final schedules = _MockScheduleRepo();
      final cfg = _samplePostgres(id: 'del1');
      when(() => repo.getAll()).thenAnswer(
        (_) async => rd.Success(<PostgresConfig>[cfg]),
      );
      when(
        () => schedules.getByDatabaseConfig('del1'),
      ).thenAnswer((_) async => const rd.Success(<Schedule>[]));
      when(() => repo.delete('del1')).thenAnswer(
        (_) async => const rd.Success(unit),
      );

      final provider = _TestPgProvider(repo, schedules);
      await Future<void>.delayed(Duration.zero);

      expect(provider.configs, hasLength(1));

      final ok = await provider.deleteConfig('del1');

      expect(ok, isTrue);
      verify(() => schedules.getByDatabaseConfig('del1')).called(1);
      verify(() => repo.delete('del1')).called(1);
      expect(provider.configs, isEmpty);
    });

    test('deleteConfig returns false when repository.delete fails', () async {
      final repo = _MockRepo();
      final schedules = _MockScheduleRepo();
      final cfg = _samplePostgres(id: 'bad-del');
      when(() => repo.getAll()).thenAnswer(
        (_) async => rd.Success(<PostgresConfig>[cfg]),
      );
      when(
        () => schedules.getByDatabaseConfig('bad-del'),
      ).thenAnswer((_) async => const rd.Success(<Schedule>[]));
      when(() => repo.delete('bad-del')).thenAnswer(
        (_) async => rd.Failure(Exception('disk full')),
      );

      final provider = _TestPgProvider(repo, schedules);
      await Future<void>.delayed(Duration.zero);

      final ok = await provider.deleteConfig('bad-del');

      expect(ok, isFalse);
      expect(provider.error, isNotNull);
      expect(provider.configs, hasLength(1));
    });

    test(
      'deleteConfig uses generic message when schedule lookup error is not '
      'a domain Failure',
      () async {
        final repo = _MockRepo();
        final schedules = _MockScheduleRepo();
        when(() => repo.getAll()).thenAnswer(
          (_) async => const rd.Success(<PostgresConfig>[]),
        );
        when(() => schedules.getByDatabaseConfig('y')).thenAnswer(
          (_) async => rd.Failure(Exception('opaque')),
        );

        final provider = _TestPgProvider(repo, schedules);
        await Future<void>.delayed(Duration.zero);

        final ok = await provider.deleteConfig('y');

        expect(ok, isFalse);
        expect(
          provider.error,
          equals(
            'Não foi possível validar dependências antes da exclusão.',
          ),
        );
      },
    );

    test('getConfigById returns loaded config or null', () async {
      final repo = _MockRepo();
      final schedules = _MockScheduleRepo();
      final cfg = _samplePostgres(id: 'g1');
      when(() => repo.getAll()).thenAnswer(
        (_) async => rd.Success(<PostgresConfig>[cfg]),
      );

      final provider = _TestPgProvider(repo, schedules);
      await Future<void>.delayed(Duration.zero);

      expect(provider.getConfigById('g1')?.id, 'g1');
      expect(provider.getConfigById('missing'), isNull);
    });

    test('duplicateConfig uses duplicateConfigCopy via createConfig', () async {
      final repo = _MockRepo();
      final schedules = _MockScheduleRepo();
      when(() => repo.getAll()).thenAnswer(
        (_) async => const rd.Success(<PostgresConfig>[]),
      );
      PostgresConfig? captured;
      when(() => repo.create(any())).thenAnswer((invocation) async {
        captured = invocation.positionalArguments.first as PostgresConfig;
        return rd.Success(captured!);
      });

      final provider = _TestPgProvider(repo, schedules);
      await Future<void>.delayed(Duration.zero);

      final source = _samplePostgres(name: 'orig');
      await provider.duplicateConfig(source);

      expect(captured, isNotNull);
      expect(captured!.name, 'orig (cópia)');
      expect(provider.verifyToolsCallCount, 1);
    });

    test(
      'updateConfig invokes verifyToolsOrThrow then repository.update',
      () async {
        final repo = _MockRepo();
        final schedules = _MockScheduleRepo();
        final existing = _samplePostgres(id: 'e1', name: 'old');
        var listed = <PostgresConfig>[existing];
        when(() => repo.getAll()).thenAnswer((_) async => rd.Success(listed));
        when(() => repo.update(any())).thenAnswer((invocation) async {
          final next = invocation.positionalArguments.first as PostgresConfig;
          listed = <PostgresConfig>[next];
          return rd.Success(next);
        });

        final provider = _TestPgProvider(repo, schedules);
        await Future<void>.delayed(Duration.zero);

        final revised = existing.copyWith(name: 'new');
        final ok = await provider.updateConfig(revised);

        expect(ok, isTrue);
        expect(provider.verifyToolsCallCount, 1);
        verify(() => repo.update(revised)).called(1);
        expect(provider.configs.single.name, 'new');
      },
    );

    test('createConfig returns false when repository.create fails', () async {
      final repo = _MockRepo();
      final schedules = _MockScheduleRepo();
      when(() => repo.getAll()).thenAnswer(
        (_) async => const rd.Success(<PostgresConfig>[]),
      );
      when(() => repo.create(any())).thenAnswer(
        (_) async => rd.Failure(Exception('persist failed')),
      );

      final provider = _TestPgProvider(repo, schedules);
      await Future<void>.delayed(Duration.zero);

      final ok = await provider.createConfig(_samplePostgres());

      expect(ok, isFalse);
      expect(provider.error, isNotNull);
      expect(provider.error, contains('persist failed'));
    });

    test('updateConfig returns false when repository.update fails', () async {
      final repo = _MockRepo();
      final schedules = _MockScheduleRepo();
      final cfg = _samplePostgres(id: 'u9', name: 'n');
      when(() => repo.getAll()).thenAnswer(
        (_) async => rd.Success(<PostgresConfig>[cfg]),
      );
      when(() => repo.update(any())).thenAnswer(
        (_) async => rd.Failure(Exception('row missing')),
      );

      final provider = _TestPgProvider(repo, schedules);
      await Future<void>.delayed(Duration.zero);

      final ok = await provider.updateConfig(cfg.copyWith(name: 'x'));

      expect(ok, isFalse);
      expect(provider.error, isNotNull);
      expect(provider.error, contains('row missing'));
    });

    test(
      'updateConfig returns false when reload after update fails',
      () async {
        final repo = _MockRepo();
        final schedules = _MockScheduleRepo();
        final existing = _samplePostgres(id: 'ur1', name: 'a');
        var getAllCalls = 0;
        when(() => repo.getAll()).thenAnswer((_) async {
          getAllCalls++;
          if (getAllCalls == 1) {
            return rd.Success(<PostgresConfig>[existing]);
          }
          return rd.Failure(Exception('reload after update'));
        });
        when(() => repo.update(any())).thenAnswer(
          (_) async => rd.Success(existing.copyWith(name: 'b')),
        );

        final provider = _TestPgProvider(repo, schedules);
        await Future<void>.delayed(Duration.zero);

        final ok = await provider.updateConfig(existing.copyWith(name: 'b'));

        expect(ok, isFalse);
        expect(provider.error, contains('Erro ao atualizar configuração'));
        expect(provider.error, contains('reload after update'));
        verify(() => repo.update(any())).called(1);
      },
    );

    test('toggleEnabled returns false when id is missing', () async {
      final repo = _MockRepo();
      final schedules = _MockScheduleRepo();
      when(() => repo.getAll()).thenAnswer(
        (_) async => const rd.Success(<PostgresConfig>[]),
      );

      final provider = _TestPgProvider(repo, schedules);
      await Future<void>.delayed(Duration.zero);

      final ok = await provider.toggleEnabled('missing', false);

      expect(ok, isFalse);
      expect(provider.error, equals(provider.configNotFoundMessage));
      verifyNever(() => repo.update(any()));
    });

    test(
      'toggleEnabled calls update with withEnabled when id exists',
      () async {
        final repo = _MockRepo();
        final schedules = _MockScheduleRepo();
        final cfg = _samplePostgres(id: 't1');
        when(() => repo.getAll()).thenAnswer(
          (_) async => rd.Success(<PostgresConfig>[cfg]),
        );
        PostgresConfig? updatedArg;
        when(() => repo.update(any())).thenAnswer((invocation) async {
          updatedArg = invocation.positionalArguments.first as PostgresConfig;
          return rd.Success(updatedArg!);
        });

        final provider = _TestPgProvider(repo, schedules);
        await Future<void>.delayed(Duration.zero);

        final ok = await provider.toggleEnabled('t1', false);

        expect(ok, isTrue);
        expect(updatedArg, isNotNull);
        expect(updatedArg!.enabled, isFalse);
        expect(provider.verifyToolsCallCount, 1);
      },
    );

    test(
      'deleteConfig sets manual error when schedule dependency check fails',
      () async {
        final repo = _MockRepo();
        final schedules = _MockScheduleRepo();
        when(() => repo.getAll()).thenAnswer(
          (_) async => const rd.Success(<PostgresConfig>[]),
        );
        when(() => schedules.getByDatabaseConfig('x')).thenAnswer(
          (_) async => const rd.Failure(
            ValidationFailure(message: 'sched indisponível'),
          ),
        );

        final provider = _TestPgProvider(repo, schedules);
        await Future<void>.delayed(Duration.zero);

        final ok = await provider.deleteConfig('x');

        expect(ok, isFalse);
        expect(provider.error, contains('sched indisponível'));
        verifyNever(() => repo.delete(any()));
      },
    );

    test(
      'activeConfigs and inactiveConfigs partition by enabled flag',
      () async {
        final repo = _MockRepo();
        final schedules = _MockScheduleRepo();
        when(() => repo.getAll()).thenAnswer(
          (_) async => rd.Success(<PostgresConfig>[
            _samplePostgres(id: 'on', name: 'a'),
            _samplePostgres(id: 'off', name: 'b').copyWith(enabled: false),
          ]),
        );

        final provider = _TestPgProvider(repo, schedules);
        await Future<void>.delayed(Duration.zero);

        expect(provider.activeConfigs, hasLength(1));
        expect(provider.activeConfigs.single.id, 'on');
        expect(provider.inactiveConfigs, hasLength(1));
        expect(provider.inactiveConfigs.single.id, 'off');
      },
    );

    test('initial loadConfigs sets error when getAll fails', () async {
      final repo = _MockRepo();
      final schedules = _MockScheduleRepo();
      when(() => repo.getAll()).thenAnswer(
        (_) async => rd.Failure(Exception('db off')),
      );

      final provider = _TestPgProvider(repo, schedules);
      await Future<void>.delayed(Duration.zero);

      expect(provider.error, isNotNull);
      expect(provider.error, contains('db off'));
    });

    test('recordConnectionTest stores snapshot per config id', () async {
      final repo = _MockRepo();
      final schedules = _MockScheduleRepo();
      when(() => repo.getAll()).thenAnswer(
        (_) async => const rd.Success(<PostgresConfig>[]),
      );

      final provider = _TestPgProvider(repo, schedules);
      await Future<void>.delayed(Duration.zero);

      expect(provider.connectionTestSnapshotFor('c1'), isNull);
      provider.recordConnectionTest('c1', success: true);
      final s1 = provider.connectionTestSnapshotFor(
        'c1',
      );
      expect(s1, isNotNull);
      expect(s1!.success, isTrue);
      provider.recordConnectionTest('c1', success: false);
      expect(provider.connectionTestSnapshotFor('c1')!.success, isFalse);
    });

    test('updateConfig clears connection test snapshot for that id', () async {
      final repo = _MockRepo();
      final schedules = _MockScheduleRepo();
      final cfg = _samplePostgres(id: 'u1');
      when(() => repo.getAll()).thenAnswer(
        (_) async => rd.Success(<PostgresConfig>[cfg]),
      );
      when(() => repo.update(any())).thenAnswer(
        (_) async => rd.Success(cfg.copyWith(name: 'renamed')),
      );
      when(() => schedules.getByDatabaseConfig(any())).thenAnswer(
        (_) async => const rd.Success(<Schedule>[]),
      );

      final provider = _TestPgProvider(repo, schedules);
      await Future<void>.delayed(Duration.zero);

      provider.recordConnectionTest('u1', success: true);
      expect(provider.connectionTestSnapshotFor('u1'), isNotNull);

      final ok = await provider.updateConfig(cfg.copyWith(name: 'renamed'));
      expect(ok, isTrue);
      expect(provider.connectionTestSnapshotFor('u1'), isNull);
    });

    test('deleteConfig clears connection test snapshot', () async {
      final repo = _MockRepo();
      final schedules = _MockScheduleRepo();
      final cfg = _samplePostgres(id: 'd1');
      when(() => repo.getAll()).thenAnswer(
        (_) async => rd.Success(<PostgresConfig>[cfg]),
      );
      when(
        () => repo.delete('d1'),
      ).thenAnswer((_) async => const rd.Success(unit));
      when(() => schedules.getByDatabaseConfig('d1')).thenAnswer(
        (_) async => const rd.Success(<Schedule>[]),
      );

      final provider = _TestPgProvider(repo, schedules);
      await Future<void>.delayed(Duration.zero);

      provider.recordConnectionTest('d1', success: true);
      expect(provider.connectionTestSnapshotFor('d1'), isNotNull);

      final ok = await provider.deleteConfig('d1');
      expect(ok, isTrue);
      expect(provider.connectionTestSnapshotFor('d1'), isNull);
    });
  });
}
