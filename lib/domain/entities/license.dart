import 'package:uuid/uuid.dart';

class License {
  final String id;
  final String deviceKey;
  final String licenseKey;
  final DateTime? expiresAt;
  final List<String> allowedFeatures;
  final DateTime createdAt;
  final DateTime updatedAt;

  License({
    String? id,
    required this.deviceKey,
    required this.licenseKey,
    this.expiresAt,
    required this.allowedFeatures,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  License copyWith({
    String? id,
    String? deviceKey,
    String? licenseKey,
    DateTime? expiresAt,
    List<String>? allowedFeatures,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return License(
      id: id ?? this.id,
      deviceKey: deviceKey ?? this.deviceKey,
      licenseKey: licenseKey ?? this.licenseKey,
      expiresAt: expiresAt ?? this.expiresAt,
      allowedFeatures: allowedFeatures ?? this.allowedFeatures,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  bool get isValid => !isExpired;

  bool hasFeature(String feature) {
    return allowedFeatures.contains(feature);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is License && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
