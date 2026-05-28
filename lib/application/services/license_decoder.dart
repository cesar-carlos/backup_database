import 'dart:convert';

import 'package:backup_database/core/constants/license_constants.dart';
import 'package:backup_database/core/errors/failure.dart' as core;
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/license/ed25519_license_verifier.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:result_dart/result_dart.dart' as rd;

/// Decodifica e verifica licenças Ed25519 v2 — agora com **suporte a
/// rotação de chave**.
///
/// O decoder mantém um mapa `keyId → Ed25519LicenseVerifier`. Durante
/// a verificação:
///
/// 1. Lê `keyId` do payload assinado.
/// 2. Procura o verifier correspondente no mapa.
/// 3. Se não encontrar, **rejeita** (não tenta fallback — caso contrário
///    um atacante poderia atribuir um `keyId` arbitrário esperando que o
///    sistema verificasse com a chave errada).
///
/// Construção típica:
/// - [LicenseDecoder.fromEnv] — lê `BACKUP_DATABASE_LICENSE_PUBLIC_KEY`
///   (legacy, mapeada para [LicenseConstants.keyIdDefault]) e/ou
///   `BACKUP_DATABASE_LICENSE_PUBLIC_KEYS` (mapa JSON
///   `{"ed25519-1": "base64", "ed25519-2": "base64"}`). Os dois podem
///   coexistir; a entrada do JSON tem precedência se houver colisão de
///   `keyId`.
/// - [LicenseDecoder.unavailable] — quando nenhuma chave foi configurada;
///   `decode` devolve `ValidationFailure` consistente.
class LicenseDecoder {
  LicenseDecoder({required Map<String, List<int>> publicKeysByKeyId})
    : _verifiers = _buildVerifiers(publicKeysByKeyId),
      _availabilityFailure = null {
    if (_verifiers.isEmpty) {
      throw ArgumentError(
        'publicKeysByKeyId must not be empty (provide at least one '
        'key bytes entry of $_ed25519PublicKeySize bytes).',
      );
    }
  }

  LicenseDecoder.unavailable({required String message})
    : _verifiers = const {},
      _availabilityFailure = core.ValidationFailure(message: message);

  static const _ed25519PublicKeySize = 32;

  /// `keyId → verifier`. Mapa imutável após construção.
  final Map<String, Ed25519LicenseVerifier> _verifiers;
  final core.ValidationFailure? _availabilityFailure;

  bool get isAvailable => _verifiers.isNotEmpty;

  /// `keyId`s aceitos por este decoder. Útil para diagnóstico e logs.
  Iterable<String> get acceptedKeyIds => _verifiers.keys;

  static Map<String, Ed25519LicenseVerifier> _buildVerifiers(
    Map<String, List<int>> publicKeysByKeyId,
  ) {
    final result = <String, Ed25519LicenseVerifier>{};
    publicKeysByKeyId.forEach((keyId, bytes) {
      if (bytes.length != _ed25519PublicKeySize) {
        throw ArgumentError(
          'Public key for keyId "$keyId" must be exactly '
          '$_ed25519PublicKeySize bytes, got ${bytes.length}.',
        );
      }
      result[keyId] = Ed25519LicenseVerifier(publicKeyBytes: bytes);
    });
    return Map.unmodifiable(result);
  }

  static rd.Result<List<int>> _publicKeyFromEnv() {
    final base64Key = dotenv.env[LicenseConstants.envLicensePublicKey];
    if (base64Key == null || base64Key.trim().isEmpty) {
      return const rd.Failure(
        core.ValidationFailure(
          message:
              'Chave pública de licença não configurada. '
              'Configure BACKUP_DATABASE_LICENSE_PUBLIC_KEY.',
        ),
      );
    }
    try {
      final decoded = base64.decode(base64Key.trim());
      if (decoded.length != _ed25519PublicKeySize) {
        return rd.Failure(
          core.ValidationFailure(
            message:
                'Chave pública inválida. Esperado $_ed25519PublicKeySize bytes, '
                'recebido ${decoded.length} bytes.',
          ),
        );
      }
      return rd.Success(decoded);
    } on Object catch (e) {
      return rd.Failure(
        core.ValidationFailure(
          message: 'Erro ao decodificar chave pública: $e',
        ),
      );
    }
  }

