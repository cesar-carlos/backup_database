import 'package:uuid/uuid.dart';

enum SmtpAuthMode {
  password('password'),
  oauthGoogle('oauth_google'),
  oauthMicrosoft('oauth_microsoft')
  ;

  const SmtpAuthMode(this.value);
  final String value;

  bool get isOAuth => this != SmtpAuthMode.password;

  static SmtpAuthMode fromValue(String raw) {
    for (final mode in values) {
      if (mode.value == raw) {
        return mode;
      }
    }
    return SmtpAuthMode.password;
  }
}

enum SmtpOAuthProvider {
  google('google'),
  microsoft('microsoft')
  ;

  const SmtpOAuthProvider(this.value);
  final String value;

  static SmtpOAuthProvider? fromValue(String raw) {
    for (final provider in values) {
      if (provider.value == raw) {
        return provider;
      }
    }
    return null;
  }
}

class EmailConfig {
  EmailConfig({
    required this.recipients,
    String? id,
    this.configName = 'Configuracao SMTP',
    this.senderName = 'Sistema de Backup',
    this.fromEmail = 'backup@example.com',
    this.fromName = 'Sistema de Backup',
    this.smtpServer = 'smtp.gmail.com',
    this.smtpPort = 587,
    this.username = '',
    this.password = '',
    this.useSsl = true,
    this.authMode = SmtpAuthMode.password,
    this.oauthProvider,
    this.oauthAccountEmail,
    this.oauthTokenKey,
    this.oauthConnectedAt,
    this.notifyOnSuccess = true,
    this.notifyOnError = true,
    this.notifyOnWarning = true,
    this.attachLog = false,
    this.enabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();
  final String id;
  final String configName;
  final String senderName;
  final String fromEmail;
  final String fromName;
  final String smtpServer;
  final int smtpPort;
  final String username;
  final String password;
  final bool useSsl;
  final SmtpAuthMode authMode;
  final SmtpOAuthProvider? oauthProvider;
  final String? oauthAccountEmail;
  final String? oauthTokenKey;
  final DateTime? oauthConnectedAt;
  final List<String> recipients;
  final bool notifyOnSuccess;
  final bool notifyOnError;
  final bool notifyOnWarning;
  final bool attachLog;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  EmailConfig copyWith({
    String? id,
    String? configName,
    String? senderName,
    String? fromEmail,
    String? fromName,
    String? smtpServer,
    int? smtpPort,
    String? username,
    String? password,
    bool? useSsl,
    SmtpAuthMode? authMode,
    SmtpOAuthProvider? oauthProvider,
    String? oauthAccountEmail,
    String? oauthTokenKey,
    DateTime? oauthConnectedAt,
    bool clearOAuthProvider = false,
    bool clearOAuthAccountEmail = false,
    bool clearOAuthTokenKey = false,
    bool clearOAuthConnectedAt = false,
    List<String>? recipients,
    bool? notifyOnSuccess,
    bool? notifyOnError,
    bool? notifyOnWarning,
    bool? attachLog,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmailConfig(
      id: id ?? this.id,
      configName: configName ?? this.configName,
      senderName: senderName ?? this.senderName,
      fromEmail: fromEmail ?? this.fromEmail,
      fromName: fromName ?? this.fromName,
      smtpServer: smtpServer ?? this.smtpServer,
      smtpPort: smtpPort ?? this.smtpPort,
      username: username ?? this.username,
      password: password ?? this.password,
      useSsl: useSsl ?? this.useSsl,
      authMode: authMode ?? this.authMode,
      oauthProvider: clearOAuthProvider
          ? null
          : (oauthProvider ?? this.oauthProvider),
      oauthAccountEmail: clearOAuthAccountEmail
          ? null
          : (oauthAccountEmail ?? this.oauthAccountEmail),
      oauthTokenKey: clearOAuthTokenKey
          ? null
          : (oauthTokenKey ?? this.oauthTokenKey),
      oauthConnectedAt: clearOAuthConnectedAt
          ? null
          : (oauthConnectedAt ?? this.oauthConnectedAt),
      recipients: recipients ?? this.recipients,
      notifyOnSuccess: notifyOnSuccess ?? this.notifyOnSuccess,
      notifyOnError: notifyOnError ?? this.notifyOnError,
      notifyOnWarning: notifyOnWarning ?? this.notifyOnWarning,
      attachLog: attachLog ?? this.attachLog,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmailConfig &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
