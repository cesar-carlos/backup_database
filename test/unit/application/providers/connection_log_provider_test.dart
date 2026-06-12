import 'package:backup_database/application/providers/connection_log_provider.dart';
import 'package:backup_database/domain/entities/connection_log.dart';
import 'package:backup_database/domain/repositories/i_connection_log_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockRepository extends Mock implements IConnectionLogRepository {}

final _sampleLogs = <ConnectionLog>[
  ConnectionLog(
    id: '1',
    clientHost: '192.168.1.1',
    success: true,
    timestamp: DateTime(2026),
  ),
];

void main() {
  group('ConnectionLogProvider.loadLogs', () {
    late _MockRepository repository;
    late ConnectionLogProvider provider;

    setUp(() {
      repository = _MockRepository();
      provider = ConnectionLogProvider(repository);
    });

    test('sets generic error message when repository fails', () async {
      when(() => repository.getRecentLogs(any())).thenAnswer(
        (_) async => rd.Failure(Exception('database unavailable')),
      );

      await provider.loadLogs();

      expect(
        provider.error,
        'Erro ao carregar log de conexões: Exception: database unavailable',
      );
    });

    test('returns early when already loading', () async {
      var callCount = 0;
      when(() => repository.getRecentLogs(any())).thenAnswer((_) async {
        callCount++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return rd.Success(_sampleLogs);
      });

      final f1 = provider.loadLogs();
      final f2 = provider.loadLogs();
      await Future.wait([f1, f2]);

      expect(callCount, 1);
    });
  });
}
