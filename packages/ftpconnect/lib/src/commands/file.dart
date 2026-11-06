import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../ftp_exceptions.dart';
import '../ftp_socket.dart';
import '../ftpconnect_base.dart';
import '../utils.dart';

typedef FileProgress = void Function(
  double progressInPercent,
  int totalReceived,
  int fileSize,
);

class FTPFile {
  FTPFile(this._socket);

  final FTPSocket _socket;

  Future<bool> rename(String sOldName, String sNewName) async {
    var sResponse = await _socket.sendCommand('RNFR $sOldName');
    if (sResponse.code != 350) {
      return false;
    }

    sResponse = await _socket.sendCommand('RNTO $sNewName');
    return sResponse.isSuccessCode();
  }

  Future<bool> delete(String? sFilename) async {
    final sResponse = await _socket.sendCommand('DELE $sFilename');
    return sResponse.isSuccessCode();
  }

  Future<bool> exist(String sFilename) async {
    return await size(sFilename) != -1;
  }

  Future<int> size(String? sFilename) async {
    try {
      var sResponse = await _socket.sendCommand('SIZE $sFilename');
      if (!sResponse.isSuccessCode() &&
          _socket.transferType != TransferType.binary) {
        final socketTransferTypeBackup = _socket.transferType;
        await _socket.setTransferType(TransferType.binary);
        sResponse = await _socket.sendCommand('SIZE $sFilename');
        await _socket.setTransferType(socketTransferTypeBackup);
      }
      return int.parse(sResponse.message.replaceAll('213 ', ''));
    } catch (e) {
      return -1;
    }
  }

  Future<bool> download(
    String? sRemoteName,
    File fLocalFile, {
    FileProgress? onProgress,
  }) async {
    final fileSize = await size(sRemoteName);
    if (fileSize < 0) throw FTPConnectException('Remote file unavailable');
    final passive = await _socket.openDataTransferChannel();
    final port = Utils.parsePort(passive.message, _socket.supportIPV6);
    final data = await _socket.openDataSocket(port);
    IOSink? sink;
    final timeout = Duration(seconds: _socket.timeout);
    try {
      final initial = await _socket.sendCommand('RETR $sRemoteName');
      if (initial.code != 125 && initial.code != 150) {
        throw FTPConnectException('Download refused', initial.message);
      }
      sink = fLocalFile.openWrite();
      var received = 0;
      await sink.addStream(data.timeout(timeout).map((chunk) {
        received += chunk.length;
        onProgress?.call(fileSize == 0 ? 100 : received * 100 / fileSize,
            received, fileSize);
        return chunk;
      }));
      await sink.flush().timeout(timeout);
      await sink.close().timeout(timeout);
      sink = null;
      final completed = await _socket.readResponse();
      if ((completed.code != 226 && completed.code != 250) ||
          received != fileSize) {
        throw FTPConnectException('Incomplete download', completed.message);
      }
      return true;
    } catch (_) {
      _socket.abort();
      rethrow;
    } finally {
      _socket.releaseDataSocket(data);
      if (sink != null) {
        try {
          await sink.close().timeout(timeout);
        } catch (_) {}
      }
    }
  }

  Future<bool> upload(
    File file, {
    String remoteName = '',
    FileProgress? onProgress,
  }) =>
      _upload(file, remoteName: remoteName, onProgress: onProgress);

  Future<bool> uploadWithResume(
    File file, {
    required int offset,
    String remoteName = '',
    FileProgress? onProgress,
  }) =>
      _upload(file,
          offset: offset, remoteName: remoteName, onProgress: onProgress);

  Future<bool> _upload(
    File file, {
    int offset = 0,
    String remoteName = '',
    FileProgress? onProgress,
  }) async {
    final size = await file.length();
    if (offset < 0 || offset > size) {
      throw ArgumentError.value(offset, 'offset');
    }
    final passive = await _socket.openDataTransferChannel();
    final port = Utils.parsePort(passive.message, _socket.supportIPV6);
    final data = await _socket.openDataSocket(port);
    Timer? idleTimer;
    final stalled = Completer<void>();
    var timedOut = false;
    void resetIdleTimer() {
      idleTimer?.cancel();
      idleTimer = Timer(Duration(seconds: _socket.timeout), () {
        timedOut = true;
        stalled.completeError(TimeoutException('FTP data transfer stalled'));
        _socket.abort();
      });
    }

    try {
      // REST must immediately precede STOR; success here is 350, not 2xx.
      if (offset > 0) {
        final rest = await _socket.sendCommand('REST $offset');
        if (rest.code != 350) {
          throw FTPConnectException('Resume refused', rest.message);
        }
      }
      final name = remoteName.isEmpty ? p.basename(file.path) : remoteName;
      final initial = await _socket.sendCommand('STOR $name');
      if (initial.code != 125 && initial.code != 150) {
        throw FTPConnectException('Upload refused', initial.message);
      }
      var sent = offset;
      resetIdleTimer();
      final stream = file.openRead(offset).map((chunk) {
        resetIdleTimer();
        sent += chunk.length;
        onProgress?.call(size == 0 ? 100 : sent * 100 / size, sent, size);
        return chunk;
      });
      // Bound a blocked writer and destroy its socket before returning failure.
      await Future.any<void>([
        data.addStream(stream),
        stalled.future,
        _socket.whenAborted
            .then((_) => throw FTPConnectException('Upload aborted')),
      ]);
      await data.flush().timeout(Duration(seconds: _socket.timeout));
      await data.close().timeout(Duration(seconds: _socket.timeout));
      idleTimer?.cancel();
      if (timedOut) throw TimeoutException('FTP data transfer stalled');
      final completed = await _socket.readResponse();
      if (completed.code != 226 && completed.code != 250) {
        throw FTPConnectException('Transfer Error.', completed.message);
      }
      if (sent != size) {
        throw FTPConnectException('Local file changed during upload');
      }
      return true;
    } catch (_) {
      // A late 226/426 must not become the reply to a cleanup/retry command.
      _socket.abort();
      rethrow;
    } finally {
      idleTimer?.cancel();
      _socket.releaseDataSocket(data);
    }
  }
}
