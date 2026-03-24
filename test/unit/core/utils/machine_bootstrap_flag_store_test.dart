import 'dart:io';

import 'package:backup_database/core/utils/machine_bootstrap_flag_store.dart';
import 'package:backup_database/core/utils/machine_storage_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('machine bootstrap flag store', () {
    test('returns false when marker file does not exist', () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'machine_bootstrap_flag_absent_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final hasFlag = await hasMachineBootstrapFlag(
        fileName: MachineStorageLayout.resetV223Marker,
        machineRootOverride: tempRoot,
      );

      expect(hasFlag, isFalse);
    });

    test(
      'creates and reads marker file in machine-scope config directory',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'machine_bootstrap_flag_present_',
        );
        addTearDown(() async {
          if (await tempRoot.exists()) {
            await tempRoot.delete(recursive: true);
          }
        });

        await markMachineBootstrapFlag(
          fileName: MachineStorageLayout.resetV224Marker,
          machineRootOverride: tempRoot,
        );

        final markerFile = File(
          p.join(
            tempRoot.path,
            MachineStorageLayout.config,
            MachineStorageLayout.resetV224Marker,
          ),
        );
        final hasFlag = await hasMachineBootstrapFlag(
          fileName: MachineStorageLayout.resetV224Marker,
          machineRootOverride: tempRoot,
        );

        expect(await markerFile.exists(), isTrue);
        expect(hasFlag, isTrue);
      },
    );
  });
}
