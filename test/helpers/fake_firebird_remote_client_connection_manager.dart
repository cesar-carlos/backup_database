import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';

class FakeConnectedLegacyRemoteConnectionManager extends ConnectionManager {
  FakeConnectedLegacyRemoteConnectionManager()
    : super(serverConnectionRepository: null);

  @override
  bool get isConnected => true;

  @override
  bool get isFirebirdSupported => false;
}

class FakeConnectedFirebirdCapableRemoteConnectionManager
    extends ConnectionManager {
  FakeConnectedFirebirdCapableRemoteConnectionManager()
    : super(serverConnectionRepository: null);

  @override
  bool get isConnected => true;

  @override
  bool get isFirebirdSupported => true;
}
