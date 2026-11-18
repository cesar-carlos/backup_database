import 'dart:io';

import 'package:backup_database/core/config/environment_loader.dart';
import 'package:flutter_test/flutter_test.dart';

// Only names reach matchers: a failing CI test must never print secret values.
Set<String> forbiddenKeys(String content) {
  final names = <String>{};
  for (final line in content.split('\n')) {
    final text = line.trim();
    if (text.startsWith('#')) continue;
    final separator = text.indexOf('=');
    if (separator < 1) continue;
    final key = text.substring(0, separator).trim();
    final value = text.substring(separator + 1).trim();
    if (value.isNotEmpty &&
        value != '""' &&
        value != "''" &&
        EnvironmentLoader.forbiddenInBundledAssetKeys.contains(key)) {
      names.add(key);
    }
  }
  return names;
}

void main() {
  for (final path in ['.env', '.env.example', '.env.client', '.env.server']) {
    test('$path contains no bundled secrets', () {
      final file = File(path);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Required release configuration',
      );
      expect(
        forbiddenKeys(file.readAsStringSync()),
        isEmpty,
        reason: 'Remove secret values from the repository configuration.',
      );
    });
  }

  test('failure output includes key names but never values', () {
    const secret = 'regression-only-secret-do-not-print';
    final names = forbiddenKeys('LICENSE_ADMIN_PASSWORD=$secret');
    try {
      expect(names, isEmpty);
      fail('Expected the guard to reject the configuration');
    } on TestFailure catch (error) {
      expect(error.message, contains('LICENSE_ADMIN_PASSWORD'));
      expect(error.message, isNot(contains(secret)));
    }
  });
}
