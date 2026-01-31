class ServerException implements Exception {
  const ServerException({required this.message, this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'ServerException: $message (status: $statusCode)';
}

class DatabaseException implements Exception {
  const DatabaseException({required this.message});
  final String message;

  @override
  String toString() => 'DatabaseException: $message';
}

class NetworkException implements Exception {
  const NetworkException({required this.message});
  final String message;

  @override
  String toString() => 'NetworkException: $message';
}

class BackupException implements Exception {
  const BackupException({required this.message, this.databaseName});
  final String message;
  final String? databaseName;

  @override
  String toString() => 'BackupException: $message (database: $databaseName)';
}

class FileSystemException implements Exception {
  const FileSystemException({required this.message, this.path});
  final String message;
  final String? path;

  @override
  String toString() => 'FileSystemException: $message (path: $path)';
}
