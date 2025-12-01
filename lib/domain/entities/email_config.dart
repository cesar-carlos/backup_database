import 'package:uuid/uuid.dart';

class EmailConfig {
  final String id;
  final String senderName;
  final String fromEmail;
  final String fromName;
  final String smtpServer;
  final int smtpPort;
  final String username;
  final String password;
  final bool useSsl;
  final List<String> recipients;
  final bool notifyOnSuccess;
  final bool notifyOnError;
  final bool notifyOnWarning;
  final bool attachLog;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  EmailConfig({
    String? id,
    this.senderName = 'Sistema de Backup',
    this.fromEmail = 'backup@example.com',
    this.fromName = 'Sistema de Backup',
    this.smtpServer = 'smtp.gmail.com',
    this.smtpPort = 587,
    this.username = '',
    this.password = '',
    this.useSsl = true,
    required this.recipients,
    this.notifyOnSuccess = true,
    this.notifyOnError = true,
    this.notifyOnWarning = true,
    this.attachLog = false,
    this.enabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  EmailConfig copyWith({
    String? id,
    String? senderName,
    String? fromEmail,
    String? fromName,
    String? smtpServer,
    int? smtpPort,
    String? username,
    String? password,
    bool? useSsl,
    List<String>? recipients,
    bool? notifyOnSuccess,
    bool? notifyOnError,
    bool? notifyOnWarning,
    bool? attachLog,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmailConfig(
      id: id ?? this.id,
      senderName: senderName ?? this.senderName,
      fromEmail: fromEmail ?? this.fromEmail,
      fromName: fromName ?? this.fromName,
      smtpServer: smtpServer ?? this.smtpServer,
      smtpPort: smtpPort ?? this.smtpPort,
      username: username ?? this.username,
      password: password ?? this.password,
      useSsl: useSsl ?? this.useSsl,
      recipients: recipients ?? this.recipients,
      notifyOnSuccess: notifyOnSuccess ?? this.notifyOnSuccess,
      notifyOnError: notifyOnError ?? this.notifyOnError,
      notifyOnWarning: notifyOnWarning ?? this.notifyOnWarning,
      attachLog: attachLog ?? this.attachLog,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmailConfig &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

