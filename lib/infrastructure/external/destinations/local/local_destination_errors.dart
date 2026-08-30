import 'dart:io';

abstract final class LocalDestinationErrors {
  static String permissionMessage(FileSystemException e, String path) {
    if (e.osError?.errorCode == 5) {
      return 'Acesso negado ao diretório: $path\n'
          'Execute o aplicativo como Administrador ou escolha outro diretório.';
    } else if (e.osError?.errorCode == 3) {
      return 'Caminho não encontrado: $path\n'
          'Verifique se o disco ou pasta existe.';
    } else if (e.osError?.errorCode == 112) {
      return 'Disco cheio ou sem espaço suficiente: $path';
    }
    return 'Erro ao acessar: $path - ${e.message}';
  }

  static String userFriendly(Object e) {
    if (e is FileSystemException) {
      return permissionMessage(e, e.path ?? 'desconhecido');
    }
    return e.toString();
  }
}
