import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/payload_limits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PayloadLimits (M5.4)', () {
    test('tipos pequenos tem limite apertado', () {
      // Comandos de schedule com so um id devem ter limite minimo
      expect(
        PayloadLimits.maxPayloadBytesFor(MessageType.executeSchedule),
        lessThan(8 * 1024),
      );
      expect(
        PayloadLimits.maxPayloadBytesFor(MessageType.cancelSchedule),
        lessThan(8 * 1024),
      );
      expect(
        PayloadLimits.maxPayloadBytesFor(MessageType.heartbeat),
        lessThanOrEqualTo(4 * 1024),
      );
    });

    test('fileChunk tem limite proximo do global (alta tolerancia)', () {
      // Unico tipo que pode legitimamente carregar MB de payload
      expect(
        PayloadLimits.maxPayloadBytesFor(MessageType.fileChunk),
        SocketConfig.maxMessagePayloadBytes,
      );
    });

    test('listas e schedules tem limite intermediario', () {
      // Lista pode ter muitos schedules com config JSON
      expect(
        PayloadLimits.maxPayloadBytesFor(MessageType.scheduleList),
        greaterThanOrEqualTo(256 * 1024),
      );
      expect(
        PayloadLimits.maxPayloadBytesFor(MessageType.fileList),
        greaterThanOrEqualTo(256 * 1024),
      );
      expect(
        PayloadLimits.maxPayloadBytesFor(MessageType.updateSchedule),
        greaterThanOrEqualTo(64 * 1024),
      );
    });

    test('capabilities response tem limite conservador', () {
      // capabilities e payload pequeno, bem definido (M1.3)
      expect(
        PayloadLimits.maxPayloadBytesFor(MessageType.capabilitiesResponse),
        lessThanOrEqualTo(64 * 1024),
      );
      expect(
        PayloadLimits.maxPayloadBytesFor(MessageType.capabilitiesRequest),
        lessThanOrEqualTo(4 * 1024),
      );
    });

    test('todo MessageType tem limite definido (no map ou via fallback)', () {
      // Garante que adicionar um novo MessageType nao deixa lacuna —
      // o helper sempre retorna limite valido (perType ou fallback global).
      for (final type in MessageType.values) {
        final limit = PayloadLimits.maxPayloadBytesFor(type);
        expect(
          limit,
          greaterThan(0),
          reason: 'Tipo ${type.name} deve ter limite > 0',
        );
        expect(
          limit,
          lessThanOrEqualTo(SocketConfig.maxMessagePayloadBytes),
          reason: 'Tipo ${type.name} nao pode exceder o teto global',
        );
      }
    });

    test('limites do mapa publico nunca excedem o global (defesa)', () {
      // Mesmo se alguem editar o mapa com valor errado, o helper deve
      // saturar no teto global (cinto + suspensorio).
      for (final entry in PayloadLimits.perType.entries) {
        final effective = PayloadLimits.maxPayloadBytesFor(entry.key);
        expect(effective, lessThanOrEqualTo(SocketConfig.maxMessagePayloadBytes));
      }
    });

    test('mapa cobre todos os tipos atuais do protocolo', () {
      // Nao e exigido — tipos nao mapeados caem no fallback. Mas e
      // sinal de saude: alertar quando alguem adicionar tipo novo
      // sem decidir o limite.
      final missing = MessageType.values
          .where((t) => !PayloadLimits.perType.containsKey(t))
          .toList();
      expect(
        missing,
        isEmpty,
        reason:
            'Tipos sem limite explicito: ${missing.map((e) => e.name).join(', ')}. '
            'Adicione entrada em PayloadLimits.perType ou justifique fallback.',
      );
    });
  });
}
