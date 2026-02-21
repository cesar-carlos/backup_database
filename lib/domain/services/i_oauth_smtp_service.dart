import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/smtp_oauth_state.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class IOAuthSmtpService {
  Future<rd.Result<SmtpOAuthState>> connect({
    required String configId,
    required SmtpOAuthProvider provider,
  });

  Future<rd.Result<SmtpOAuthState>> reconnect({
    required String configId,
    required SmtpOAuthProvider provider,
  });

  Future<rd.Result<void>> disconnect({
    required String tokenKey,
  });

  Future<rd.Result<String>> resolveValidAccessToken({
    required SmtpOAuthProvider provider,
    required String tokenKey,
  });
}
