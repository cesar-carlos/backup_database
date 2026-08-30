import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_ftp_service.dart';
import 'package:backup_database/domain/services/i_nextcloud_destination_service.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_labels.dart';
import 'package:flutter/widgets.dart';

const int _ftpMinPort = 1;
const int _ftpMaxPort = 65535;

sealed class DestinationConnectionTestFeedback {
  const DestinationConnectionTestFeedback();
  String get message;
}

final class DestinationConnectionTestSucceeded
    extends DestinationConnectionTestFeedback {
  const DestinationConnectionTestSucceeded(this.message);
  @override
  final String message;
}

final class DestinationConnectionTestFailed
    extends DestinationConnectionTestFeedback {
  const DestinationConnectionTestFailed(this.message);
  @override
  final String message;
}

class DestinationDialogConnectionTesters {
  DestinationDialogConnectionTesters({
    required this.ftpService,
    required this.nextcloudService,
    required this.label,
    String Function(String)? encryptPassword,
  }) : encryptPassword = encryptPassword ?? EncryptionService.encrypt;

  final IFtpService ftpService;
  final INextcloudDestinationService nextcloudService;
  final DestinationDialogLabelBuilder label;
  final String Function(String) encryptPassword;

  Future<DestinationConnectionTestFeedback> testFtpConnection({
    required TextEditingController hostController,
    required TextEditingController portController,
    required TextEditingController usernameController,
    required TextEditingController passwordController,
    required TextEditingController remotePathController,
    required TextEditingController connectionTimeoutSecondsController,
    required TextEditingController uploadTimeoutMinutesController,
    required bool useFtps,
    required bool allowInvalidCertificates,
    required bool enableVerboseLog,
    required bool enableStrongIntegrityValidation,
    required bool enableReadBackValidation,
    required VoidCallback onProbeStarted,
  }) async {
    final missing = _ftpRequiredFieldError(
      hostController: hostController,
      portController: portController,
      usernameController: usernameController,
      passwordController: passwordController,
    );
    if (missing != null) {
      return DestinationConnectionTestFailed(missing);
    }

    onProbeStarted();

    try {
      final port = int.tryParse(portController.text.trim());
      if (port == null || port < _ftpMinPort || port > _ftpMaxPort) {
        return DestinationConnectionTestFailed(
          label(
            'Porta inválida. Use um valor entre $_ftpMinPort e $_ftpMaxPort',
            'Invalid port. Use a value between $_ftpMinPort and $_ftpMaxPort',
          ),
        );
      }

      final config = _ftpConfig(
        host: hostController.text.trim(),
        port: port,
        username: usernameController.text.trim(),
        password: passwordController.text,
        remotePath: remotePathController.text.trim(),
        useFtps: useFtps,
        allowInvalidCertificates: allowInvalidCertificates,
        enableVerboseLog: enableVerboseLog,
        enableStrongIntegrityValidation: enableStrongIntegrityValidation,
        enableReadBackValidation: enableReadBackValidation,
        connectionTimeoutSeconds: _optionalInt(
          connectionTimeoutSecondsController.text,
        ),
        uploadTimeoutMinutes: _optionalInt(
          uploadTimeoutMinutesController.text,
        ),
      );

      final result = await ftpService.testConnection(config);
      return result.fold(_ftpSuccessFeedback, _ftpFailureFeedback);
    } on Object catch (e) {
      return DestinationConnectionTestFailed(
        label('Erro inesperado: $e', 'Unexpected error: $e'),
      );
    }
  }

  Future<DestinationConnectionTestFeedback> testNextcloudConnection({
    required TextEditingController serverUrlController,
    required TextEditingController usernameController,
    required TextEditingController appPasswordController,
    required TextEditingController remotePathController,
    required TextEditingController folderNameController,
    required NextcloudAuthMode authMode,
    required bool allowInvalidCertificates,
    required VoidCallback onProbeStarted,
  }) async {
    final missing = _nextcloudRequiredFieldError(
      serverUrlController: serverUrlController,
      usernameController: usernameController,
      appPasswordController: appPasswordController,
      authMode: authMode,
    );
    if (missing != null) {
      return DestinationConnectionTestFailed(missing);
    }

    onProbeStarted();

    try {
      final config = NextcloudDestinationConfig(
        serverUrl: serverUrlController.text.trim(),
        username: usernameController.text.trim(),
        appPassword: encryptPassword(appPasswordController.text),
        authMode: authMode,
        remotePath: remotePathController.text.trim(),
        folderName: folderNameController.text.trim(),
        allowInvalidCertificates: allowInvalidCertificates,
      );

      final result = await nextcloudService.testConnection(config);
      return result.fold(_nextcloudSuccessFeedback, _nextcloudFailureFeedback);
    } on Object catch (e) {
      return DestinationConnectionTestFailed(
        label('Erro inesperado: $e', 'Unexpected error: $e'),
      );
    }
  }

  String? _ftpRequiredFieldError({
    required TextEditingController hostController,
    required TextEditingController portController,
    required TextEditingController usernameController,
    required TextEditingController passwordController,
  }) {
    if (hostController.text.trim().isEmpty) {
      return label('Servidor FTP é obrigatório', 'FTP server is required');
    }
    if (portController.text.trim().isEmpty) {
      return label('Porta é obrigatória', 'Port is required');
    }
    if (usernameController.text.trim().isEmpty) {
      return label('Usuário é obrigatório', 'Username is required');
    }
    if (passwordController.text.trim().isEmpty) {
      return label('Senha é obrigatória', 'Password is required');
    }
    return null;
  }

