import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../ftp_entry.dart';
import '../ftp_exceptions.dart';
import '../ftp_socket.dart';
import '../ftpconnect_base.dart';
import '../utils.dart';

class FTPDirectory {
  FTPDirectory(this._socket);

  final FTPSocket _socket;

  Future<bool> makeDirectory(String sName) async {
    final sResponse = await _socket.sendCommand('MKD $sName');
    return sResponse.isSuccessCode();
  }

  Future<bool> deleteEmptyDirectory(String? sName) async {
    final sResponse = await _socket.sendCommand('rmd $sName');
    return sResponse.isSuccessCode();
  }

  Future<bool> changeDirectory(String? sName) async {
    final sResponse = await _socket.sendCommand('CWD $sName');
    return sResponse.isSuccessCode();
  }

  Future<String> currentDirectory() async {
    final sResponse = await _socket.sendCommand('PWD');
    if (!sResponse.isSuccessCode()) {
      throw FTPConnectException(
        'Failed to get current working directory',
        sResponse.message,
      );
    }

    final iStart = sResponse.message.indexOf('"') + 1;
    final iEnd = sResponse.message.lastIndexOf('"');

    return sResponse.message.substring(iStart, iEnd);
  }

  Future<List<FTPEntry>> directoryContent() async {
    final response = await _socket.openDataTransferChannel();
    _socket.sendCommandWithoutWaitingResponse(_socket.listCommand.describeEnum);

    final iPort = Utils.parsePort(response.message, _socket.supportIPV6);
    final dataSocket = await Socket.connect(
      _socket.host,
      iPort,
      timeout: Duration(seconds: _socket.timeout),
    );
    var response2 = await _socket.readResponse();
    var isTransferCompleted = response2.isSuccessCode();
    if (!isTransferCompleted &&
        response2.code != 125 &&
        response2.code != 150) {
      throw FTPConnectException('Connection refused. ', response2.message);
    }

    final lstDirectoryListing = <int>[];
    await dataSocket.listen((Uint8List data) {
      lstDirectoryListing.addAll(data);
    }).asFuture();

    await dataSocket.close();

    if (!isTransferCompleted) {
      response2 = await _socket.readResponse();
      if (!response2.isSuccessCode()) {
        throw FTPConnectException('Transfer Error.', response2.message);
      }
    }

    final lstFTPEntries = <FTPEntry>[];
    for (final line in Utf8Codec().decode(lstDirectoryListing).split('\n')) {
      if (line.trim().isNotEmpty) {
        lstFTPEntries.add(
          FTPEntry.parse(
            line.replaceAll('\r', ''),
            _socket.listCommand,
          ),
        );
      }
    }

    return lstFTPEntries;
  }

  Future<List<String>> directoryContentNames() async {
    final list = await directoryContent();
    return list.map((f) => f.name).whereType<String>().toList();
  }
}
