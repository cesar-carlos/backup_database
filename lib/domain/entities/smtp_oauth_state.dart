import 'package:backup_database/domain/entities/email_config.dart';

class SmtpOAuthState {
  const SmtpOAuthState({
    required this.provider,
    required this.accountEmail,
    required this.tokenKey,
    required this.connectedAt,
  });

  final SmtpOAuthProvider provider;
  final String accountEmail;
  final String tokenKey;
  final DateTime connectedAt;
}