  String? _nextcloudRequiredFieldError({
    required TextEditingController serverUrlController,
    required TextEditingController usernameController,
    required TextEditingController appPasswordController,
    required NextcloudAuthMode authMode,
  }) {
    if (serverUrlController.text.trim().isEmpty) {
      return label(
        'URL do Nextcloud é obrigatória',
        'Nextcloud URL is required',
      );
    }
    if (usernameController.text.trim().isEmpty) {
      return label('Usuário é obrigatório', 'Username is required');
    }
    if (appPasswordController.text.trim().isEmpty) {
      return authMode == NextcloudAuthMode.appPassword
          ? label('App Password é obrigatório', 'App Password is required')
          : label(
              'Senha do usuário é obrigatória',
              'User password is required',
            );
    }
    return null;
  }

  FtpDestinationConfig _ftpConfig({
    required String host,
    required int port,
    required String username,
    required String password,
    required String remotePath,
    required bool useFtps,
    required bool allowInvalidCertificates,
    required bool enableVerboseLog,
    required bool enableStrongIntegrityValidation,
    required bool enableReadBackValidation,
    required int? connectionTimeoutSeconds,
    required int? uploadTimeoutMinutes,
  }) {
    return FtpDestinationConfig.fromJson({
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'remotePath': remotePath,
      'useFtps': useFtps,
      'allowInvalidCertificates': allowInvalidCertificates,
      'enableVerboseLog': enableVerboseLog,
      'enableStrongIntegrityValidation': enableStrongIntegrityValidation,
      'enableReadBackValidation': enableReadBackValidation,
      'connectionTimeoutSeconds': connectionTimeoutSeconds,
      'uploadTimeoutMinutes': uploadTimeoutMinutes,
    });
  }

  DestinationConnectionTestFeedback _ftpSuccessFeedback(
    FtpConnectionTestResult testResult,
  ) {
    if (!testResult.ok) {
      return DestinationConnectionTestFailed(
        label(
          'Falha ao conectar ao servidor FTP',
          'Failed to connect to FTP server',
        ),
      );
    }
    final restInfo = _ftpRestInfo(testResult.supportsRestStream);
    final warningInfo = _ftpWarningInfo(testResult);
    return DestinationConnectionTestSucceeded(
      label(
        'Conexão FTP estabelecida com sucesso!$restInfo$warningInfo',
        'FTP connection established successfully!$restInfo$warningInfo',
      ),
    );
  }

  DestinationConnectionTestFeedback _ftpFailureFeedback(Object failure) {
    final message = failureUserMessage(
      failure,
      fallback: label('Erro desconhecido', 'Unknown error'),
    );
    return DestinationConnectionTestFailed(
      label(
        'Erro ao testar conexão FTP:\n$message',
        'Error testing FTP connection:\n$message',
      ),
    );
  }

  String _ftpRestInfo(bool? supportsRestStream) {
    return switch (supportsRestStream) {
      true =>
        '\n${label("Suporta retomada de upload (REST STREAM).", "Supports upload resume (REST STREAM).")}',
      false =>
        '\n${label("Não suporta retomada de upload. "
            "Em caso de interrupção, o envio será reiniciado do zero.", "Does not support upload resume. "
            "If interrupted, upload will restart from the beginning.")}',
      null => '',
    };
  }

  String _ftpWarningInfo(FtpConnectionTestResult testResult) {
    final compatWarnings = <String>[];
    if (testResult.canWrite == false) {
      compatWarnings.add(
        label(
          'Sem permissão de escrita no diretório remoto.',
          'No write permission on remote directory.',
        ),
      );
    }
    if (testResult.canRename == false) {
      compatWarnings.add(
        label(
          'Renomear arquivos não permitido (RNFR/RNTO). '
              'Upload pode falhar na publicação final.',
          'File rename not allowed (RNFR/RNTO). '
              'Upload may fail at final publication.',
        ),
      );
    }
    if (compatWarnings.isEmpty) {
      return '';
    }
    return '\n${label("Avisos:", "Warnings:")} ${compatWarnings.join(" ")}'
        '${compatWarnings.isNotEmpty ? " " : ""}'
        '${label("Consulte o guia de configuração do servidor FTP.", "See FTP server configuration guide.")}';
  }

  DestinationConnectionTestFeedback _nextcloudSuccessFeedback(bool success) {
    if (success) {
      return DestinationConnectionTestSucceeded(
        label(
          'Conexão Nextcloud estabelecida com sucesso!',
          'Nextcloud connection established successfully!',
        ),
      );
    }
    return DestinationConnectionTestFailed(
      label(
        'Falha ao conectar ao servidor Nextcloud',
        'Failed to connect to Nextcloud server',
      ),
    );
  }

  DestinationConnectionTestFeedback _nextcloudFailureFeedback(Object failure) {
    final message = failureUserMessage(
      failure,
      fallback: label('Erro desconhecido', 'Unknown error'),
    );
    return DestinationConnectionTestFailed(
      label(
        'Erro ao testar conexão Nextcloud:\n$message',
        'Error testing Nextcloud connection:\n$message',
      ),
    );
  }

  int? _optionalInt(String raw) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : int.tryParse(trimmed);
  }
}
