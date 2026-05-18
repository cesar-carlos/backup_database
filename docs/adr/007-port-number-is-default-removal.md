# ADR-007: Remover `PortNumber.isDefault`

- Status: accepted
- Data: 2026-05-18
- Decisores: time do produto (app desktop backup_database)
- Contexto relacionado:
  `docs/notes/plano_refatoracao_e_melhorias_2026-04-19.md` (B5, A5, M4)

## Contexto

`PortNumber` valida portas TCP (1–65535). O getter `isDefault` retornava
`true` para uma lista fixa de portas “comuns” (1433, 2638, 3050, 3306,
5432) **sem** saber qual SGBD está em uso.

O achado **B5** corrigiu a lista (incluiu 2638 e 3050), mas o conceito
permanece ambíguo: a porta 5432 é default de PostgreSQL, não de SQL
Server; 3306 (MySQL) nem é SGBD suportado pelo app hoje.

Auditoria (2026-05-18): **nenhum** código em `lib/` chama `isDefault`;
apenas testes unitários do value object.

## Decisao

**Remover** o getter `PortNumber.isDefault` do domínio.

Porta padrão por motor continua definida nos construtores/factories de
cada config (`SqlServerConfig` → 1433, `SybaseConfig` → 2638,
`PostgresConfig` → 5432, `FirebirdConfig` → 3050) e nos serializers de
protocolo — fonte única e contextualizada.

## Consequencias

### Positivas

- Elimina API enganosa (heurística cross-SGBD sem `DatabaseType`).
- Menos superfície para divergência entre `isDefault` e defaults reais.

### Negativas

- Se no futuro a UI precisar de hint “porta padrão”, deve consultar o
  default do SGBD ativo, não `PortNumber`.

### Neutras

- Testes de `isDefault` são substituídos por testes de validação de
  intervalo em `port_number_test.dart`.

## Alternativas consideradas

### Manter `isDefault` atualizado (opção A5)

- Corrige B5, mas mantém semântica frágil.
- Rejeitada após confirmar zero uso em produção.

### `@Deprecated` e remoção posterior

- Útil se houvesse callers externos; não há.
- Rejeitada em favor de remoção direta.

## Notas de implementacao

- Remover getter em `lib/domain/value_objects/port_number.dart`.
- Atualizar `test/unit/domain/value_objects/port_number_test.dart`.
