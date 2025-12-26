class ServerException implements Exception {
  final String message;
  final int? statusCode;

  const ServerException({required this.message, this.statusCode});

  @override
  String toString() => 'ServerException: $message (status: $statusCode)';
}

class DatabaseException implements Exception {
  final String message;

  const DatabaseException({required this.message});

  @override
  String toString() => 'DatabaseException: $message';
}

class NetworkException implements Exception {
  final String message;

  const NetworkException({required this.message});

  @override
  String toString() => 'NetworkException: $message';
}

class BackupException implements Exception {
  final String message;
  final String? databaseName;

  const BackupException({required this.message, this.databaseName});

  @override
  String toString() => 'BackupException: $message (database: $databaseName)';
}

class FileSystemException implements Exception {
  final String message;
  final String? path;

  const FileSystemException({required this.message, this.path});

  @override
  String toString() => 'FileSystemException: $message (path: $path)';
}
