import 'dart:io';

abstract final class LocalDestinationErrors {
  static String permissionMessage(FileSystemException e, String path) {
    if (e.osError?.errorCode == 5) {
      return 'Acesso negado ao diretório: $path\n'
          'Verifique as permissões da conta que executa o backup. '
          'No serviço Windows, essa conta pode ser diferente do usuário da interface.';
    } else if (e.osError?.errorCode == 3) {
      return 'Caminho não encontrado: $path\n'
          'Verifique se o disco ou pasta existe. Para compartilhamentos de rede '
          r'no serviço Windows, use um caminho UNC (\\servidor\pasta); '
          'unidades mapeadas pelo usuário podem não estar disponíveis ao serviço.';
    } else if (e.osError?.errorCode == 53 || e.osError?.errorCode == 67) {
      return 'Compartilhamento de rede indisponível: $path\n'
          'Verifique o caminho UNC, a conexão e as permissões da conta do serviço Windows.';
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
