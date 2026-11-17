// This administrative CLI prints only paths and non-secret instructions.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:path/path.dart' as p;

/// Generates into a new, access-restricted folder outside the checkout.
/// Never prints private material or modifies the deployed trust configuration.
Future<Directory> prepareKeypair(String keyId, String outputParent) async {
  if (!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(keyId) ||
      keyId == 'ed25519-1') {
    throw ArgumentError(
      'Use a new key ID (letters, numbers, underscore or dash).',
    );
  }
  final parent = Directory(outputParent);
  final resolved = await parent.resolveSymbolicLinks();
  final repository = await Directory.current.resolveSymbolicLinks();
  if (p.equals(resolved, repository) || p.isWithin(repository, resolved)) {
    throw ArgumentError('The output folder must be outside the repository.');
  }
  final directory = await Directory(resolved).createTemp('license-rotation-');
  // Set permissions BEFORE writing any secret. Abort on any permission error.
  if (Platform.isWindows) {
    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final identity = await Process.run(
      p.join(systemRoot, 'System32', 'whoami.exe'),
      ['/user', '/fo', 'csv', '/nh'],
    );
    final sid = RegExp('S-1-5-[0-9-]+')
        .firstMatch(identity.stdout.toString())
        ?.group(0);
    if (identity.exitCode != 0 || sid == null) {
      throw StateError(
        'Could not identify the signing operator. No key written.',
      );
    }
    final permissions = await Process.run(
      p.join(systemRoot, 'System32', 'icacls.exe'),
      [
        directory.path,
        '/inheritance:r',
        '/grant:r',
        '*$sid:(OI)(CI)F',
        '*S-1-5-18:(OI)(CI)F',
      ],
    );
    if (permissions.exitCode != 0) {
      throw StateError('Could not protect the output folder. No key written.');
    }
  } else {
    final permissions = await Process.run('chmod', ['700', directory.path]);
    if (permissions.exitCode != 0) {
      throw StateError('Could not protect the output folder. No key written.');
    }
  }
  final pair = ed.generateKey();
  final publicKey = base64.encode(pair.publicKey.bytes);
  await File(p.join(directory.path, 'signer.env')).writeAsString(
    'BACKUP_DATABASE_LICENSE_ACTIVE_KEY_ID=$keyId\n'
    'BACKUP_DATABASE_LICENSE_PRIVATE_KEY=${base64.encode(pair.privateKey.bytes)}\n',
    flush: true,
  );
  await File(p.join(directory.path, 'public.env')).writeAsString(
    'BACKUP_DATABASE_LICENSE_PUBLIC_KEY=\n'
    'BACKUP_DATABASE_LICENSE_PUBLIC_KEYS=${jsonEncode({keyId: publicKey})}\n'
    'BACKUP_DATABASE_LICENSE_ACTIVE_KEY_ID=$keyId\n',
    flush: true,
  );
  return directory;
}

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run scripts/generate_license_keypair.dart NEW_KEY_ID EXISTING_PRIVATE_FOLDER',
    );
    exitCode = 64;
    return;
  }
  try {
    // Also protect invocation from a working directory outside the checkout.
    final scriptRoot = Directory.fromUri(Platform.script.resolve('../')).path;
    final destination = await Directory(args[1]).resolveSymbolicLinks();
    if (p.equals(scriptRoot, destination) ||
        p.isWithin(scriptRoot, destination)) {
      throw ArgumentError('The output folder must be outside the repository.');
    }
    final directory = await prepareKeypair(args[0], destination);
    print('Prepared protected files in: ${directory.path}');
    print('Only public.env may be copied to release configuration.');
    print(
      'signer.env is private: never commit, attach, or copy to client machines.',
    );
    print('No installed key or existing license was changed.');
  } on Object {
    stderr.writeln(
      'Key preparation failed. Check the key ID, external folder and permissions.',
    );
    exitCode = 1;
  }
}
