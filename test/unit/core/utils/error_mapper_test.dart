import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/error_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ErrorMessageMapper.mapToUserMessage', () {
    test('returns generic message when exception is null', () {
      expect(
        ErrorMessageMapper.mapToUserMessage(null),
        equals('Ocorreu um erro desconhecido. Tente novamente.'),
      );
    });

    group('Failure types', () {
      test('NetworkFailure returns localized network message', () {
        final result = ErrorMessageMapper.mapToUserMessage(
          const NetworkFailure(message: 'down'),
        );
        expect(result, contains('Erro de rede'));
        expect(result, contains('Verifique sua conexão'));
      });

      test('ValidationFailure includes original message prefixed', () {
        final result = ErrorMessageMapper.mapToUserMessage(
          const ValidationFailure(message: 'campo obrigatório'),
        );
        expect(result, equals('Dados inválidos: campo obrigatório'));
      });

      test('FileSystemFailure includes original message prefixed', () {
        final result = ErrorMessageMapper.mapToUserMessage(
          const FileSystemFailure(message: 'sem espaço'),
        );
        expect(result, equals('Erro no sistema de arquivos: sem espaço'));
      });

      test('ServerFailure with CONNECTION_REFUSED has dedicated message', () {
        final result = ErrorMessageMapper.mapToUserMessage(
          const ServerFailure(
            message: 'irrelevant',
            code: 'CONNECTION_REFUSED',
          ),
        );
        expect(result, contains('Servidor não respondeu'));
      });

      test('ServerFailure with TIMEOUT has dedicated message', () {
        final result = ErrorMessageMapper.mapToUserMessage(
          const ServerFailure(message: 'irrelevant', code: 'TIMEOUT'),
        );
        expect(
          result,
          equals('Tempo esgotado ao aguardar resposta do servidor.'),
        );
      });

      test('ServerFailure with unknown code falls back to message', () {
        final result = ErrorMessageMapper.mapToUserMessage(
          const ServerFailure(message: 'oops', code: 'WEIRD_CODE'),
        );
        expect(result, equals('Erro no servidor: oops'));
      });

      test('Generic Failure with empty message uses fallback', () {
        final result = ErrorMessageMapper.mapToUserMessage(
          const NetworkFailure(message: ''),
        );
        // NetworkFailure is matched before generic — message stays the
        // dedicated one regardless of failure.message content.
        expect(result, contains('Erro de rede'));
      });
    });

    group('Generic exceptions', () {
      test('ConnectionManager not connected maps to friendly prompt', () {
        final result = ErrorMessageMapper.mapToUserMessage(
          Exception('ConnectionManager not connected'),
        );
        expect(result, contains('Conecte-se a um servidor'));
      });

      test('"during file transfer" disconnection has dedicated message', () {
        final result = ErrorMessageMapper.mapToUserMessage(
          Exception('Disconnected during file transfer to remote'),
        );
        expect(result, contains('Conexão perdida durante o download'));
      });

      test('"during backup" disconnection has dedicated message', () {
        final result = ErrorMessageMapper.mapToUserMessage(
          Exception('disconnected during backup execution'),
        );
        expect(result, contains('Conexão perdida durante o backup'));
      });

      test('TimeoutException string is mapped', () {
        final result = ErrorMessageMapper.mapToUserMessage(
          Exception('Operation TimeoutException after 30s'),
        );
        expect(
          result,
          equals('Tempo esgotado ao aguardar resposta do servidor.'),
        );
      });

      test('time limit message extracts minutes from "limite:"', () {
        final result = ErrorMessageMapper.mapToUserMessage(
          Exception(
            'Aguardando conclusão do backup excedeu o limite: 15 minutos',
          ),
        );
        expect(result, contains('15 min'));
        expect(result, contains('tempo limite'));
      });

      test('time limit message falls back to default when minutes absent', () {
        final result = ErrorMessageMapper.mapToUserMessage(
          Exception(
            'Aguardando conclusao do backup excedeu o limite definido',
          ),
        );
        expect(result, contains('10 min'));
      });

      test('returns original message if no rule matches', () {
        final result = ErrorMessageMapper.mapToUserMessage(
          Exception('Some random error'),
        );
        expect(result, contains('Some random error'));
      });

      test('returns generic message when string is empty', () {
        final result = ErrorMessageMapper.mapToUserMessage('');
        expect(
          result,
          equals('Ocorreu um erro desconhecido. Tente novamente.'),
        );
      });
    });

    test('mapExceptionToMessage alias remains backwards-compatible', () {
      expect(
        mapExceptionToMessage(const NetworkFailure(message: 'x')),
        equals(
          ErrorMessageMapper.mapToUserMessage(
            const NetworkFailure(message: 'x'),
          ),
        ),
      );
    });
  });
}
