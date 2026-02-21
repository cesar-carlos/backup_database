import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Notification OAuth layering rules', () {
    test('presentation notifications scope must not import infrastructure', () {
      final files = <File>[
        File('lib/presentation/pages/notifications_page.dart'),
        ..._dartFilesIn('lib/presentation/widgets/notifications'),
      ];

      final violations = <String>[];
      for (final file in files) {
        final content = file.readAsStringSync();
        if (content.contains('package:backup_database/infrastructure/')) {
          violations.add(file.path);
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Arquivos de presentation em notificacoes nao devem importar infrastructure diretamente: ${violations.join(', ')}',
      );
    });

    test('application notifications scope must not import infrastructure', () {
      final files = <File>[
        File('lib/application/providers/notification_provider.dart'),
        File('lib/application/services/notification_service.dart'),
      ];

      final violations = <String>[];
      for (final file in files) {
        final content = file.readAsStringSync();
        if (content.contains('package:backup_database/infrastructure/')) {
          violations.add(file.path);
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Arquivos de application em notificacoes nao devem importar infrastructure diretamente: ${violations.join(', ')}',
      );
    });

    test('domain SMTP/OAuth entities must not depend on app, infra or UI', () {
      final files = <File>[
        File('lib/domain/entities/email_config.dart'),
        File('lib/domain/entities/smtp_oauth_state.dart'),
        File('lib/domain/entities/email_test_audit.dart'),
      ];

      final violations = <String>[];
      for (final file in files) {
        final content = file.readAsStringSync();
        if (content.contains('package:backup_database/application/') ||
            content.contains('package:backup_database/infrastructure/') ||
            content.contains('package:backup_database/presentation/')) {
          violations.add(file.path);
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Entidades de dominio SMTP/OAuth nao podem depender de camadas externas: ${violations.join(', ')}',
      );
    });
  });
}

List<File> _dartFilesIn(String directoryPath) {
  final directory = Directory(directoryPath);
  if (!directory.existsSync()) {
    return const <File>[];
  }

  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList(growable: false);
}
