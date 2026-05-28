import 'package:uuid/uuid.dart';

class License {
  License({
    required this.deviceKey,
    required this.licenseKey,
    required this.allowedFeatures,
    String? id,
    this.expiresAt,
    this.notBefore,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();
  final String id;
  final String deviceKey;
  final String licenseKey;
  final DateTime? expiresAt;

  /// Janela "not yet valid" — licença só passa a valer a partir deste
  /// timestamp. Antes era validado apenas no decode (descartado depois);
  /// agora persistido para que reabrir o app antes do horário ainda
  /// rejeite a licença (defesa contra "renove agora, ative depois").
  final DateTime? notBefore;
  final List<String> allowedFeatures;
  final DateTime createdAt;
  final DateTime updatedAt;

  License copyWith({
    String? id,
    String? deviceKey,
    String? licenseKey,
    DateTime? expiresAt,
    DateTime? notBefore,
    List<String>? allowedFeatures,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return License(
      id: id ?? this.id,
      deviceKey: deviceKey ?? this.deviceKey,
      licenseKey: licenseKey ?? this.licenseKey,
      expiresAt: expiresAt ?? this.expiresAt,
      notBefore: notBefore ?? this.notBefore,
      allowedFeatures: allowedFeatures ?? this.allowedFeatures,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Licença ainda não entrou em vigor (janela `notBefore` no futuro).
  bool get isNotYetValid {
    if (notBefore == null) return false;
    return DateTime.now().isBefore(notBefore!);
  }

  bool get isValid => !isExpired && !isNotYetValid;

  bool hasFeature(String feature) {
    return allowedFeatures.contains(feature);
  }

  /// Identidade da licença = `licenseKey` (determinístico, derivado do
  /// payload assinado). O `id` é gerado por `Uuid().v4()` na construção
  /// — usá-lo como chave de igualdade fazia duas leituras consecutivas
  /// do mesmo registro virarem objetos "diferentes".
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is License &&
          runtimeType == other.runtimeType &&
          licenseKey == other.licenseKey &&
          deviceKey == other.deviceKey;

  @override
  int get hashCode => Object.hash(licenseKey, deviceKey);
}