  /// Lê `BACKUP_DATABASE_LICENSE_PUBLIC_KEYS` (JSON
  /// `{"keyId": "base64", ...}`) do env e mescla no mapa final. Falhas
  /// de parse são reportadas como warning **não-fatal** — chaves
  /// válidas continuam carregadas, inválidas são descartadas com log.
  static Map<String, List<int>> _publicKeysMapFromEnv() {
    final raw = dotenv.env[LicenseConstants.envLicensePublicKeys];
    if (raw == null || raw.trim().isEmpty) return const {};
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(raw.trim()) as Map<String, dynamic>;
    } on Object catch (e) {
      LoggerService.warning(
        'BACKUP_DATABASE_LICENSE_PUBLIC_KEYS com JSON inválido: $e. '
        'Ignorando esse env e mantendo apenas chave legacy se houver.',
      );
      return const {};
    }
    final result = <String, List<int>>{};
    decoded.forEach((keyId, value) {
      if (value is! String) {
        LoggerService.warning(
          'BACKUP_DATABASE_LICENSE_PUBLIC_KEYS: entry "$keyId" '
          'não é string base64 — ignorada.',
        );
        return;
      }
      try {
        final bytes = base64.decode(value.trim());
        if (bytes.length != _ed25519PublicKeySize) {
          LoggerService.warning(
            'BACKUP_DATABASE_LICENSE_PUBLIC_KEYS: entry "$keyId" tem '
            '${bytes.length} bytes (esperado $_ed25519PublicKeySize) — '
            'ignorada.',
          );
          return;
        }
        result[keyId] = bytes;
      } on Object catch (e) {
        LoggerService.warning(
          'BACKUP_DATABASE_LICENSE_PUBLIC_KEYS: entry "$keyId" base64 '
          'inválido ($e) — ignorada.',
        );
      }
    });
    return result;
  }

  /// Constrói o decoder a partir do env. Mescla a chave legacy
  /// (`PUBLIC_KEY`, mapeada para `keyIdDefault`) com o mapa
  /// (`PUBLIC_KEYS`). O mapa tem precedência caso o mesmo `keyId`
  /// apareça nos dois.
  static rd.Result<LicenseDecoder> fromEnv() {
    final keys = <String, List<int>>{};

    final legacy = _publicKeyFromEnv();
    legacy.fold(
      (bytes) => keys[LicenseConstants.keyIdDefault] = bytes,
      (_) {},
    );

    final map = _publicKeysMapFromEnv();
    keys.addAll(map);

    if (keys.isEmpty) {
      return rd.Failure(legacy.exceptionOrNull()!);
    }

    return rd.Success(LicenseDecoder(publicKeysByKeyId: keys));
  }

  Future<rd.Result<Map<String, dynamic>>> decode(String licenseKey) async {
    try {
      final availabilityFailure = _availabilityFailure;
      if (availabilityFailure != null) {
        return rd.Failure(availabilityFailure);
      }

      final trimmedKey = licenseKey.trim();
      if (trimmedKey.isEmpty) {
        return const rd.Failure(
          core.ValidationFailure(
            message: 'Chave de licença não pode estar vazia',
          ),
        );
      }

      final licenseBytes = _decodeBase64(trimmedKey);
      if (licenseBytes == null) {
        return const rd.Failure(
          core.ValidationFailure(
            message: 'Chave de licença inválida. Formato base64 incorreto.',
          ),
        );
      }

      final licenseJson = utf8.decode(licenseBytes);
      if (licenseJson.trim().isEmpty) {
        return const rd.Failure(
          core.ValidationFailure(
            message: 'Chave de licença contém dados vazios',
          ),
        );
      }

      final licenseData = _parseJson(licenseJson);
      if (licenseData == null) {
        return const rd.Failure(
          core.ValidationFailure(
            message: 'Chave de licença inválida. Formato JSON incorreto.',
          ),
        );
      }

      final data = licenseData['data'];
      final signature = licenseData['signature'];

      if (data is! Map<String, dynamic> || signature == null) {
        return const rd.Failure(
          core.ValidationFailure(
            message: 'Chave de licença inválida. Estrutura incorreta.',
          ),
        );
      }

      final version = data['licenseVersion'] as int?;
      if (version != LicenseConstants.currentVersion) {
        return rd.Failure(
          core.ValidationFailure(
            message:
                'Versão de licença não suportada. '
                'Esperado v${LicenseConstants.currentVersion}, '
                'recebido v$version. '
                'Solicite uma licença atualizada.',
          ),
        );
      }

      return _verify(data, signature as Object);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao decodificar chave de licença',
        e,
        stackTrace,
      );
      return const rd.Failure(
        core.ValidationFailure(
          message:
              'Erro ao processar chave de licença. '
              'Verifique se a chave está correta.',
        ),
      );
    }
  }

  List<int>? _decodeBase64(String input) {
    try {
      final decoded = base64.decode(input);
      return decoded.isEmpty ? null : decoded;
    } on Object {
      return null;
    }
  }

  Map<String, dynamic>? _parseJson(String input) {
    try {
      return jsonDecode(input) as Map<String, dynamic>;
    } on Object {
      return null;
    }
  }

  rd.Result<Map<String, dynamic>> _verify(
    Map<String, dynamic> data,
    Object signature,
  ) {
    final validationResult = _validateRequiredFields(data);
    if (validationResult.isError()) {
      return validationResult;
    }

    final signatureBytesResult = _decodeSignature(signature);
    if (signatureBytesResult.isError()) {
      return rd.Failure(signatureBytesResult.exceptionOrNull()!);
    }

    final signatureBytes = signatureBytesResult.getOrNull()!;
    final dataJson = jsonEncode(data);
    final messageBytes = utf8.encode(dataJson);

    // `keyId` já foi validado em `_validateRequiredFields` (trim + non-empty);
    // aqui usamos para localizar o verifier correto. Se o keyId não está
    // em `_verifiers`, **rejeita** (não tenta fallback — qualquer chave
    // que o cliente conheça precisa estar declarada explicitamente).
    final keyId = (data['keyId'] as String).trim();
    final verifier = _verifiers[keyId];
    if (verifier == null) {
      LoggerService.warning(
        'Licença usa keyId "$keyId" desconhecido. '
        'Aceitos: ${_verifiers.keys.join(", ")}.',
      );
      return rd.Failure(
        core.ValidationFailure(
          message:
              'keyId desconhecido: "$keyId". '
              'Atualize a configuração de chaves públicas ou solicite '
              'uma licença com keyId suportado.',
        ),
      );
    }

    if (!verifier.verify(
      messageBytes: messageBytes,
      signatureBytes: signatureBytes,
    )) {
      LoggerService.warning(
        'Assinatura Ed25519 de licença inválida (keyId=$keyId)',
      );
      return const rd.Failure(
        core.ValidationFailure(message: 'Assinatura de licença inválida'),
      );
    }

    final timeValidationResult = _validateTimeWindow(data);
    if (timeValidationResult.isError()) {
      return timeValidationResult;
    }

    return rd.Success(_normalizePayload(data));
  }

  rd.Result<Map<String, dynamic>> _validateRequiredFields(
    Map<String, dynamic> data,
  ) {
    // Antes este método tinha 4 cópias verbatim do pattern
    // `if (field == null || field.trim().isEmpty) return Failure(...)`.
    // Agora delega a `_requireString` que retorna a string trimada ou
    // uma `Failure` semântica.
    final deviceKey = _requireString(data, 'deviceKey');
    if (deviceKey == null) return _missingField('deviceKey');

    final issuedAt = _requireString(data, 'issuedAt');
    if (issuedAt == null) return _missingField('issuedAt');
    final issuedAtParseResult = _parseIsoDate(issuedAt, 'issuedAt');
    if (issuedAtParseResult.isError()) {
      return rd.Failure(issuedAtParseResult.exceptionOrNull()!);
    }

    final keyId = _requireString(data, 'keyId');
    if (keyId == null) return _missingField('keyId');
    // Note: validação de "keyId conhecido" agora acontece em `_verify`
    // contra o mapa `_verifiers` — permite rotação de chave sem mudar
    // este método. Aqui só garantimos que o campo é uma string não-vazia.

    final issuer = _requireString(data, 'issuer');
    if (issuer == null) return _missingField('issuer');
    if (issuer != LicenseConstants.issuerDefault) {
      return rd.Failure(
        core.ValidationFailure(
          message:
              'Emissor inválido. Esperado "${LicenseConstants.issuerDefault}", '
              'recebido "$issuer".',
        ),
      );
    }

    final allowedFeatures = data['allowedFeatures'];
    if (allowedFeatures is! List) {
      return const rd.Failure(
        core.ValidationFailure(
          message: 'Campo obrigatório ausente ou inválido: allowedFeatures',
        ),
      );
    }
    final featureValues = allowedFeatures.whereType<String>().toList();
    if (featureValues.length != allowedFeatures.length) {
      return const rd.Failure(
        core.ValidationFailure(
          message: 'allowedFeatures deve conter somente strings',
        ),
      );
    }
    final hasEmptyFeature = featureValues.any(
      (feature) => feature.trim().isEmpty,
    );
    if (hasEmptyFeature) {
      return const rd.Failure(
        core.ValidationFailure(
          message: 'allowedFeatures não pode conter valores vazios',
        ),
      );
    }

    return const rd.Success({});
  }

  /// Helper de validação: extrai e valida que [fieldName] em [data] é uma
  /// string não-vazia (após trim). Retorna a string trimada em caso de
  /// sucesso, ou `null` (que o caller traduz via `_missingField`).
  String? _requireString(Map<String, dynamic> data, String fieldName) {
    final value = data[fieldName] as String?;
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  /// Builder de `Failure` para campo obrigatório ausente. Centralizado
  /// para garantir que a mensagem seja consistente em todas as
  /// validações (antes era hard-coded em cada `if` block).
  rd.Result<Map<String, dynamic>> _missingField(String fieldName) {
    return rd.Failure(
      core.ValidationFailure(
        message: 'Campo obrigatório ausente: $fieldName',
      ),
    );
  }

  /// Helper de parsing de data ISO-8601. Centraliza o pattern
  /// `try { DateTime.parse(value); } on Object { return Failure(...); }`
  /// que aparecia 3 vezes (issuedAt, notBefore, expiresAt).
  rd.Result<DateTime> _parseIsoDate(String value, String fieldName) {
    try {
      return rd.Success(DateTime.parse(value));
    } on Object {
      return rd.Failure(
        core.ValidationFailure(
          message: 'Campo $fieldName com formato inválido',
        ),
      );
    }
  }

  rd.Result<List<int>> _decodeSignature(Object signature) {
    if (signature is! String) {
      return const rd.Failure(
        core.ValidationFailure(
          message: 'Assinatura deve ser uma string base64',
        ),
      );
    }

    try {
      final signatureBytes = base64.decode(signature);
      if (signatureBytes.isEmpty) {
        return const rd.Failure(
          core.ValidationFailure(message: 'Assinatura vazia'),
        );
      }
      return rd.Success(signatureBytes);
    } on Object {
      return const rd.Failure(
        core.ValidationFailure(
          message: 'Assinatura inválida. Formato base64 incorreto.',
        ),
      );
    }
  }

  rd.Result<Map<String, dynamic>> _validateTimeWindow(
    Map<String, dynamic> data,
  ) {
    final now = DateTime.now();

    // Antes este método tinha 2 try/catch quase idênticos para `notBefore`
    // e `expiresAt`. Agora delega o parsing ao `_parseIsoDate` (já usado
    // no `_validateRequiredFields` para `issuedAt`) e mantém apenas a
    // lógica específica de cada janela.
    final notBefore = data['notBefore'] as String?;
    if (notBefore != null && notBefore.isNotEmpty) {
      final parseResult = _parseIsoDate(notBefore, 'notBefore');
      if (parseResult.isError()) {
        return rd.Failure(parseResult.exceptionOrNull()!);
      }
      final notBeforeDt = parseResult.getOrThrow();
      if (now.isBefore(notBeforeDt)) {
        return rd.Failure(
          core.ValidationFailure(
            message:
                'Licença ainda não válida. Válida a partir de: '
                '${notBeforeDt.toIso8601String()}',
          ),
        );
      }
    }

    final expiresAt = data['expiresAt'] as String?;
    if (expiresAt != null && expiresAt.isNotEmpty) {
      final parseResult = _parseIsoDate(expiresAt, 'expiresAt');
      if (parseResult.isError()) {
        return rd.Failure(parseResult.exceptionOrNull()!);
      }
      final expiresAtDt = parseResult.getOrThrow();
      if (now.isAfter(expiresAtDt)) {
        return rd.Failure(
          core.ValidationFailure(
            message: 'Licença expirada em: ${expiresAtDt.toIso8601String()}',
          ),
        );
      }
    }

    return const rd.Success({});
  }

  Map<String, dynamic> _normalizePayload(Map<String, dynamic> data) {
    final normalizedFeatures = (data['allowedFeatures'] as List)
        .map((feature) => (feature as String).trim())
        .toSet()
        .toList();
    return {
      'deviceKey': data['deviceKey'] as String,
      'expiresAt': data['expiresAt'] as String?,
      'notBefore': data['notBefore'] as String?,
      'allowedFeatures': normalizedFeatures,
      'keyId': data['keyId'] as String,
    };
  }
}
