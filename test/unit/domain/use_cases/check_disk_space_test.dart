import 'dart:io';

import 'package:backup_database/domain/use_cases/storage/check_disk_space.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CheckDiskSpace', () {
    late CheckDiskSpace checkDiskSpace;

    setUp(() {
      checkDiskSpace = CheckDiskSpace();
    });

    test('deve retornar informações do disco', () async {
      if (!await _hasWmic()) {
        return;
      }

      final result = await checkDiskSpace(r'C:\');

      expect(result.isSuccess(), true);

      result.fold((info) {
        expect(info.totalBytes, greaterThan(0));
        expect(info.freeBytes, greaterThanOrEqualTo(0));
        expect(info.usedPercentage, greaterThanOrEqualTo(0));
        expect(info.usedPercentage, lessThanOrEqualTo(100));
      }, (failure) => fail('Não deveria falhar: $failure'));
    });

    test('deve verificar se há espaço suficiente', () async {
      if (!await _hasWmic()) {
        return;
      }

      final result = await checkDiskSpace(r'C:\');

      result.fold((info) {
        expect(info.hasEnoughSpace(1024), true);
        expect(info.hasEnoughSpace(info.freeBytes + 1), false);
      }, (failure) => fail('Não deveria falhar: $failure'));
    });
  });
}

Future<bool> _hasWmic() async {
  try {
    final result = await Process.run('wmic', ['os', 'get', 'caption']);
    return result.exitCode == 0;
  } on Object catch (_) {
    return false;
  }
}
