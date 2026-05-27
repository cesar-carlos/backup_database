import 'package:backup_database/core/utils/sybase_connection_field_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SybaseConnectionFieldValidator', () {
    test('valor sem caracteres reservados retorna null (válido)', () {
      expect(
        SybaseConnectionFieldValidator.validate('foo_bar123', 'Campo'),
        isNull,
      );
      expect(SybaseConnectionFieldValidator.isUnsafe('foo_bar123'), isFalse);
    });

    // Achado C.1 da auditoria: parser do Sybase usa `;` como separador
    // de params. Sem essa validação, password contendo `;LOG=hack.log`
    // adiciona um param adicional ao connect (injection de connection
    // string).
    test('rejeita valor com `;` (separador Sybase)', () {
      final error = SybaseConnectionFieldValidator.validate(
        'pwd;LOG=hack.log',
        'Senha',
      );
      expect(error, isNotNull);
      expect(error, contains('Senha'));
      expect(error, contains('";"'));
      expect(
        SybaseConnectionFieldValidator.isUnsafe('pwd;LOG=hack.log'),
        isTrue,
      );
    });

    test('rejeita valor com `=` (separador chave/valor Sybase)', () {
      final error = SybaseConnectionFieldValidator.validate(
        'user=hack',
        'Usuário',
      );
      expect(error, isNotNull);
      expect(error, contains('Usuário'));
      expect(error, contains('"="'));
    });

    test('string vazia retorna null (validador é só para sanitização)', () {
      expect(SybaseConnectionFieldValidator.validate('', 'Campo'), isNull);
      expect(SybaseConnectionFieldValidator.isUnsafe(''), isFalse);
    });

    test('mensagem de erro identifica o campo informado', () {
      final error = SybaseConnectionFieldValidator.validate(
        'srv;extra',
        'Nome do servidor',
      );
      expect(error, contains('Nome do servidor'));
    });
  });
}
