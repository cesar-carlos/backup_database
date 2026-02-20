import 'package:uuid/uuid.dart';

class EmailNotificationTarget {
  EmailNotificationTarget({
    required this.emailConfigId,
    required this.recipientEmail,
    String? id,
    this.notifyOnSuccess = true,
    this.notifyOnError = true,
    this.notifyOnWarning = true,
    this.enabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String emailConfigId;
  final String recipientEmail;
  final bool notifyOnSuccess;
  final bool notifyOnError;
  final bool notifyOnWarning;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  EmailNotificationTarget copyWith({
    String? id,
    String? emailConfigId,
    String? recipientEmail,
    bool? notifyOnSuccess,
    bool? notifyOnError,
    bool? notifyOnWarning,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmailNotificationTarget(
      id: id ?? this.id,
      emailConfigId: emailConfigId ?? this.emailConfigId,
      recipientEmail: recipientEmail ?? this.recipientEmail,
      notifyOnSuccess: notifyOnSuccess ?? this.notifyOnSuccess,
      notifyOnError: notifyOnError ?? this.notifyOnError,
      notifyOnWarning: notifyOnWarning ?? this.notifyOnWarning,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmailNotificationTarget &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
