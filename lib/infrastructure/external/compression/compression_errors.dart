import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';

abstract final class CompressionErrors {
  static String fileSystemErrorMessage(FileSystemException e) {
    final path = e.path ?? 'desconhecido';
    if (e.osError?.errorCode == 5) {
      return 'Acesso negado ao arquivo: $path\n'
          'Execute o aplicativo como Administrador ou escolha outro diretório.';
    } else if (e.osError?.errorCode == 3) {
      return 'Caminho não encontrado: $path\n'
          'Verifique se o disco ou pasta existe.';
    } else if (e.osError?.errorCode == 112) {
      return 'Disco cheio ou sem espaço suficiente para criar o arquivo ZIP.';
    } else if (e.osError?.errorCode == 32) {
      return 'Arquivo em uso por outro processo: $path\n'
          'O arquivo pode estar sendo usado pelo sistema ou outro programa.\n'
          'Aguarde alguns segundos e tente novamente, ou feche outros programas que podem estar usando o arquivo.';
    }
    return 'Erro ao acessar arquivo: ${e.message}';
  }

  static String userFriendlyError(Object e) {
    if (e is FileSystemException) {
      return fileSystemErrorMessage(e);
    }
    return failureUserMessage(e);
  }
}
