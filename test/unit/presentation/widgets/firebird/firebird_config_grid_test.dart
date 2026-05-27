import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/presentation/widgets/firebird/firebird_config_grid.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---- B10: FirebirdConfigGrid display ----
  //
  // Antes da auditoria 2026-05-27 o grid mostrava sempre `host:port` e
  // `databaseFile`. Em modo embedded o host/port nao tem significado;
  // e configs alias-only (databaseFile vazio) tinham celula em branco.
  // Estes testes documentam a regra: embedded -> "(embedded)" ;
  // alias-only -> alias.

  Widget harness(List<FirebirdConfig> configs) {
    return FluentApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(1280, 720)),
        child: NavigationView(
          content: ScaffoldPage(
            content: FirebirdConfigGrid(configs: configs),
          ),
        ),
      ),
    );
  }

  FirebirdConfig cfg({
    required String id,
    bool useEmbedded = false,
    String host = 'srv',
    int port = 3050,
    String databaseFile = '',
    String? aliasName,
  }) {
    return FirebirdConfig(
      id: id,
      name: 'cfg-$id',
      host: host,
      databaseFile: databaseFile,
      username: 'u',
      password: 'p',
      port: PortNumber(port),
      useEmbedded: useEmbedded,
      aliasName: aliasName,
    );
  }

  testWidgets(
    'modo TCP mostra host:port no endpoint e databaseFile na coluna db',
    (tester) async {
      await tester.pumpWidget(
        harness([
          cfg(
            id: 'tcp',
            host: 'app-srv',
            port: 3055,
            databaseFile: r'C:\data\biz.fdb',
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('app-srv:3055'), findsOneWidget);
      expect(find.text(r'C:\data\biz.fdb'), findsOneWidget);
    },
  );

  testWidgets(
    'modo embedded mostra (embedded) no endpoint em vez de host:port',
    (tester) async {
      await tester.pumpWidget(
        harness([
          cfg(
            id: 'emb',
            useEmbedded: true,
            host: 'localhost',
            databaseFile: r'C:\data\local.fdb',
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('(embedded)'), findsOneWidget);
      // Host:port nao deve aparecer (nao ha conexao TCP).
      expect(find.text('localhost:3050'), findsNothing);
    },
  );

  testWidgets(
    'alias-only (databaseFile vazio) mostra alias na coluna db em vez de '
    'celula em branco',
    (tester) async {
      await tester.pumpWidget(
        harness([
          cfg(
            id: 'alias',
            aliasName: 'meu_alias',
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('meu_alias'), findsOneWidget);
    },
  );
}
