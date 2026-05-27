import 'package:backup_database/application/providers/oauth_provider_base.dart';
import 'package:backup_database/infrastructure/external/google/google_auth_service.dart';

class GoogleOAuthConfig {
  const GoogleOAuthConfig({
    required this.clientId,
    this.clientSecret,
  });

  factory GoogleOAuthConfig.fromJson(Map<String, dynamic> json) {
    return GoogleOAuthConfig(
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

class GoogleAuthProvider
    extends OAuthProviderBase<GoogleOAuthConfig, GoogleAuthResult> {
  GoogleAuthProvider(this._authService)
    : super(
        oauthConfigPrefsKey: _oauthConfigKey,
        serviceLabel: 'Google',
        initializeService: _authService.initialize,
        signInService: _authService.signIn,
        signInSilentlyService: _authService.signInSilently,
        signOutService: _authService.signOut,
      );

  final GoogleAuthService _authService;

  static const _oauthConfigKey = 'google_oauth_config';

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
  GoogleOAuthConfig buildConfig({
    required String clientId,
    String? clientSecret,
  }) {
    return GoogleOAuthConfig(clientId: clientId, clientSecret: clientSecret);
  }

  @override
  Map<String, dynamic> configToJson(GoogleOAuthConfig config) =>
      config.toJson();

  @override
  GoogleOAuthConfig configFromJson(Map<String, dynamic> json) =>
      GoogleOAuthConfig.fromJson(json);

  @override
  String emailOf(GoogleAuthResult result) => result.email;

  @override
  String clientIdOf(GoogleOAuthConfig config) => config.clientId;

  @override
  String? clientSecretOf(GoogleOAuthConfig config) => config.clientSecret;

  /// API legada usada pelo `GoogleDriveDestinationService`. Continua
  /// retornando `null` quando não há sessão ativa.
  GoogleAuthResult? getAuthResult() {
    if (!_authService.isSignedIn) return null;
    return GoogleAuthResult(
      accessToken: _authService.accessToken!,
      email: _authService.currentUserEmail!,
    );
  }
}
