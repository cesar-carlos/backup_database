import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/email_notification_profile.dart';
import 'package:backup_database/domain/repositories/i_email_config_repository.dart';
import 'package:backup_database/domain/repositories/i_email_notification_target_repository.dart';
import 'package:result_dart/result_dart.dart' as rd;

class GetEmailNotificationProfiles {
  GetEmailNotificationProfiles({
    required IEmailConfigRepository emailConfigRepository,
    required IEmailNotificationTargetRepository targetRepository,
  }) : _emailConfigRepository = emailConfigRepository,
       _targetRepository = targetRepository;

  final IEmailConfigRepository _emailConfigRepository;
  final IEmailNotificationTargetRepository _targetRepository;

  Future<rd.Result<List<EmailNotificationProfile>>> call() async {
    final configsResult = await _emailConfigRepository.getAll();

    return configsResult.fold(
      (configs) async {
        final profiles = <EmailNotificationProfile>[];

        for (final config in configs) {
          final targetsResult = await _targetRepository.getByConfigId(
            config.id,
          );

          final targets = targetsResult.getOrElse((_) => const []);
          profiles.add(
            EmailNotificationProfile(
              config: config,
              targets: targets,
            ),
          );
        }

        return rd.Success(profiles);
      },
      (failure) => rd.Failure(
        DatabaseFailure(
          message: 'Erro ao carregar perfis de notificacao: $failure',
        ),
      ),
    );
  }
}
