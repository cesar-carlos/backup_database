import 'package:backup_database/infrastructure/external/oauth/oauth_config_store.dart';

class GoogleOAuthConfigStore extends OAuthConfigStore {
  GoogleOAuthConfigStore(super.credentials)
    : super(storageKey: key, label: 'Google');
  static const key = 'google_oauth_config';
}
