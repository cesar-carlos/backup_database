import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';

/// Sink de append-only para arquivos de log, com **atomicidade write-line**
/// e **rotação opcional** baseada em tamanho.
///
/// ## Por que existe
///
/// Múltiplos arquivos de log no projeto (`service_bootstrap.log`,
/// `service_control_diagnostics.log`, `install_elevated_*.log`) gravavam
/// direto via `File.writeAsString(mode: append)` em chamadas concorrentes,
/// causando dois problemas:
///
/// 1. **Interleaving** — quando duas chamadas paralelas acertavam o mesmo
///    arquivo no mesmo tick do event loop, suas linhas podiam ser
///    intercaladas no meio do arquivo, corrompendo a leitura por humanos
///    e scripts grep/awk.
///
/// 2. **Crescimento ilimitado** — sem rotação, em um serviço 24/7 com
///    restart loop transitório, `service_bootstrap.log` chegava a GBs
///    consumindo o disco do servidor.
///
/// ## Como resolve
///
/// - **Fila interna**: writes são enfileirados e processados sequencialmente
///   por um único `Future` em background (`_processQueue`). Garante que a
///   ordem das linhas no arquivo seja a ordem das chamadas a [append].
/// - **Rotação por tamanho**: quando o arquivo atinge [maxFileSize], é
///   renomeado para `<name>.1` (e o existente vira `<name>.2`, até
///   [maxFiles]). Os mais antigos são deletados.
/// - **Best-effort**: erros de I/O são logados via `developer.log` (para
///   evitar recursão se o LoggerService usar este sink) mas nunca lançados
///   ao caller — diagnostics não devem quebrar o fluxo principal.
///
/// ## Limitações
///
/// - Não é thread-safe entre **processos** — apenas entre operações
///   concorrentes do mesmo processo Dart. Para sincronização inter-process
///   considere file locking (ex.: `RandomAccessFile.lock()`).
/// - Em caso de crash do processo durante write, a última linha pode
///   estar truncada. Aceitável para diagnostics.
class AppendingFileSink {
  AppendingFileSink({
    required String path,
    this.maxFileSize = 10 * 1024 * 1024,
    this.maxFiles = 5,
  }) : _path = path;

  final String _path;

  /// Tamanho máximo em bytes antes de rotacionar. Default: 10 MB.
  final int maxFileSize;

  /// Quantos arquivos rotacionados manter (`<name>.1`, `<name>.2`, ...).
  /// Default: 5 (≈ 50 MB total com `maxFileSize` default).
  final int maxFiles;

  final Queue<String> _writeQueue = Queue<String>();
  bool _processing = false;

  /// Enfileira [content] para append. Adiciona `\n` ao final se não
  /// houver. Retorna imediatamente — a write efetiva acontece em
  /// background. Para garantir flush, use [flush] explicitamente.
  void append(String content) {
    final line = content.endsWith('\n') ? content : '$content\n';
    _writeQueue.add(line);
    unawaited(_processQueue());
  }

  /// Aguarda a fila atual ser drenada para o disco. Útil em testes ou
  /// antes de shutdown para garantir que diagnostics não sejam perdidos.
  Future<void> flush() async {
    while (_writeQueue.isNotEmpty || _processing) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<void> _processQueue() async {
    if (_processing) return;
    _processing = true;
    try {
      while (_writeQueue.isNotEmpty) {
        final batch = StringBuffer();
        // Drain batch: agrupar writes pendentes em um único I/O reduz
        // overhead quando há rajadas (ex.: polling loop emitindo 5+
        // diagnostics em sequência).
        while (_writeQueue.isNotEmpty) {
          batch.write(_writeQueue.removeFirst());
        }
        await _writeBatch(batch.toString());
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _writeBatch(String batch) async {
    try {
      final file = File(_path);
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }

      // Rotação proativa: se o arquivo já está acima do limite, rotaciona
      // ANTES de gravar. Garante que o arquivo atual nunca extrapole muito
      // além do limite (a granularidade é o tamanho do batch).
      if (await file.exists()) {
        final stat = await file.stat();
        if (stat.size >= maxFileSize) {
          await _rotate();
        }
      }

      await file.writeAsString(batch, mode: FileMode.append);
    } on Object catch (e, s) {
      // Não usamos LoggerService aqui para evitar recursão se o
      // LoggerService for configurado para escrever neste mesmo sink.
      LoggerService.warning(
        '[AppendingFileSink] write failed for $_path: $e',
        e,
        s,
      );
    }
  }

  Future<void> _rotate() async {
    try {
      // Remove o mais antigo (se chegou ao limite)
      final oldest = File('$_path.$maxFiles');
      if (await oldest.exists()) {
        await oldest.delete();
      }
      // Shift: file.N → file.(N+1) de trás para frente para não sobrescrever
      for (var i = maxFiles - 1; i >= 1; i--) {
        final src = File('$_path.$i');
        if (await src.exists()) {
          await src.rename('$_path.${i + 1}');
        }
      }
      // file → file.1
      final current = File(_path);
      if (await current.exists()) {
        await current.rename('$_path.1');
      }
    } on Object catch (e, s) {
      LoggerService.warning(
        '[AppendingFileSink] rotation failed for $_path: $e',
        e,
        s,
      );
    }
  }
}
