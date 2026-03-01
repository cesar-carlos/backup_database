import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ftp_exceptions.dart';
import 'ftp_reply.dart';
import 'ftpconnect_base.dart';
import 'logger.dart';

class FTPSocket {
  FTPSocket(this.host, this.port, this.securityType, this.logger, this.timeout);

  final String host;
  final int port;
  final Logger logger;
  final int timeout;
  final SecurityType securityType;
  late RawSocket _socket;
  TransferMode transferMode = TransferMode.passive;
  TransferType _transferType = TransferType.auto;
  ListCommand listCommand = ListCommand.mlsd;
  bool supportIPV6 = false;

  TransferType get transferType => _transferType;

  Future<FTPReply> readResponse() async {
    final res = StringBuffer();
    await Future.doWhile(() async {
      var dataReceivedSuccessfully = false;

      while (_socket.available() > 0) {
        res.write(Utf8Codec().decode(_socket.read()!).trim());
        dataReceivedSuccessfully = true;
      }
      if (dataReceivedSuccessfully) return false;

      await Future.delayed(const Duration(milliseconds: 300));
      return true;
    }).timeout(Duration(seconds: timeout), onTimeout: () {
      throw FTPConnectException('Timeout reached for Receiving response !');
    });

    var r = res.toString();
    if (r.startsWith('\n')) r = r.replaceFirst('\n', '');

    if (r.length < 3) throw FTPConnectException('Illegal Reply Exception', r);

    int? code;
    final lines = r.split('\n');
    String? line;
    for (line in lines) {
      if (line.length >= 3) code = int.tryParse(line.substring(0, 3)) ?? code;
    }
    if (line != null && line.length >= 4 && line[3] == '-') {
      return readResponse();
    }

    if (code == null) throw FTPConnectException('Illegal Reply Exception', r);

    final reply = FTPReply(code, r);
    logger.log('< ${reply.toString()}');
    return reply;
  }

  Future<FTPReply> sendCommand(String cmd) {
    logger.log('> $cmd');
    _socket.write(Utf8Codec().encode('$cmd\r\n'));

    return readResponse();
  }

  void sendCommandWithoutWaitingResponse(String cmd) {
    logger.log('> $cmd');
    _socket.write(Utf8Codec().encode('$cmd\r\n'));
  }

  Future<bool> connect(String user, String pass, {String? account}) async {
    logger.log('Connecting...');

    final timeout = Duration(seconds: this.timeout);

    try {
      if (securityType == SecurityType.ftps) {
        _socket = await RawSecureSocket.connect(
          host,
          port,
          timeout: timeout,
          onBadCertificate: (_) => true,
        );
      } else {
        _socket = await RawSocket.connect(
          host,
          port,
          timeout: timeout,
        );
      }
    } catch (e) {
      throw FTPConnectException(
        'Could not connect to $host ($port)',
        e.toString(),
      );
    }

    logger.log('Connection established, waiting for welcome message...');
    await readResponse();

    if (securityType == SecurityType.ftpes) {
      var lResp = await sendCommand('AUTH TLS');
      if (!lResp.isSuccessCode()) {
        lResp = await sendCommand('AUTH SSL');
        if (!lResp.isSuccessCode()) {
          throw FTPConnectException(
            'FTPES cannot be applied: the server refused both AUTH TLS and AUTH SSL commands',
            lResp.message,
          );
        }
      }

      _socket = await RawSecureSocket.secure(
        _socket,
        onBadCertificate: (_) => true,
      );
    }

    if ([SecurityType.ftpes, SecurityType.ftps].contains(securityType)) {
      await sendCommand('PBSZ 0');
      await sendCommand('PROT P');
    }

    var lResp = await sendCommand('USER $user');

    if (lResp.code == 331) {
      lResp = await sendCommand('PASS $pass');
      if (lResp.code == 332) {
        if (account == null) throw FTPConnectException('Account required');
        lResp = await sendCommand('ACCT $account');
        if (!lResp.isSuccessCode()) {
          throw FTPConnectException('Wrong Account', lResp.message);
        }
      } else if (!lResp.isSuccessCode()) {
        throw FTPConnectException('Wrong Username/password', lResp.message);
      }
    } else if (lResp.code == 332) {
      if (account == null) throw FTPConnectException('Account required');
      lResp = await sendCommand('ACCT $account');
      if (!lResp.isSuccessCode()) {
        throw FTPConnectException('Wrong Account', lResp.message);
      }
    } else if (!lResp.isSuccessCode()) {
      throw FTPConnectException('Wrong username $user', lResp.message);
    }

    logger.log('Connected!');
    return true;
  }

  Future<FTPReply> openDataTransferChannel() async {
    if (transferMode == TransferMode.active) {
      return FTPReply(200, '');
    }
    final res = await sendCommand(supportIPV6 ? 'EPSV' : 'PASV');
    if (!res.isSuccessCode()) {
      throw FTPConnectException('Could not start Passive Mode', res.message);
    }
    return res;
  }

  Future<void> setTransferType(TransferType pTransferType) async {
    if (_transferType == pTransferType) return;
    switch (pTransferType) {
      case TransferType.auto:
        await sendCommand('TYPE A');
        break;
      case TransferType.ascii:
        await sendCommand('TYPE A');
        break;
      case TransferType.binary:
        await sendCommand('TYPE I');
        break;
    }
    _transferType = pTransferType;
  }

  Future<bool> disconnect() async {
    logger.log('Disconnecting...');

    try {
      await sendCommand('QUIT');
    } catch (ignored) {
      // Ignore
    } finally {
      await _socket.close();
      _socket.shutdown(SocketDirection.both);
    }

    logger.log('Disconnected!');
    return true;
  }
}
