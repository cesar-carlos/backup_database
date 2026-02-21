import 'package:uuid/uuid.dart';

class EmailTestAudit {
  EmailTestAudit({
    required this.configId,
    required this.correlationId,
    required this.recipientEmail,
    required this.senderEmail,
    required this.smtpServer,
    required this.smtpPort,
    required this.status,
    this.errorType,
    this.errorMessage,
    this.attempts = 1,
    this.durationMs,
    String? id,
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String configId;
  final String correlationId;
  final String recipientEmail;
  final String senderEmail;
  final String smtpServer;
  final int smtpPort;
  final String status;
  final String? errorType;
  final String? errorMessage;
  final int attempts;
  final int? durationMs;
  final DateTime createdAt;

  bool get isSuccess => status.toLowerCase() == 'success';
}
