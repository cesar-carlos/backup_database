import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:crypto/crypto.dart';

/// Verifica a senha admin do gerador de licenças contra um **hash**
/// armazenado em `LICENSE_ADMIN_PASSWORD_HASH`.
///
/// Antes (auditoria 2026-05-28): a comparação era `entered == plain`
/// onde `plain` vinha de `dotenv.env['LICENSE_ADMIN_PASSWORD']` — senha
/// em claro embutida no `.env` bundled. Múltiplos problemas:
/// - Senha trivialmente extraível de qualquer release.
/// - Comparação não-constant-time (timing attack — irrelevante local,
///   mas má prática).
/// - Sem lockout: brute-force interativo possível.
///
/// Agora:
/// - `LICENSE_ADMIN_PASSWORD` foi descontinuado em favor de
///   `LICENSE_ADMIN_PASSWORD_HASH` no formato
///   `pbkdf2-sha256$<iterations>$<base64salt>$<base64hash>`.
/// - Comparação usa hash + constant-time compare.
/// - Lockout após `maxAttempts` falhas consecutivas, com janela de
///   `lockoutDuration`.
///
/// Para gerar um hash novo, use `scripts/hash_admin_password.dart`.
class AdminPasswordVerifier {
  AdminPasswordVerifier({
    int maxAttempts = 3,
    Duration lockoutDuration = const Duration(seconds: 30),
    DateTime Function() now = _defaultNow,
    math.Random? randomForSalt,
  }) : _maxAttempts = maxAttempts,
       _lockoutDuration = lockoutDuration,
       _now = now,
       _saltRandom = randomForSalt ?? math.Random.secure();

  static DateTime _defaultNow() => DateTime.now();

  final int _maxAttempts;
  final Duration _lockoutDuration;
  final DateTime Function() _now;
  // Mantido para injetar RNG determinístico em testes de `encodeForStorage`
  // (testes não usam mais o estado da instância; a função estática
  // `encodeForStorage` também aceita override). Reservado para futuras
  // operações que precisem gerar salt no fluxo de instância.
  // ignore: unused_field
  final math.Random _saltRandom;

  int _failedAttempts = 0;
  DateTime? _lockedUntil;

  /// Tempo restante de lockout, se houver. Útil para a UI exibir um
  /// countdown ou simplesmente desabilitar o botão.
  Duration? get remainingLockout {
    final until = _lockedUntil;
    if (until == null) return null;
    final remaining = until.difference(_now());
    if (remaining <= Duration.zero) {
      _lockedUntil = null;
      _failedAttempts = 0;
      return null;
    }
    return remaining;
  }

  /// Sucesso → reset; falha → incrementa e (se atingiu o limite) ativa
  /// lockout. Lockout ativo retorna [VerificationResult.lockedOut]
  /// independente do valor da senha.
  VerificationResult verify({
    required String enteredPassword,
    required String storedHash,
  }) {
    final lockoutLeft = remainingLockout;
    if (lockoutLeft != null) {
      return VerificationResult.lockedOut(lockoutLeft);
    }

    if (storedHash.trim().isEmpty) {
      LoggerService.warning(
        'AdminPasswordVerifier: LICENSE_ADMIN_PASSWORD_HASH ausente — '
        'gerador de licenças permanece bloqueado.',
      );
      return const VerificationResult.notConfigured();
    }

    final parsed = _parse(storedHash);
    if (parsed == null) {
      LoggerService.warning(
        'AdminPasswordVerifier: formato invalido em '
        'LICENSE_ADMIN_PASSWORD_HASH. Esperado '
        r'"pbkdf2-sha256$<iters>$<salt>$<hash>".',
      );
      return const VerificationResult.notConfigured();
    }

    final computed = pbkdf2HmacSha256(
      password: enteredPassword,
      salt: parsed.salt,
      iterations: parsed.iterations,
      keyLengthBytes: parsed.hash.length,
    );

    if (_constantTimeEquals(computed, parsed.hash)) {
      _failedAttempts = 0;
      _lockedUntil = null;
      return const VerificationResult.success();
    }

    _failedAttempts++;
    if (_failedAttempts >= _maxAttempts) {
      _lockedUntil = _now().add(_lockoutDuration);
      final n = _failedAttempts;
      _failedAttempts = 0;
      return VerificationResult.lockedOutAfterFailures(n, _lockoutDuration);
    }
    final remainingAttempts = _maxAttempts - _failedAttempts;
    return VerificationResult.invalidPassword(remainingAttempts);
  }

