import 'dart:io';

import 'package:backup_database/core/utils/app_data_directory_resolver.dart';
import 'package:backup_database/core/utils/machine_storage_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveLegacyWindowsUserAppDataDirectory', () {
    test(
      'returns null when not running on Windows',
      () async {
        expect(await resolveLegacyWindowsUserAppDataDirectory(), isNull);
      },
      skip: Platform.isWindows,
    );

    test(
      'returns Roaming Backup Database path on Windows',
      () async {
        final dir = await resolveLegacyWindowsUserAppDataDirectory();
        expect(dir, isNotNull);
        final normalized = p.normalize(dir!.path).toLowerCase();
        expect(normalized, contains('appdata'));
        expect(normalized, contains('backup database'));
      },
      skip: !Platform.isWindows,
    );
  });

  group('resolveMachineRootDirectory', () {
    test(
      r'Windows uses ProgramData\BackupDatabase',
      () async {
        final root = await resolveMachineRootDirectory();
        final normalized = p.normalize(root.path).toLowerCase();
        expect(normalized, contains('programdata'));
        expect(p.basename(root.path).toLowerCase(), 'backupdatabase');
      },
      skip: !Platform.isWindows,
    );

    test(
      'non-Windows resolves to a non-empty documents path',
      () async {
        final root = await resolveMachineRootDirectory();
        expect(root.path.isNotEmpty, isTrue);
      },
      skip: Platform.isWindows,
    );
  });

  group('machine-scope path layout', () {
    test(
      'resolveMachineDataDirectory appends data segment on Windows',
      () async {
        final root = await resolveMachineRootDirectory();
        final data = await resolveMachineDataDirectory();
        expect(
          p.normalize(data.path).toLowerCase(),
          p
              .normalize(
                p.join(root.path, MachineStorageLayout.data),
              )
              .toLowerCase(),
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'resolveMachineStagingBackupsDirectory uses staging/backups on Windows',
      () async {
        final root = await resolveMachineRootDirectory();
        final staging = await resolveMachineStagingBackupsDirectory();
        expect(
          p.normalize(staging.path).toLowerCase(),
          p
              .normalize(
                p.join(
                  root.path,
                  MachineStorageLayout.staging,
                  MachineStorageLayout.stagingBackups,
                ),
              )
              .toLowerCase(),
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'resolveMachineLocksDirectory appends locks',
      () async {
        final root = await resolveMachineRootDirectory();
        final locks = await resolveMachineLocksDirectory();
        expect(
          p.normalize(locks.path).toLowerCase(),
          p
              .normalize(
                p.join(root.path, MachineStorageLayout.locks),
              )
              .toLowerCase(),
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'resolveMachineSecretsDirectory appends secrets',
      () async {
        final root = await resolveMachineRootDirectory();
        final secrets = await resolveMachineSecretsDirectory();
        expect(
          p.normalize(secrets.path).toLowerCase(),
          p
              .normalize(
                p.join(root.path, MachineStorageLayout.secrets),
              )
              .toLowerCase(),
        );
      },
      skip: !Platform.isWindows,
    );
  });

  group('resolveAppDataDirectory', () {
    test(
      'matches resolveMachineRootDirectory',
      () async {
        final a = await resolveAppDataDirectory();
        final b = await resolveMachineRootDirectory();
        expect(p.normalize(a.path), p.normalize(b.path));
      },
    );
  });
}
