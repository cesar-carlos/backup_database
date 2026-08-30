import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/smtp_oauth_state.dart';
import 'package:backup_database/domain/services/i_oauth_smtp_service.dart';
import 'package:flutter/foundation.dart';
import 'package:result_dart/result_dart.dart' as rd;

class NotificationOAuthCoordinator {
  NotificationOAuthCoordinator({
    required this._oauthSmtpService,
    required this._notifyListeners,
    required this._clearError,
    required this._setErrorManual,
  });

  final IOAuthSmtpService _oauthSmtpService;
  final VoidCallback _notifyListeners;
  final void Function() _clearError;
  final void Function(String message) _setErrorManual;

  Future<EmailConfig?> connect({
    required EmailConfig config,
    required SmtpOAuthProvider provider,
  }) {
    return _run(
      () => _oauthSmtpService.connect(
        configId: config.id,
        provider: provider,
      ),
      config: config,
      provider: provider,
    );
  }

  Future<EmailConfig?> reconnect({
    required EmailConfig config,
    required SmtpOAuthProvider provider,
  }) {
    return _run(
      () => _oauthSmtpService.reconnect(
        configId: config.id,
        provider: provider,
      ),
      config: config,
      provider: provider,
    );
  }

  Future<EmailConfig?> _run(
    Future<rd.Result<SmtpOAuthState>> Function() operation, {
    required EmailConfig config,
    required SmtpOAuthProvider provider,
  }) async {
    _clearError();
    _notifyListeners();

    final result = await operation();
    return result.fold(
      (SmtpOAuthState state) {
        _clearError();
        return config.copyWith(
          authMode: provider == SmtpOAuthProvider.google
              ? SmtpAuthMode.oauthGoogle
              : SmtpAuthMode.oauthMicrosoft,
          oauthProvider: provider,
          oauthAccountEmail: state.accountEmail,
          oauthTokenKey: state.tokenKey,
          oauthConnectedAt: state.connectedAt,
        );
      },
      (failure) {
        _setErrorManual(AsyncStateMixin.extractFailureMessage(failure));
        return null;
      },
    );
  }

  Future<EmailConfig> disconnect(EmailConfig config) async {
    _clearError();
    _notifyListeners();

    final tokenKey = config.oauthTokenKey?.trim() ?? '';
    if (tokenKey.isNotEmpty) {
      final result = await _oauthSmtpService.disconnect(tokenKey: tokenKey);
      if (result.isError()) {
        final failure = result.exceptionOrNull();
        if (failure != null) {
          _setErrorManual(AsyncStateMixin.extractFailureMessage(failure));
        }
      }
    }

    return config.copyWith(
      authMode: SmtpAuthMode.password,
      clearOAuthProvider: true,
      clearOAuthAccountEmail: true,
      clearOAuthTokenKey: true,
      clearOAuthConnectedAt: true,
    );
  }
}
