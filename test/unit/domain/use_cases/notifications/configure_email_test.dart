import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/repositories/i_email_config_repository.dart';
import 'package:backup_database/domain/use_cases/notifications/configure_email.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockEmailConfigRepository extends Mock
    implements IEmailConfigRepository {}

void main() {
  late _MockEmailConfigRepository repository;
  late ConfigureEmail useCase;

  final config = EmailConfig(
    id: 'config-1',
    configName: 'SMTP A',
    smtpServer: 'smtp.a.local',
    username: 'user@a.local',
    password: 'secret',
    recipients: const ['legacy@a.local'],
  );

  setUp(() {
    repository = _MockEmailConfigRepository();
    useCase = ConfigureEmail(repository);
  });

  group('ConfigureEmail', () {
    test('updates config when it already exists', () async {
      when(
        () => repository.getById(config.id),
      ).thenAnswer((_) async => rd.Success(config));
      when(
        () => repository.update(config),
      ).thenAnswer((_) async => rd.Success(config));

      final result = await useCase(config);

      expect(result.isSuccess(), isTrue);
      verify(() => repository.getById(config.id)).called(1);
      verify(() => repository.update(config)).called(1);
      verifyNever(() => repository.create(config));
    });

    test('creates config when getById returns failure', () async {
      when(
        () => repository.getById(config.id),
      ).thenAnswer(
        (_) async => const rd.Failure(
          NotFoundFailure(message: 'nao encontrado'),
        ),
      );
      when(
        () => repository.create(config),
      ).thenAnswer((_) async => rd.Success(config));

      final result = await useCase(config);

      expect(result.isSuccess(), isTrue);
      verify(() => repository.getById(config.id)).called(1);
      verify(() => repository.create(config)).called(1);
      verifyNever(() => repository.update(config));
    });
  });
}
