import 'package:backup_database/application/providers/oauth_provider_base.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_auth_service.dart';

class DropboxOAuthConfig {
  const DropboxOAuthConfig({required this.clientId, this.clientSecret});

  factory DropboxOAuthConfig.fromJson(Map<String, dynamic> json) {
    return DropboxOAuthConfig(
      clientId: json['clientId'] as String,
      clientSecret: json['clientSecret'] as String?,
    );
  }
  final String clientId;
  final String? clientSecret;

  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'clientSecret': clientSecret,
  };
}

class DropboxAuthProvider
    extends OAuthProviderBase<DropboxOAuthConfig, DropboxAuthResult> {
  DropboxAuthProvider(this._authService)
    : super(
        oauthConfigPrefsKey: _oauthConfigKey,
        serviceLabel: 'Dropbox',
        initializeService: _authService.initialize,
        signInService: _authService.signIn,
        signInSilentlyService: _authService.signInSilently,
        signOutService: _authService.signOut,
      );

  final DropboxAuthService _authService;

  static const _oauthConfigKey = 'dropbox_oauth_config';

  // ===========================================================================
  // Hooks abstratos
  // ===========================================================================

  @override
  bool get isSignedIn => _authService.isSignedIn;

  @override
  String? get currentUserEmailFromService => _authService.currentUserEmail;

  @override
  String? get accessTokenFromService => _authService.accessToken;

  @override
  DropboxOAuthConfig buildConfig({
    required String clientId,
    String? clientSecret,
  }) {
    return DropboxOAuthConfig(clientId: clientId, clientSecret: clientSecret);
  }

  @override
  Map<String, dynamic> configToJson(DropboxOAuthConfig config) =>
      config.toJson();

  @override
  DropboxOAuthConfig configFromJson(Map<String, dynamic> json) =>
      DropboxOAuthConfig.fromJson(json);

  @override
  String emailOf(DropboxAuthResult result) => result.email;

  @override
  String clientIdOf(DropboxOAuthConfig config) => config.clientId;

  @override
  String? clientSecretOf(DropboxOAuthConfig config) => config.clientSecret;

  /// API legada usada pelo `DropboxDestinationService`.
  DropboxAuthResult? getAuthResult() {
    if (!_authService.isSignedIn) return null;
    return DropboxAuthResult(
      accessToken: _authService.accessToken!,
      email: _authService.currentUserEmail!,
    );
  }
}
