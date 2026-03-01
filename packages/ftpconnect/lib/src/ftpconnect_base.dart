import 'dart:io';

import 'package:path/path.dart' as p;

import 'commands/directory.dart';
import 'commands/file.dart';
import 'ftp_entry.dart';
import 'ftp_exceptions.dart';
import 'ftp_reply.dart';
import 'ftp_socket.dart';
import 'logger.dart';
import 'utils.dart';

class FTPConnect {
  FTPConnect(
    String host, {
    int? port,
    String user = 'anonymous',
    String pass = '',
    bool showLog = false,
    SecurityType securityType = SecurityType.ftp,
    Logger? logger,
    int timeout = 30,
  })  : _user = user,
        _pass = pass {
    port ??= securityType == SecurityType.ftps ? 990 : 21;
    _socket = FTPSocket(
      host,
      port,
      securityType,
      logger ?? Logger(isEnabled: showLog),
      timeout,
    );
  }

  final String _user;
  final String _pass;
  late FTPSocket _socket;

  set transferMode(TransferMode pTransferMode) {
    _socket.transferMode = pTransferMode;
  }

  set listCommand(ListCommand pListCommand) {
    _socket.listCommand = pListCommand;
  }

  set supportIPV6(bool pSupportIPV6) {
    _socket.supportIPV6 = pSupportIPV6;
  }

  Future<void> setTransferType(TransferType pTransferType) async {
    if (_socket.transferType == pTransferType) return;
    await _socket.setTransferType(pTransferType);
  }

  Future<bool> connect() => _socket.connect(_user, _pass);

  Future<bool> disconnect() => _socket.disconnect();

  Future<FTPReply> sendCustomCommand(String pCmd) => _socket.sendCommand(pCmd);

  Future<bool> uploadFile(
    File fFile, {
    String sRemoteName = '',
    FileProgress? onProgress,
  }) {
    return FTPFile(_socket).upload(
      fFile,
      remoteName: sRemoteName,
      onProgress: onProgress,
    );
  }

  /// Upload file with resume support (REST + STOR).
  /// Use when server supports REST STREAM and partial file exists remotely.
  Future<bool> uploadFileWithResume(
    File fFile, {
    required int offset,
    String sRemoteName = '',
    FileProgress? onProgress,
  }) {
    return FTPFile(_socket).uploadWithResume(
      fFile,
      offset: offset,
      remoteName: sRemoteName,
      onProgress: onProgress,
    );
  }

  Future<bool> downloadFile(
    String? sRemoteName,
    File fFile, {
    FileProgress? onProgress,
  }) {
    return FTPFile(_socket).download(
      sRemoteName,
      fFile,
      onProgress: onProgress,
    );
  }

  Future<bool> makeDirectory(String sDirectory) {
    return FTPDirectory(_socket).makeDirectory(sDirectory);
  }

  Future<bool> deleteEmptyDirectory(String? sDirectory) {
    return FTPDirectory(_socket).deleteEmptyDirectory(sDirectory);
  }

  Future<bool> deleteDirectory(String sDirectory) async {
    final currentDir = await currentDirectory();
    if (!await changeDirectory(sDirectory)) {
      throw FTPConnectException(
        "Couldn't change directory to $sDirectory",
      );
    }
    final dirContent = await listDirectoryContent();
    for (final entry in dirContent) {
      if (entry.type == FTPEntryType.file) {
        if (!await deleteFile(entry.name)) {
          throw FTPConnectException(
            "Couldn't delete file ${entry.name}",
          );
        }
      } else {
        if (!await deleteDirectory(entry.name)) {
          throw FTPConnectException(
            "Couldn't delete folder ${entry.name}",
          );
        }
      }
    }
    await changeDirectory(currentDir);
    return deleteEmptyDirectory(sDirectory);
  }

  Future<bool> changeDirectory(String? sDirectory) {
    return FTPDirectory(_socket).changeDirectory(sDirectory);
  }

  Future<String> currentDirectory() {
    return FTPDirectory(_socket).currentDirectory();
  }

  Future<List<FTPEntry>> listDirectoryContent() {
    return FTPDirectory(_socket).directoryContent();
  }

  Future<List<String>> listDirectoryContentOnlyNames() {
    return FTPDirectory(_socket).directoryContentNames();
  }

  Future<bool> rename(String sOldName, String sNewName) {
    return FTPFile(_socket).rename(sOldName, sNewName);
  }

  Future<bool> deleteFile(String? sFilename) {
    return FTPFile(_socket).delete(sFilename);
  }

  Future<bool> existFile(String sFilename) {
    return FTPFile(_socket).exist(sFilename);
  }

  Future<int> sizeFile(String sFilename) {
    return FTPFile(_socket).size(sFilename);
  }

  Future<bool> uploadFileWithRetry(
    File fileToUpload, {
    String pRemoteName = '',
    int pRetryCount = 1,
    FileProgress? onProgress,
  }) {
    Future<bool> uploadFileRetry() async {
      return uploadFile(
        fileToUpload,
        sRemoteName: pRemoteName,
        onProgress: onProgress,
      );
    }

    return Utils.retryAction(uploadFileRetry, pRetryCount);
  }

  Future<bool> downloadFileWithRetry(
    String pRemoteName,
    File pLocalFile, {
    int pRetryCount = 1,
    FileProgress? onProgress,
  }) {
    Future<bool> downloadFileRetry() async {
      return downloadFile(
        pRemoteName,
        pLocalFile,
        onProgress: onProgress,
      );
    }

    return Utils.retryAction(downloadFileRetry, pRetryCount);
  }

  Future<bool> downloadDirectory(
    String pRemoteDir,
    Directory pLocalDir, {
    int pRetryCount = 1,
  }) {
    Future<bool> downloadDir(String? pRemoteDir, Directory pLocalDir) async {
      await pLocalDir.create(recursive: true);

      if (!await changeDirectory(pRemoteDir)) {
        throw FTPConnectException(
          'Cannot download directory',
          '$pRemoteDir not found or inaccessible !',
        );
      }
      final dirContent = await listDirectoryContent();
      for (final entry in dirContent) {
        if (entry.type == FTPEntryType.file) {
          final localFile = File(p.join(pLocalDir.path, entry.name));
          await downloadFile(entry.name, localFile);
        } else if (entry.type == FTPEntryType.dir) {
          final localDir =
              await Directory(p.join(pLocalDir.path, entry.name))
                  .create(recursive: true);
          await downloadDir(entry.name, localDir);
          await changeDirectory('..');
        }
      }
      return true;
    }

    Future<bool> downloadDirRetry() async {
      return downloadDir(pRemoteDir, pLocalDir);
    }

    return Utils.retryAction(downloadDirRetry, pRetryCount);
  }

  Future<bool> checkFolderExistence(String pDirectory) {
    return changeDirectory(pDirectory);
  }

  Future<bool> createFolderIfNotExist(String pDirectory) async {
    if (!await checkFolderExistence(pDirectory)) {
      return makeDirectory(pDirectory);
    }
    return true;
  }
}

enum ListCommand { nlst, list, mlsd }

enum TransferType { auto, ascii, binary }

enum TransferMode { active, passive }

enum SecurityType { ftp, ftps, ftpes }

extension CommandListTypeEnum on ListCommand {
  String get describeEnum => toString().substring(toString().indexOf('.') + 1);
}
