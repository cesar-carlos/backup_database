import 'package:flutter_test/flutter_test.dart';
import 'package:backup_database/domain/use_cases/storage/check_disk_space.dart';

void main() {
  group('CheckDiskSpace', () {
    late CheckDiskSpace checkDiskSpace;

    setUp(() {
      checkDiskSpace = CheckDiskSpace();
    });

    test('deve retornar informações do disco', () async {
      final result = await checkDiskSpace('C:\\');

      expect(result.isSuccess(), true);

      result.fold(
        (info) {
          expect(info.totalBytes, greaterThan(0));
          expect(info.freeBytes, greaterThanOrEqualTo(0));
          expect(info.usedPercentage, greaterThanOrEqualTo(0));
          expect(info.usedPercentage, lessThanOrEqualTo(100));
        },
        (failure) => fail('Não deveria falhar: ${failure.toString()}'),
      );
    });

    test('deve verificar se há espaço suficiente', () async {
      final result = await checkDiskSpace('C:\\');

      result.fold(
        (info) {
          expect(info.hasEnoughSpace(1024), true);
          expect(info.hasEnoughSpace(info.freeBytes + 1), false);
        },
        (failure) => fail('Não deveria falhar: ${failure.toString()}'),
      );
    });
  });
}