  /// Gera um hash para armazenamento. Use para popular
  /// `LICENSE_ADMIN_PASSWORD_HASH` no `.env` externo.
  static String encodeForStorage({
    required String password,
    int iterations = 200000,
    int saltLengthBytes = 16,
    int keyLengthBytes = 32,
    List<int>? saltOverrideForTesting,
    math.Random? randomForSalt,
  }) {
    final salt =
        saltOverrideForTesting ??
        _randomSalt(saltLengthBytes, randomForSalt ?? math.Random.secure());
    final hash = pbkdf2HmacSha256(
      password: password,
      salt: salt,
      iterations: iterations,
      keyLengthBytes: keyLengthBytes,
    );
    final saltB64 = base64.encode(salt);
    final hashB64 = base64.encode(hash);
    return r'pbkdf2-sha256$'
        '$iterations'
        r'$'
        '$saltB64'
        r'$'
        '$hashB64';
  }

  static _ParsedHash? _parse(String storedHash) {
    final parts = storedHash.trim().split(r'$');
    if (parts.length != 4) return null;
    if (parts[0] != 'pbkdf2-sha256') return null;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations < 1) return null;
    try {
      final salt = base64.decode(parts[2]);
      final hash = base64.decode(parts[3]);
      if (salt.isEmpty || hash.isEmpty) return null;
      return _ParsedHash(
        iterations: iterations,
        salt: salt,
        hash: hash,
      );
    } on Object {
      return null;
    }
  }

  static List<int> _randomSalt(int length, math.Random rng) {
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }

  /// Implementação simples de PBKDF2-HMAC-SHA256 sobre `crypto.Hmac`.
  /// Pública para uso em scripts de hash (`scripts/hash_admin_password.dart`).
  static Uint8List pbkdf2HmacSha256({
    required String password,
    required List<int> salt,
    required int iterations,
    required int keyLengthBytes,
  }) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final out = BytesBuilder(copy: false);
    var block = 1;
    const hLen = 32; // SHA-256
    while (out.length < keyLengthBytes) {
      final saltBlock = Uint8List(salt.length + 4);
      saltBlock.setRange(0, salt.length, salt);
      saltBlock[salt.length] = (block >> 24) & 0xff;
      saltBlock[salt.length + 1] = (block >> 16) & 0xff;
      saltBlock[salt.length + 2] = (block >> 8) & 0xff;
      saltBlock[salt.length + 3] = block & 0xff;

      var u = hmac.convert(saltBlock).bytes;
      final t = Uint8List.fromList(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < hLen; j++) {
          t[j] ^= u[j];
        }
      }
      out.add(t);
      block++;
    }
    return Uint8List.fromList(out.toBytes().sublist(0, keyLengthBytes));
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

class _ParsedHash {
  _ParsedHash({
    required this.iterations,
    required this.salt,
    required this.hash,
  });
  final int iterations;
  final List<int> salt;
  final List<int> hash;
}

enum VerificationOutcome {
  success,
  invalidPassword,
  lockedOut,
  lockedOutAfterFailures,
  notConfigured,
}

class VerificationResult {
  const VerificationResult._(this.outcome, {this.detail});

  const VerificationResult.success() : this._(VerificationOutcome.success);
  const VerificationResult.invalidPassword(int remainingAttempts)
    : this._(
        VerificationOutcome.invalidPassword,
        detail: remainingAttempts,
      );
  const VerificationResult.lockedOut(Duration remaining)
    : this._(VerificationOutcome.lockedOut, detail: remaining);

  /// `failedAttempts` é o N que disparou o lockout; `lockoutDuration` é
  /// quanto tempo o lockout vai durar. Ambos disponíveis em [detail]
  /// como tuple Dart (records, Dart 3+).
  const VerificationResult.lockedOutAfterFailures(
    int failedAttempts,
    Duration lockoutDuration,
  ) : this._(
        VerificationOutcome.lockedOutAfterFailures,
        detail: (
          failedAttempts: failedAttempts,
          lockoutDuration: lockoutDuration,
        ),
      );
  const VerificationResult.notConfigured()
    : this._(VerificationOutcome.notConfigured);

  final VerificationOutcome outcome;

  /// `int` (remainingAttempts) ou `Duration` (lockout), conforme o caso.
  /// `null` para `success`/`notConfigured`.
  final Object? detail;

  bool get isSuccess => outcome == VerificationOutcome.success;
  bool get isLockedOut =>
      outcome == VerificationOutcome.lockedOut ||
      outcome == VerificationOutcome.lockedOutAfterFailures;
  bool get isNotConfigured => outcome == VerificationOutcome.notConfigured;
  bool get isInvalidPassword => outcome == VerificationOutcome.invalidPassword;
}
