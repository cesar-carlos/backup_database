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
    _socket.logger.log('Download $sRemoteName to ${fLocalFile.path}');
    var fileSize = await FTPFile(_socket).size(sRemoteName);
    if (fileSize == -1) {
      throw FTPConnectException('Remote File $sRemoteName does not exist!');
    }

    final response = await _socket.openDataTransferChannel();
    _socket.sendCommandWithoutWaitingResponse('RETR $sRemoteName');

    final lPort = Utils.parsePort(response.message, _socket.supportIPV6);
    _socket.logger.log('Opening DataSocket to Port $lPort');
    final dataSocket = await Socket.connect(
      _socket.host,
      lPort,
      timeout: Duration(seconds: _socket.timeout),
    );
    var response2 = await _socket.readResponse();
    var isTransferCompleted = response2.isSuccessCode();
    if (!isTransferCompleted &&
        response2.code != 125 &&
        response2.code != 150) {
      throw FTPConnectException('Connection refused. ', response2.message);
    }

    _socket.logger.log('Start downloading...');
    final sink = fLocalFile.openWrite(mode: FileMode.writeOnly);
    var received = 0;
    await dataSocket.listen((data) {
      sink.add(data);
      if (onProgress != null) {
        received += data.length;
        final percent = ((received / fileSize) * 100).toStringAsFixed(2);
        var percentVal = double.tryParse(percent) ?? 100;
        if (percentVal.isInfinite || percentVal.isNaN) percentVal = 100;
        onProgress(percentVal, received, fileSize);
      }
    }).asFuture();

    await dataSocket.close();
    await sink.flush();
    await sink.close();

    if (!isTransferCompleted) {
      response2 = await _socket.readResponse();
      if (!response2.isSuccessCode()) {
        throw FTPConnectException('Transfer Error.', response2.message);
      }
    }

    _socket.logger.log('File Downloaded!');
    return true;
  }

  Future<bool> upload(
    File fFile, {
    String remoteName = '',
    FileProgress? onProgress,
  }) async {
    _socket.logger.log('Upload File: ${fFile.path}');

    final response = await _socket.openDataTransferChannel();

    var sFilename = remoteName;
    if (sFilename.isEmpty) {
      sFilename = p.basename(fFile.path);
    }

    _socket.sendCommandWithoutWaitingResponse('STOR $sFilename');

    final iPort = Utils.parsePort(response.message, _socket.supportIPV6);
    _socket.logger.log('Opening DataSocket to Port $iPort');
    final dataSocket = await Socket.connect(_socket.host, iPort);
    var response2 = await _socket.readResponse();
    var isTransferCompleted = response2.isSuccessCode();
    if (!isTransferCompleted &&
        response2.code != 125 &&
        response2.code != 150) {
      throw FTPConnectException('Connection refused. ', response2.message);
    }

    _socket.logger.log('Start uploading...');

    var received = 0;
    final fileSize = await fFile.length();

    final readStream = fFile.openRead().transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (data, sink) {
          sink.add(data);
          if (onProgress != null) {
            received += data.length;
            final percent = ((received / fileSize) * 100).toStringAsFixed(2);
            var percentVal = double.tryParse(percent) ?? 100;
            if (percentVal.isInfinite || percentVal.isNaN) percentVal = 100;
            onProgress(percentVal, received, fileSize);
          }
        },
      ),
    );

    await dataSocket.addStream(readStream);
    await dataSocket.flush();
    await dataSocket.close();

    if (!isTransferCompleted) {
      response2 = await _socket.readResponse();
      if (!response2.isSuccessCode()) {
        throw FTPConnectException('Transfer Error.', response2.message);
      }
    }

    _socket.logger.log('File Uploaded!');
    return true;
  }

  /// Upload file with resume support (REST + STOR).
  /// [offset] - byte offset to resume from (server must have bytes 0..offset-1).
  /// Progress reports total bytes (offset + sent) over fileSize.
  Future<bool> uploadWithResume(
    File fFile, {
    required int offset,
    String remoteName = '',
    FileProgress? onProgress,
  }) async {
    _socket.logger.log(
      'Upload File with resume: ${fFile.path} from offset $offset',
    );

    final fileSize = await fFile.length();
    if (offset >= fileSize) {
      _socket.logger.log('Offset >= fileSize, nothing to upload');
      return true;
    }

    final restReply = await _socket.sendCommand('REST $offset');
    if (!restReply.isSuccessCode()) {
      throw FTPConnectException(
        'Server does not support REST or refused offset $offset',
        restReply.message,
      );
    }

    final response = await _socket.openDataTransferChannel();

    var sFilename = remoteName;
    if (sFilename.isEmpty) {
      sFilename = p.basename(fFile.path);
    }

    _socket.sendCommandWithoutWaitingResponse('STOR $sFilename');

    final iPort = Utils.parsePort(response.message, _socket.supportIPV6);
    _socket.logger.log('Opening DataSocket to Port $iPort');
    final dataSocket = await Socket.connect(_socket.host, iPort);
    var response2 = await _socket.readResponse();
    var isTransferCompleted = response2.isSuccessCode();
    if (!isTransferCompleted &&
        response2.code != 125 &&
        response2.code != 150) {
      throw FTPConnectException('Connection refused. ', response2.message);
    }

    _socket.logger.log('Start uploading from offset $offset...');

    var sent = 0;

    final readStream = fFile.openRead(offset).transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (data, sink) {
          sink.add(data);
          if (onProgress != null) {
            sent += data.length;
            final totalReceived = offset + sent;
            final percent =
                ((totalReceived / fileSize) * 100).toStringAsFixed(2);
            var percentVal = double.tryParse(percent) ?? 100;
            if (percentVal.isInfinite || percentVal.isNaN) percentVal = 100;
            onProgress(percentVal, totalReceived, fileSize);
          }
        },
      ),
    );

    await dataSocket.addStream(readStream);
    await dataSocket.flush();
    await dataSocket.close();

    if (!isTransferCompleted) {
      response2 = await _socket.readResponse();
      if (!response2.isSuccessCode()) {
        throw FTPConnectException('Transfer Error.', response2.message);
      }
    }

    _socket.logger.log('File Uploaded (resumed from $offset)!');
    return true;
  }
}
