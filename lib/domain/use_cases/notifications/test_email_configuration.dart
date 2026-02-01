import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/services/i_notification_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class TestEmailConfiguration {
  TestEmailConfiguration(this._notificationService);
  final INotificationService _notificationService;

  Future<rd.Result<bool>> call(EmailConfig config) async {
    if (config.recipients.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Nenhum destinatário configurado'),
      );
    }

    final recipient = config.recipients.first;
    final result = await _notificationService.sendTestEmail(
      recipient,
      'Teste de Configuração de Email',
    );

    return result.fold(
      (_) => const rd.Success(true),
      rd.Failure.new,
    );
  }
}
