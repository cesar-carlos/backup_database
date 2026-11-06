import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ftp_exceptions.dart';
import 'ftp_reply.dart';
import 'ftpconnect_base.dart';
import 'logger.dart';

class FTPSocket {
  FTPSocket(
    this.host,
    this.port,
    this.securityType,
    this.logger,
    this.timeout, {
    this.allowInvalidCertificates = true,
  });

  final String host;
  final int port;
  final Logger logger;
  final int timeout;
  final SecurityType securityType;
  final bool allowInvalidCertificates;
  late RawSocket _socket;
  bool _dataChannelProtected = false;
  TransferMode transferMode = TransferMode.passive;
  TransferType _transferType = TransferType.auto;
  ListCommand listCommand = ListCommand.mlsd;
  bool supportIPV6 = false;

  TransferType get transferType => _transferType;

  final List<int> _responseBytes = [];
  bool _closed = false;
  final Set<Socket> _dataSockets = {};
  Completer<void> _aborted = Completer<void>();

  Future<void> get whenAborted => _aborted.future;

  void abort() {
    _closed = true;
    if (!_aborted.isCompleted) _aborted.complete();
    for (final data in _dataSockets) {
      data.destroy();
    }
    _dataSockets.clear();
    try {
      _socket.shutdown(SocketDirection.both);
      unawaited(_socket.close());
    } catch (_) {
      // The connection may still be opening.
    }
  }

  void releaseDataSocket(Socket socket) {
    _dataSockets.remove(socket);
    socket.destroy();
  }

  void _checkOpen() {
    if (_closed) throw FTPConnectException('FTP connection aborted');
  }

  Future<FTPReply> readResponse() async {
    final elapsed = Stopwatch()..start();
    final lines = <String>[];
    int? code;
    while (elapsed.elapsed < Duration(seconds: timeout)) {
      _checkOpen();
      final end = _responseBytes.indexOf(10);
      if (end >= 0) {
        final line = utf8
            .decode(_responseBytes.sublist(0, end), allowMalformed: true)
            .replaceFirst(RegExp(r'\r$'), '');
        _responseBytes.removeRange(0, end + 1);
        lines.add(line);
        if (code == null) {
          if (!RegExp(r'^\d{3}[ -]').hasMatch(line)) {
            throw FTPConnectException('Illegal Reply Exception', line);
          }
          code = int.parse(line.substring(0, 3));
        }
        if (line.startsWith('$code ')) {
          final reply = FTPReply(code, lines.join('\n'));
          logger.log('< $reply');
          return reply;
        }
        continue;
      }
      final bytes = _socket.available() > 0 ? _socket.read() : null;
      if (bytes != null) {
        _responseBytes.addAll(bytes);
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
    // A late reply must never be mistaken for the next command's response.
    abort();
    throw TimeoutException('Timeout reached for Receiving response');
  }

  Future<FTPReply> sendCommand(String cmd) async {
    _checkOpen();
    logger.log('> $cmd');
    _socket.write(Utf8Codec().encode('$cmd\r\n'));

    return readResponse();
  }

  void sendCommandWithoutWaitingResponse(String cmd) {
    _checkOpen();
    logger.log('> $cmd');
    _socket.write(Utf8Codec().encode('$cmd\r\n'));
  }

  Future<bool> connect(String user, String pass, {String? account}) async {
    _closed = false;
    _aborted = Completer<void>();
    _responseBytes.clear();
    _transferType = TransferType.auto;
    _dataChannelProtected = false;
    try {
      return await _connect(user, pass, account: account);
    } catch (_) {
      // Login/TLS failures happen before callers consider this connected.
      // Close here; their connected-only cleanup cannot release this socket.
      abort();
      rethrow;
    }
  }

  Future<bool> _connect(String user, String pass, {String? account}) async {
    logger.log('Connecting...');

    final timeout = Duration(seconds: this.timeout);

    try {
      if (securityType == SecurityType.ftps) {
        _socket = await RawSecureSocket.connect(
          host,
          port,
          timeout: timeout,
          onBadCertificate: (_) => allowInvalidCertificates,
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

    _checkOpen();
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
        onBadCertificate: (_) => allowInvalidCertificates,
      );
    }

    if ([SecurityType.ftpes, SecurityType.ftps].contains(securityType)) {
      await sendCommand('PBSZ 0');
      final protReply = await sendCommand('PROT P');
      _dataChannelProtected = protReply.isSuccessCode();
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

  Future<Socket> openDataSocket(int port) async {
    _checkOpen();
    final timeout = Duration(seconds: this.timeout);
    final Socket socket;
    if (_dataChannelProtected) {
      socket = await SecureSocket.connect(
        host,
        port,
        timeout: timeout,
        onBadCertificate: (_) => allowInvalidCertificates,
      );
    } else {
      socket = await Socket.connect(host, port, timeout: timeout);
    }
    if (_closed) {
      socket.destroy();
      _checkOpen();
    }
    _dataSockets.add(socket);
    return socket;
  }

  Future<void> setTransferType(TransferType pTransferType) async {
    if (_transferType == pTransferType) return;
    final reply = await sendCommand(
      pTransferType == TransferType.binary ? 'TYPE I' : 'TYPE A',
    );
    if (!reply.isSuccessCode()) {
      throw FTPConnectException('Transfer type refused', reply.message);
    }
    _transferType = pTransferType;
  }

  Future<bool> disconnect() async {
    if (_closed) return true;
    logger.log('Disconnecting...');

    try {
      await sendCommand('QUIT');
    } catch (ignored) {
      // Ignore
    } finally {
      abort();
    }

    logger.log('Disconnected!');
    return true;
  }
}
