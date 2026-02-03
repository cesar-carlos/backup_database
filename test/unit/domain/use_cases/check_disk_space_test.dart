import 'package:backup_database/domain/entities/disk_space_info.dart';
import 'package:backup_database/domain/services/i_storage_checker.dart';
import 'package:backup_database/domain/use_cases/storage/check_disk_space.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class MockIStorageChecker extends Mock implements IStorageChecker {}

void main() {
  group('CheckDiskSpace', () {
    late CheckDiskSpace checkDiskSpace;
    late MockIStorageChecker mockStorageChecker;

    setUp(() {
      mockStorageChecker = MockIStorageChecker();
      checkDiskSpace = CheckDiskSpace(mockStorageChecker);
    });

    test(
      'deve retornar informações do disco quando IStorageChecker retorna sucesso',
      () async {
        const info = DiskSpaceInfo(
          totalBytes: 1000,
          freeBytes: 600,
          usedBytes: 400,
          usedPercentage: 40,
        );
        when(
          () => mockStorageChecker.checkSpace(any()),
        ).thenAnswer((_) async => const rd.Success(info));

        final result = await checkDiskSpace(r'C:\');

        expect(result.isSuccess(), true);
        result.fold(
          (resultInfo) {
            expect(resultInfo.totalBytes, 1000);
            expect(resultInfo.freeBytes, 600);
            expect(resultInfo.usedPercentage, 40);
          },
          (failure) => fail('Não deveria falhar: $failure'),
        );
        verify(() => mockStorageChecker.checkSpace(r'C:\')).called(1);
      },
    );

    test('deve verificar se há espaço suficiente', () async {
      const info = DiskSpaceInfo(
        totalBytes: 2000,
        freeBytes: 1000,
        usedBytes: 1000,
        usedPercentage: 50,
      );
      when(
        () => mockStorageChecker.checkSpace(any()),
      ).thenAnswer((_) async => const rd.Success(info));

      final result = await checkDiskSpace(r'C:\');

      result.fold(
        (resultInfo) {
          expect(resultInfo.hasEnoughSpace(1024), true);
          expect(resultInfo.hasEnoughSpace(resultInfo.freeBytes + 1), false);
        },
        (failure) => fail('Não deveria falhar: $failure'),
      );
    });
  });
}
