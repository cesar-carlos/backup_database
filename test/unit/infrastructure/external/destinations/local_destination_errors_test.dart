import 'dart:io';

import 'package:backup_database/infrastructure/external/destinations/local/local_destination_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'access denied identifies executor account rather than UI elevation',
    () {
      final message = LocalDestinationErrors.userFriendly(
        const FileSystemException('denied', r'Z:\backup', OSError('denied', 5)),
      );
      expect(message, contains('conta que executa o backup'));
      expect(message, contains('diferente do usuário'));
    },
  );
  test('missing mapped path explains UNC requirement in service session', () {
    final message = LocalDestinationErrors.userFriendly(
      const FileSystemException('missing', r'Z:\backup', OSError('missing', 3)),
    );
    expect(message, contains(r'\\servidor\pasta'));
    expect(message, contains('unidades mapeadas'));
  });
  for (final code in [53, 67]) {
    test('network error $code identifies share and service permissions', () {
      final message = LocalDestinationErrors.userFriendly(
        FileSystemException(
          'network',
          r'\\server\backup',
          OSError('network', code),
        ),
      );
      expect(message, contains('Compartilhamento de rede indisponível'));
      expect(message, contains('conta do serviço'));
    });
  }
}
