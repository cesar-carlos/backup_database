# Plano: Refatoração e Melhorias de Código

Data base: 2026-04-19
Status: **Código no repositório** (PR-A–E); **M2 (lint extra)** concluído
(2026-05-15: `discarded_futures` + `unawaited_futures` + `avoid_dynamic_calls`,
`flutter analyze` 0 issues); **M1 (freezed)** concluído (**2026-05-18**:
configs SGBD + `Schedule` + `BackupLog`/`BackupHistory` + piloto
`BackupExecutionContext`; `implements DatabaseConnectionConfig`). **PR-C** fechamento residual **C0.10/C0.12**
(2026-05-15: densidade de tabelas persistida + `AppZIndex.stackByZIndex` no
progress bar). **Roadmap §11 implementado** (M1–M14 código/docs/commits **2026-05-18**:
7 commits via `tools/plan_commit_groups.ps1`). Restam apenas **smokes manuais**
(M14 Win10/11 — `smoke_windows_mica_m14.md`; Firebird §8.1).
Escopo: 4 PRs sequenciais de **bug fixes + refatoração DRY + melhorias
de UX + consolidação arquitetural via ports/adapters genéricos**.
Pré-requisito para o plano de adoção do Firebird (ver
[`plano_suporte_firebird_2026-04-19.md`](./plano_suporte_firebird_2026-04-19.md))
e para qualquer SGBD futuro com baixo custo de manutenção.

Plano companheiro: implementação Firebird parte do estado entregue
ao final deste plano. Ler ambos em conjunto.

---

## Sumário executivo

A auditoria profunda do código atual identificou **5 níveis de
problema** que justificam refatoração estruturada antes de adicionar
o quarto SGBD (Firebird):

1. **Bugs latentes / code smells** (PR-A, 1 dia) — alguns expõem
   dados incorretos ou crashes silenciosos
2. **Duplicação técnica em domínio/infra** (PR-B, 1,5 dia) — 6
   helpers consolidam ~220 linhas hoje
3. **Falta de Design System estruturado** (PR-C, 1,5 dia) — `AppColors`
   é lista plana de 50+ cores; sem tokens de spacing/radius/motion;
   sem `ThemeExtension`; sem hierarquia atomic design; sem regra
   "composition over inheritance"
4. **Duplicação técnica em UI + UX** (PR-D, 2 dias) — god dialog,
   grids duplicados, +4 melhorias de UX (consome design system do PR-C)
5. **Falta de abstração genérica para SGBDs** (PR-E, 2,5 dias) —
   N interfaces idênticas (uma por SGBD) consolidadas em ports
   genéricos + base classes; reduz custo de adicionar SGBDs em ~70%

**Esforço total**: 8,5 dias úteis. **Linhas líquidas**: −1175 (eliminação)
+ design system. **ROI**: adicionar o 5º SGBD passa de ~5 dias para
~1,5 dia + identidade visual consistente em toda a UI.

---

## 1. Auditoria — Bugs e Code Smells Encontrados

### 1.1 Bugs latentes

| # | Bug | Arquivo | Severidade |
|---|---|---|---|
| **B1** | `enum DatabaseType { sqlServer, sybase, postgresql }` **duplicado** em `lib/presentation/widgets/sql_server/sql_server_config_dialog.dart:16` paralelo ao `lib/domain/entities/schedule.dart:8` | `sql_server_config_dialog.dart` | **Alta** |
| **B2** | `SqlServerConfigDialog._initState` "adivinha" tipo da config por heurística (`port == 2638 \|\| database.endsWith('.db')` → Sybase) | `sql_server_config_dialog.dart:84-89` | **Alta** |
| **B3** | `_showPostgresConfigDialog` **converte `PostgresConfig` em `SqlServerConfig` temporário** e espera `PostgresConfig` de volta | `database_config_page.dart:316-380` | **Alta** |
| **B4** | Mensagem hardcoded "psql não encontrado no PATH" duplicada — texto idêntico ao `ToolPathHelp.buildMessage('psql')` | `sql_server_config_dialog.dart:951` | Média |
| **B5** | `PortNumber.isDefault` retorna `true` apenas para 1433/3306/5432 — não inclui 2638 (Sybase) nem 3050 (Firebird) | `port_number.dart:17` | Baixa |
| **B6** | `int.parse(_portController.text)` sem `tryParse` em pontos críticos | `sql_server_config_dialog.dart:1116` | Média |
| **B7** | `String _t(String pt, String en)` definido inline em **17 widgets** ignorando `appLocaleString(context, ...)` que **já existe** | 17 arquivos | Baixa |
| **B8** | `SybaseConfigListItem` e `SqlServerConfigListItem` existem, `PostgresConfigListItem` **não** — assimetria | `widgets/postgres/` | Baixa |
| **B9** | `SqlServerConfigDialog` (42 KB!) é "god dialog" que aceita 3 SGBDs via flag `initialType` e branches `if (_selectedType == X)` em ~30 pontos | `sql_server_config_dialog.dart` (1200 linhas) | **Alta** |
| **B10** | `_testConnection` em god dialog tem **~370 linhas** com 3 ramos repetindo o mesmo padrão | `sql_server_config_dialog.dart:731-1109` | **Alta** |
| **B11** | `BackupOrchestratorService._estimateRequiredSpaceBytes` faz `switch (databaseType)` que difere apenas em cast e service (anti-pattern 5.8 do `architectural_patterns.mdc`) | `backup_orchestrator_service.dart:638-686` | Média |

### 1.2 Code smells (duplicação)

| # | Code smell | Linhas duplicadas |
|---|---|---|
| **C1** | `_storePasswordOrThrow` triplicado em SqlServer/Sybase/Postgres repos | ~30 |
| **C2** | `_calculateBackupSize` / `_calculateFileSize` em PG + SQL Server + Sybase services | ~80 |
| **C3** | `_safeDeletePartialBackup` + `_waitForStableBackupFile` (SQL Server, faltando nos outros) | ~50 |
| **C4** | `switch DatabaseType` duplicado (label/cor) em 4 widgets | ~40 |
| **C5** | `SqlServerConfigList`, `SybaseConfigList`, `PostgresConfigGrid` virtualmente idênticos | ~230 |
| **C6** | `SqlServerConfigListItem` e `SybaseConfigListItem` virtualmente idênticos | ~50 |
| **C7** | Boilerplate `_testConnection` (validate → loading → fold → mensagem → mounted check) em 2 dialogs | ~150 |
| **C8** | Extração textual `failure.message vs failure.toString()` repetida | ~30 |
| **C9** | Constantes de prefixo de secure storage espalhadas | trivial |
| **C10** | Diálogos "Confirma duplicar?" implementados inline em vez de helper | ~30 |
| **C11** | `*ConfigProvider` (3 cópias) com mesma estrutura `loadConfigs/createConfig/updateConfig/deleteConfig/toggleEnabled/duplicateConfig` | ~250 |
| **C12** | `*ConfigRepository` (3 cópias) com `getAll/getById/create/update/delete/getEnabled` quase idênticos | ~180 |
| **C13** | `I*BackupService` (3 interfaces) com mesmas assinaturas | ~120 |

### 1.3 UI/UX — 10 oportunidades

| # | Item | Estado atual | Proposta |
|---|---|---|---|
| **U1** | `_SectionHeader` mostra apenas count total | "SQL Server (5)" | "SQL Server (5) — 3 ativas, 2 inativas" |
| **U2** | Seção com 0 configs some completamente | seção oculta | Placeholder "+ Adicionar SQL Server" |
| **U3** | Nenhum feedback persistente do "Testar conexão" | só `MessageModal` flash | `lastTestedAt` + `lastTestStatus` no provider |
| **U4** | Dialogs não respondem a `Enter`/`Esc` | precisa clicar | Atalhos via `Shortcuts` |
| **U5** | `PasswordField` sem toggle "mostrar senha" | sempre oculta | IconButton com olho |
| **U6** | Diálogo de duplicar força nome `"X (cópia)"` | confirma e duplica | TextBox editável |
| **U7** | `schedule_dialog.dart` (84 KB) form gigante | scroll infinito | TabView por seção |
| **U8** | Ícone fixo `database` para todos SGBDs | sem diferenciação | `DatabaseTypeMetadata.of(type).icon` |
| **U9** | Cores SGBDs arbitrárias | pastéis genéricos | Cores oficiais (MS SQL #CC2927, Firebird #F40F02) |
| **U10** | `MessageModal` modal bloqueante para sucessos | sempre modal | `InfoBar` não-bloqueante |

---

## 2. Análise Arquitetural — Hexagonal / Ports & Adapters

### 2.1 Estado atual: já é Clean Architecture, parcialmente hexagonal

O projeto declara "Clean Architecture + DDD" em `project_specifics.mdc`
e a estrutura cumpre estritamente os limites de camada. Em terminologia
hexagonal (Alistair Cockburn):

| Conceito hexagonal | Onde já existe |
|---|---|
| **Driving ports** (inbound) | `IDatabaseBackupStrategy`, `IBackupCancellationService` |
| **Driven ports** (outbound) | `I*Repository` (15 interfaces), `I*Service` (35+) |
| **Driving adapters** | `presentation/`, `socket/server/*MessageHandler` |
| **Driven adapters** | `infrastructure/repositories/`, `infrastructure/external/` |

Os **34 arquivos `i_*.dart`** em `lib/domain/` são literalmente os
"ports". A Dependency Inversion já está cumprida.

### 2.2 Problema arquitetural identificado: ports duplicados por SGBD

```
ports/interfaces:
  ISqlServerBackupService    ┐
  ISybaseBackupService       │  3 interfaces idênticas
  IPostgresBackupService     ┘  (mesmas 4 assinaturas)

  ISqlServerConfigRepository ┐
  ISybaseConfigRepository    │  3 interfaces CRUD genéricas
  IPostgresConfigRepository  ┘

application providers:
  SqlServerConfigProvider    ┐
  SybaseConfigProvider       │  3 providers ~95% idênticos
  PostgresConfigProvider     ┘  (CRUD + AsyncStateMixin)

domain entities:
  SqlServerConfig            ┐  3 entities sem hierarquia comum;
  SybaseConfig               │  campos compartilhados (id, name,
  PostgresConfig             ┘  host/port/username/password) repetidos
```

**Sintoma**: adicionar Firebird como 4º SGBD requer ~700 linhas. Isso
viola **OCP** — adicionar SGBD modifica orchestrador, DI, presentation,
em ~20 pontos.

### 2.3 Solução: ports genéricos + base classes (PR-D)

Aplicar **Generics + Template Method**, criando 6 abstrações:

1. **`DatabaseConnectionConfig`** abstract base entity (campos universais)
2. **`IDatabaseConfigRepository<T>`** + **`BaseDatabaseConfigRepository<T,TData>`** (Template Method)
3. **`IDatabaseBackupPort<T>`** + **`BackupExecutionContext`** (DTO encapsula 12 args)
4. **`DatabaseConfigProviderBase<T>`** (provider genérico)
5. **`GenericDatabaseBackupStrategy<T>`** + **`BackupValidationRule<T>`** + **`BackupResultEnricher<T>`**
6. **DI helper `registerSgbd<TConfig,TData>`** — extension method

**Marker interfaces preservam back-compat** —
`ISqlServerBackupService extends IDatabaseBackupPort<SqlServerConfig>`
mantém testes existentes intactos.

### 2.4 Impacto medido

| Métrica | Antes do PR-D | Depois do PR-D |
|---|---|---|
| Linhas para repository novo | ~152 | ~50 |
| Linhas para provider novo | ~150 | ~30 |
| Linhas para strategy nova | ~100 | ~25 |
| Linhas para registrar em DI | ~40 | ~6 |
| **Total para SGBD novo** | **~700 linhas** | **~250 linhas** |
| **Tempo para adicionar SGBD** | **~5 dias** | **~1,5 dia** |

### 2.5 SOLID — princípios reforçados pelo PR-D

| Princípio | Estado anterior | Após PR-D |
|---|---|---|
| **SRP** | `SybaseBackupStrategy.execute` faz 5 coisas inline | Cada `Rule`/`Enricher` é classe isolada |
| **OCP** | Adicionar SGBD modifica 20 pontos | Adicionar SGBD = registrar Rules/factory/DI |
| **LSP** | Configs sem hierarquia comum | `DatabaseConnectionConfig` permite substituição |
| **ISP** | `I*BackupService` mistura execução, teste, listagem | Mantém ports coesos; `IDatabaseConfigRepository<T>` separa CRUD |
| **DIP** | Já cumprido | Reforçado — application depende de port genérico |

---

## 3. Pesquisa — Boas Práticas Modernas (Flutter/Dart 2026)

Pesquisa em [`codewithandrea.com`](https://codewithandrea.com/articles/flutter-project-structure/),
[Flutter Studio](https://flutterstudio.dev/blog/flutter-clean-architecture.html),
[`pub.dev/freezed`](http://pub.dev/packages/freezed),
[`very_good_analysis`](https://github.com/VeryGoodOpenSource/very_good_analysis)
e Medium articles publicados em 2026.

### 3.1 O que o projeto já faz bem ✅

| Prática 2026 | Estado no projeto |
|---|---|
| Clean Architecture (Domain → Application → Infrastructure → Presentation) | ✅ Aplicada com rigor; documentada em `clean_architecture.mdc` |
| Repository Pattern com interfaces no Domain (DIP) | ✅ 15 interfaces em `domain/repositories/` |
| Result pattern em vez de exceptions (`result_dart`) | ✅ Adotado consistentemente |
| Dependency Injection (`get_it`) | ✅ DI modular em `core/di/*` |
| Linter strict (`very_good_analysis 10.x`) | ✅ Configurado em `analysis_options.yaml` |
| State management com `Provider` + `ChangeNotifier` | ✅ + helper consolidado `AsyncStateMixin` |
| Testes unitários organizados em `test/unit/<layer>/` | ✅ Cobertura razoável |

### 3.2 Adoções recomendadas (alinhadas a 2026)

#### 3.2.1 Folder structure: feature-first vs layer-first

**Tendência 2026**: feature-first é considerado superior para apps em
crescimento (fonte:
[CodeWithAndrea](https://codewithandrea.com/articles/flutter-project-structure/)).

**Estado atual**: layer-first (`lib/domain/`, `lib/infrastructure/`, etc.).

**Custo de migração**: alto (centenas de imports a reorganizar). **ROI**:
moderado, principalmente para times grandes.

**Recomendação**: **NÃO migrar agora**. O projeto é "single feature de
backup" com forte coesão; a estrutura por camadas funciona bem aqui.
Considerar migração futura se surgirem features ortogonais (ex.:
gerenciamento de licenças, dashboard analytics, módulo de
auditoria) que justifiquem isolamento. Documentar como decisão
arquitetural em ADR.

#### 3.2.2 `freezed` para entities (eliminar boilerplate)

**Pacote**: [`freezed 3.2+`](https://pub.dev/packages/freezed) +
`freezed_annotation`.

**O que elimina**:
- `==` operator + `hashCode` manuais
- `copyWith` manual (~15 linhas por entity)
- `toString` para debug
- Sealed classes nativas (Dart 3.0+) com pattern matching

**Estado atual**: cada entity (`SqlServerConfig`, `SybaseConfig`,
`PostgresConfig`) implementa manualmente:
- `copyWith` (~20 linhas)
- `==`/`hashCode` por id (~5 linhas)
- Total: ~25 linhas de boilerplate × 7 entities = ~175 linhas

**Após adoção**: ~5 linhas por entity (anotação `@freezed` + classe).

**Custo de migração**: 1-2 dias para entities; rodar `build_runner`.

**Recomendação**: **adotar como item M1 do roadmap futuro** (não
bloqueia Firebird, mas elimina muito código). Priorizar quando
`DatabaseConnectionConfig` (PR-D) estabilizar — assim o freezed
codegen entende a hierarquia desde o início.

#### 3.2.3 Sealed classes + pattern matching (Dart 3+)

**Aplicação**: state machines (ex.: `BackupStatus`, `ConnectionState`)
e Result types específicos.

**Estado atual**: `BackupStatus` é enum simples (`enum BackupStatus
{ pending, running, success, error, warning, cancelled }`); funciona
mas perde poder expressivo.

**Onde compensa**: `TestConnectionOutcome` introduzido no PR-C5 será
sealed class:

```dart
sealed class TestConnectionOutcome {
  const TestConnectionOutcome();
}
class TestConnectionSuccess extends TestConnectionOutcome {
  const TestConnectionSuccess({this.detectedVersion});
  final String? detectedVersion;
}
class TestConnectionInvalid extends TestConnectionOutcome {
  const TestConnectionInvalid(this.message);
  final String message;
}
class TestConnectionError extends TestConnectionOutcome {
  const TestConnectionError(this.message);
  final String message;
}

// Uso com switch expression exaustivo:
final widget = switch (outcome) {
  TestConnectionSuccess(:final detectedVersion) => SuccessBanner(detectedVersion),
  TestConnectionInvalid(:final message) => WarningBanner(message),
  TestConnectionError(:final message) => ErrorBanner(message),
};
```

**Recomendação**: **usar em código novo (PR-C5 em diante)**. Não
migrar enums existentes (custo > benefício para 1 SGBD novo).

#### 3.2.4 `analysis_options.yaml` — re-habilitar regras desligadas

Auditoria do `analysis_options.yaml` atual mostra **15 regras
desligadas**. Algumas valem ser revisadas:

| Regra desligada | Risco | Recomendação |
|---|---|---|
| `avoid_dynamic_calls: false` | Alto — pode esconder bugs | Reabilitar; cobrir exceções com `// ignore: avoid_dynamic_calls` por linha |
| `unawaited_futures: false` | Médio — fire-and-forget escondido | Reabilitar; usar `unawaited(future)` explícito quando intencional |
| `cascade_invocations: false` | Estilo | Manter desligado (preferência do time) |
| `no_default_cases: false` | Médio — exhaustive switch perde força | Reabilitar; força `default:` explícito |
| `discarded_futures` | Alto — mesmo problema do `unawaited_futures` | **Ligado** no repo (2026-05-15); `flutter analyze` 0 issues |
| `use_late_for_private_fields_and_variables: false` | Baixo | Manter desligado (já temos AsyncStateMixin) |
| `lines_longer_than_80_chars: false` | Estilo | Manter desligado (linhas longas em SQL inline) |

**Recomendação**: **adicionar como item M2 do roadmap futuro** — PR
dedicado de "lint cleanup" para reabilitar 3-4 regras de alta
relevância e tratar warnings que aparecerem.

#### 3.2.5 `equatable_gen` como alternativa leve ao freezed

Se o time achar `freezed` overkill, `equatable_gen` gera apenas
`props` para igualdade por valor, sem mexer em copyWith/toString.

**Recomendação**: avaliar com o time. `freezed` é a escolha
"production-grade 2026"; `equatable_gen` é menor disrupção.

#### 3.2.6 Documentação ADR (Architectural Decision Records)

Já existe `docs/adr/` no projeto (`001-modelo-hibrido-scheduler.md`,
`002-transferencia-v1-streaming-sem-fileack.md`,
`003-versionamento-protocolo.md`). Padrão estabelecido e recomendado.

**Recomendação**: **registrar como ADR-004**: "Adoção de Generic
Hexagonal Ports para SGBDs" (depois do PR-D). E **ADR-005**: "Decisão
sobre folder structure (manter layer-first)" para evitar discussão
recorrente. **Estado (2026-05-15)**: ADR-004 e ADR-005 constam em
`docs/adr/` e no indice de `docs/adr/README.md`.

### 3.3 Recomendações que NÃO se aplicam aqui

| Recomendação 2026 | Por que não aplicar |
|---|---|
| Migrar de `result_dart` para `fpdart` `Either<L,R>` | Custo alto; `result_dart` cumpre o mesmo papel; time já familiar |
| Adotar Riverpod em vez de Provider | Mudança massiva; Provider já documentado no `project_specifics.mdc` |
| Adotar BLoC em vez de Provider | Idem |
| Substituir `get_it` por `injectable + get_it` | Codegen extra com benefício marginal |
| Migrar para `fluent_ui` mais novo via major | Sem necessidade clara |

### 3.4 Anti-patterns confirmados na literatura 2026

A pesquisa confirmou que o **God Class anti-pattern** é amplamente
documentado como problema em Flutter ([Iman Mesgaran 2026](https://www.linkedin.com/pulse/7-god-object-class-anti-pattern-flutter-dart-iman-mesgaran-nrruf)).
A receita de cura é exatamente o que o **PR-D5** aplica:
decomposição de widgets, separação de concerns via layers, smaller
focused components.

Outros anti-patterns confirmados que **já evitamos** ou **vamos
corrigir**:
- ✅ Repository Pattern direto na UI (já usamos via Provider)
- ⚠️ Switch with similar cases (B11/D2 — corrigido em PR-B/PR-D)
- ⚠️ Inline business logic em widgets (B9/B10 — corrigido em PR-D)
- ⚠️ Duplicate enums (B1 — corrigido em PR-A)
- ✅ Direct DB access in widgets (não acontece)
- ⚠️ **Inheritance abuse em widgets** — corrigido pelo PR-C (regra
  explícita "composition over inheritance" + slot pattern)
- ⚠️ **Magic numbers em layout** (`SizedBox(height: 16)` espalhado em
  centenas de pontos) — corrigido pelo PR-C (`AppSpacing` tokens)
- ⚠️ **Cores hardcoded sem semântica** (`Color(0xFF4CAF50)` repetido) —
  corrigido pelo PR-C (`ThemeExtension<AppSemanticColors>`)

---

## 4. Design System & Componentização — Diagnóstico e Princípios

### 4.1 Estado atual do Design System

| Item | Estado | Problema |
|---|---|---|
| `lib/core/theme/app_colors.dart` | Lista flat de **50+ cores** com nomes mistos (`primary`, `databaseSqlServer`, `googleDriveSignedInBackground`) | Sem agrupamento semântico; difícil saber "qual cor usar para feedback de erro?" sem conhecer o catálogo |
| `lib/core/theme/app_theme.dart` | Mantém `lightFluentTheme/darkFluentTheme` (Fluent UI ativo) **e** `lightTheme/darkTheme` (Material) | Material themes praticamente não usados — dead code potencial |
| Spacing | `SizedBox(height: 8)`, `SizedBox(height: 16)`, `SizedBox(width: 12)` espalhados em **centenas de pontos** | Impossível garantir consistência; alterar "padding default" é caça ao tesouro |
| Radius | `BorderRadius.circular(8)`, `BorderRadius.circular(12)` hardcoded | Idem |
| Elevation | Hardcoded em cards | Idem |
| Motion (duration/easing) | Hardcoded `Duration(milliseconds: 300)` | Idem |
| `ThemeExtension` | **Não usado** | Theme não tem dados customizados; tudo cai em `AppColors.X` (acesso global) |
| Atomic Design hierarchy | Pasta única `widgets/common/` mistura átomos (`AppButton`, `AppTextField`), moléculas (`PasswordField`, `SaveButton`) e organismos (`MessageModal`, `ConfigListItem`) | Dificulta navegação e identificação do "nível" do componente |
| Composition vs Inheritance | Sem regra documentada; `AppButton` tem ramo `if (icon != null) {...} else {...}` em vez de slot pattern | Pequenos componentes ficam infláveis com flags booleanas |
| Cores SGBDs/Schedule/Backup status | Definidas em `AppColors` ao lado das cores primitivas (`databaseSqlServer`, `scheduleDaily`, `backupSuccess`) | Cores semânticas misturadas com cores primitivas; difícil revisar paleta |
| Identidade visual entre temas Light/Dark | Validação manual case-a-case; sem `lerp` automático para cores customizadas | Dark mode pode ficar inconsistente |

### 4.2 Princípios de Design System (alvo após PR-C)

Adotamos a metodologia **Atomic Design** (Brad Frost) adaptada ao
Flutter, conforme [Rodrigo Nepomuceno 2026 (Medium)](https://rodrigonepomuceno.medium.com/atomic-design-in-flutter-modular-ui-architecture-with-design-systems-72f813c18af4):

```
Hierarquia (do mais primitivo ao mais complexo):

  Tokens     → cores, spacing, radius, elevation, motion, typography
     │
     ▼
  Átomos     → AppButton, AppTextField, AppCard, AppIcon, PasswordField
     │
     ▼
  Moléculas  → DatabaseConfigDialogShell, _SectionHeader,
               TestConnectionRunner, FormFieldRow
     │
     ▼
  Organismos → DatabaseConfigDataGrid<T>, DatabaseConfigListItem<T>,
               MessageModal, ScheduleDialogTabs
     │
     ▼
  Páginas    → DatabaseConfigPage, DashboardPage, SchedulesPage
```

### 4.3 Regras-chave (princípios documentados em `architectural_patterns.mdc`)

#### 4.3.1 Composition over inheritance (regra principal)

Adotada como diretriz oficial após pesquisa ([VibeStudio 2026](https://vibe-studio.ai/insights/building-flutter-widgets-using-composition-over-inheritance),
[KotlinCodes](https://kotlincodes.com/flutter-dart/advanced-concepts/understanding-flutters-composition-over-inheritance-philosophy/)):

```dart
// ❌ EVITAR — herança com flags booleanas
class AppButton extends StatelessWidget {
  final bool isPrimary;
  final bool isLoading;
  final IconData? icon;
  // 4 ramos no build() para combinar flags
}

// ✅ PREFERIR — slot pattern + factory constructors
class AppButton extends StatelessWidget {
  const AppButton({
    required this.onPressed,
    this.leading,    // slot (Widget? — pode ser ícone, spinner, badge)
    required this.label,
    this.trailing,   // slot
    this.variant = ButtonVariant.standard,  // enum, não flag
  });

  // Factories declarativas para casos comuns
  factory AppButton.primary({...}) => AppButton(variant: ButtonVariant.primary, ...);
  factory AppButton.icon(IconData icon, {...}) =>
      AppButton(leading: Icon(icon), ...);
  factory AppButton.loading() => AppButton(
        leading: const ProgressRing(strokeWidth: 2),
        label: '',
      );
}
```

**Justificativa**:
- Componentes mais flexíveis (combinar leading+trailing+label livremente)
- Sem explosão combinatória de booleanas
- Factory constructors documentam casos canônicos sem esconder a API base
- Testes mais simples (1 widget, N variantes via factory)

#### 4.3.2 Quando usar `extends` vs `with` vs `implements`

Adaptado de [Shubham Jain 2026 (Medium)](https://building.theatlantic.com/a-practical-guide-for-flutter-developers-to-choose-between-inheritance-interfaces-and-mixins-2baf312d36d0):

| Mecanismo | Quando usar | Exemplo no projeto |
|---|---|---|
| `extends` | Apenas para "is-a" forte: especialização real, mesma família | `SqlServerConfig extends DatabaseConnectionConfig` (PR-E) — todos são "config de banco" |
| `with` (mixin) | Reúso de comportamento sem hierarquia | `AsyncStateMixin` (já usado), `RouteAware`, `SingleTickerProviderStateMixin` |
| `implements` | Contrato sem reúso de implementação | `IDatabaseBackupPort<T>`, marker interfaces (PR-E) |
| Composição via slot/builder | Casos onde "is-a" não se aplica claramente | **Default para widgets** |

#### 4.3.3 Atomic Design folder hierarchy (futuro — M8 do roadmap)

A migração da pasta `widgets/common/` para `widgets/atoms/`,
`widgets/molecules/`, `widgets/organisms/` é uma melhoria
**desejável mas não-bloqueante** — fica como item M8 do roadmap.
Por enquanto, o PR-C documenta o nível de cada componente em
doc-comment:

```dart
/// **Atom** — botão atômico do design system; combine via slots
/// (`leading`/`trailing`) em vez de subclassar.
class AppButton extends StatelessWidget { ... }

/// **Molecule** — combina `AppTextField` + `IconButton` para
/// senha com toggle de visibilidade.
class PasswordField extends StatelessWidget { ... }

/// **Organism** — grid completo com colunas, ações e empty state.
class DatabaseConfigDataGrid<T> extends StatelessWidget { ... }
```

#### 4.3.4 Tokens semânticos sempre via `Theme.of(context).extension<X>()`

Cores, spacing e demais tokens são acessados pelo `BuildContext` (não
por `AppColors.X` global), garantindo que dark mode e temas
alternativos funcionem automaticamente:

```dart
// ❌ EVITAR — acesso direto à constante (não responde a tema)
Container(color: AppColors.surfaceLight)

// ✅ PREFERIR — via ThemeExtension
final colors = Theme.of(context).extension<AppSemanticColors>()!;
Container(color: colors.surface)

// ✅ TAMBÉM ACEITÁVEL — token primitivo (cor de marca fixa)
Container(color: AppPalette.brandPrimary)  // imutável entre temas
```

### 4.4 Tokens novos a criar no PR-C

| Token | Arquivo | Conteúdo |
|---|---|---|
| **`AppPalette`** | `lib/core/theme/tokens/app_palette.dart` | Cores primitivas imutáveis (palette de marca). Renomeado a partir do `AppColors` atual, mas só com cores que NÃO mudam entre temas (cores de SGBDs, marcas, status absolutos). |
| **`AppSpacing`** | `lib/core/theme/tokens/app_spacing.dart` | `xs (4)`, `sm (8)`, `md (16)`, `lg (24)`, `xl (32)`, `xxl (48)` |
| **`AppRadius`** | `lib/core/theme/tokens/app_radius.dart` | `sm (4)`, `md (8)`, `lg (12)`, `xl (16)`, `pill (999)` |
| **`AppElevation`** | `lib/core/theme/tokens/app_elevation.dart` | `none (0)`, `low (2)`, `medium (4)`, `high (8)` |
| **`AppDuration`** | `lib/core/theme/tokens/app_duration.dart` | `fast (150ms)`, `normal (250ms)`, `slow (400ms)` |
| **`AppCurves`** | `lib/core/theme/tokens/app_curves.dart` | `standard (Curves.easeInOut)`, `decelerate`, `accelerate` |
| **`AppTypographyScale`** | `lib/core/theme/tokens/app_typography_scale.dart` | Escala explícita (display/title/body/caption) — wrappers de `FluentTheme.typography` para uso fora de Fluent |
| **`AppSemanticColors`** | `lib/core/theme/extensions/app_semantic_colors.dart` | `ThemeExtension` com cores semânticas: `success`, `warning`, `danger`, `info`, `surface`, `surfaceVariant`, `onSurface`, `outline`, `divider`, `disabled`, etc. — MUDAM entre Light/Dark |
| **`AppBreakpoints`** | `lib/core/theme/tokens/app_breakpoints.dart` | `compact (< 720px)`, `medium (720-1024)`, `wide (1024-1440)`, `ultrawide (> 1440)`. Mesmo o app sendo desktop-only, janelas redimensionáveis exigem breakpoints internos para grids/cards |
| **`AppDensity`** | `lib/core/theme/tokens/app_density.dart` | `compact (-1)`, `comfortable (0)`, `spacious (+1)` — multiplicador de spacing/sizing. Padrão Windows é `comfortable`; usuários power podem preferir `compact` para mais densidade de informação (data grids) |
| **`AppTargetSize`** | `lib/core/theme/tokens/app_target_size.dart` | `minimum (44)` — WCAG 2.1 AA target mínimo para click/tap; `comfortable (48)` — recomendado Material; usado em validações de a11y |
| **`AppZIndex`** | `lib/core/theme/tokens/app_z_index.dart` | Camadas para `Stack`/overlays: `base (0)`, `dropdown (100)`, `tooltip (200)`, `modal (300)`, `snackbar (400)`, `notification (500)` |
| **`AppSpacing` extension on `BuildContext`** | mesmo arquivo | `context.appSpacing.md` para acesso conciso; aplica `AppDensity` automaticamente quando registrado |

### 4.5 Identidade visual — responsabilidades documentadas

Após PR-C, `architectural_patterns.mdc` ganha seção 8 com regras:

1. **Cores de marca/SGBD** (`AppPalette.databaseSqlServer`,
   `AppPalette.databaseFirebird`) ficam em `AppPalette` — imutáveis,
   const, sem variação entre temas. Acesso direto OK.
2. **Cores semânticas** (`success`/`warning`/`danger`/`surface`) ficam
   em `AppSemanticColors` ThemeExtension — VARIAM entre Light/Dark.
   Acesso obrigatório via `Theme.of(context).extension()`.
3. **Spacing/Radius/Elevation/Motion** — sempre via tokens, nunca
   hardcoded. Lint custom (M9 do roadmap) pode falhar quando detectar
   `SizedBox(height: 12)` literal em widgets do projeto.
4. **Componentes do design system** ficam em `widgets/common/` (ou
   `atoms/molecules/organisms/` no M8). Componentes de feature ficam
   em `widgets/<feature>/`.
5. **Doc-comment obrigatório** sinalizando o nível atomic do componente
   (`/// **Atom**`, `/// **Molecule**`, `/// **Organism**`).
6. **Composition over inheritance** é regra default. Inheritance só
   permitida para "is-a" forte (ex.: `SqlServerConfig extends
   DatabaseConnectionConfig`). Widget novo com `extends` que não seja
   `StatelessWidget`/`StatefulWidget` precisa justificativa em
   doc-comment.
7. **Responsivo dentro do desktop**: usar `AppBreakpoints` para
   componentes que respondem ao tamanho da janela (data grids,
   sidebars). Evitar `MediaQuery.of(context).size.width > X` literal.
8. **Densidade configurável**: aplicar `AppDensity` em data grids e
   formulários longos para permitir o usuário escolher entre
   `comfortable` (default) e `compact` (mais informação por tela).
9. **Acessibilidade (a11y) obrigatória**:
   - Targets clicáveis ≥ `AppTargetSize.minimum` (44px) — WCAG 2.1 AA
   - Contraste de texto ≥ 3:1 (validado via `textContrastGuideline`
     em testes)
   - Toda imagem decorativa tem `excludeFromSemantics: true`
   - Toda imagem informativa tem `semanticLabel`
   - Componentes customizados (ex.: `DatabaseConfigListItem`) usam
     `Semantics(label:, hint:, button: true)` quando aplicável
   - Suporte a navegação por teclado (`Tab`/`Esc`/`Enter`/atalhos)
   - Texto suporta escala dinâmica do sistema (`MediaQuery.textScaler`)
10. **Z-index explícito**: usar `AppZIndex` em `Stack`/overlays em vez
    de ordem implícita por posição na lista de children. Reduz bugs
    de "modal aparece atrás do dropdown".

---

## 5. Faseamento (5 PRs sequenciais)

```
┌──────────────────────────────────────────────────────────────────┐
│ PR-A  Bug fixes críticos              (1 dia)   →   −5 linhas    │
│        Estabilização sem refator estrutural                      │
├──────────────────────────────────────────────────────────────────┤
│ PR-B  Refator DRY domínio/infra       (1.5 dia) →  −220 linhas   │
│        6 helpers consolidados (camada 1)                         │
├──────────────────────────────────────────────────────────────────┤
│ PR-C  Design System foundation        (1.5 dia) → ~ 0 linhas     │
│        Tokens (spacing/radius/motion) + ThemeExtension semântica │
│        + AppPalette + regras "composition over inheritance"      │
├──────────────────────────────────────────────────────────────────┤
│ PR-D  Refator DRY UI + UX             (2 dias)  →  −520 linhas   │
│        God dialog quebrado, grids genéricos, +4 UX wins          │
│        (consome design system do PR-C)                           │
├──────────────────────────────────────────────────────────────────┤
│ PR-E  Hexagonal: ports + base classes (2.5 dias) → −430 linhas   │
│        DatabaseConnectionConfig + IDatabaseBackupPort<T> +       │
│        Base repository/provider; SGBD-ready                      │
└──────────────────────────────────────────────────────────────────┘
                            Total: 8.5 dias / −1175 linhas (líquido)
```

Cada PR entrega valor isolado e pode ser mergeado independentemente. Os
5 PRs juntos **destravam** a adição do Firebird (plano companheiro)
e **reduzem em 70%** o custo de qualquer SGBD futuro, além de
consolidar a identidade visual do app via design system.

---

## 6. PR-A — Bug fixes críticos

**Objetivo**: corrigir bugs detectados em auditoria sem mudar
arquitetura.

**Esforço**: 1 dia. **Critério**: zero regressão funcional.

### TODO list

- [x] **A1** — Eliminar `enum DatabaseType` duplicado (B1)
  - [x] Fonte única: `lib/domain/entities/schedule.dart` (`rg "enum DatabaseType"` só encontra esta)
  - [x] PR-D quebrou o god dialog; `sql_server_config_dialog.dart` não declara mais enum paralelo
- [x] **A2** — Remover heurística de detecção de tipo (B2)
  - [x] Absorvido pelo PR-D (dialogs por SGBD + fluxo na página de configs)
- [x] **A3** — Substituir mensagem hardcoded de psql por `ToolPathHelp` (B4)
  - [x] `postgres_config_dialog.dart` usa `ToolPathHelp.buildMessage('psql')` / `isToolNotFoundError`
- [x] **A4** — `int.tryParse` defensivo (B6)
  - [x] `sql_server_config_dialog.dart` usa `int.tryParse` nos pontos de porta relevantes
- [x] **A5** — `PortNumber.isDefault` atualizado ou deprecado (B5)
  - [x] `port_number.dart` inclui **2638** (Sybase) e **3050** (Firebird) em `isDefault`
  - [x] **Teste**: `test/unit/domain/value_objects/port_number_test.dart`

### Notas

- B3, B9, B10 (god dialog) **não** eram escopo do PR-A; foram tratados no
  **PR-D** (dialogs por SGBD + `DatabaseConfigDialogShell` / runner).
- Cada item em commit separado para facilitar `git bisect`

---

## 7. PR-B — Refator DRY de domínio/infra

**Objetivo**: extrair 6 padrões duplicados em camadas de domínio e
infraestrutura.

**Esforço**: 1,5 dia. **Critério**: ~220 linhas eliminadas, zero regressão.

### TODO list

- [x] **B1** — `SecureCredentialHelper` (C1)
  - [x] Criar `lib/infrastructure/repositories/secure_credential_helper.dart` com `storePasswordOrThrow/readPasswordOrEmpty/deletePassword`
  - [x] Migrar `SqlServerConfigRepository`, `SybaseConfigRepository`, `PostgresConfigRepository`
  - [x] **Teste**: `test/unit/infrastructure/repositories/secure_credential_helper_test.dart` (cobertura ≥80%)
- [x] **B2** — `SecureCredentialKeys` (C9)
  - [x] Criar `lib/core/constants/secure_credential_keys.dart`
  - [x] Substituir prefixos locais nos 3 repos
  - [x] **Teste**: trivial
- [x] **B3** — `BackupSizeCalculator` (C2)
  - [x] Criar `lib/core/utils/backup_size_calculator.dart` com `ofFile/ofDirectory/ofFiles`
  - [x] Migrar Postgres, SQL Server, Sybase
  - [x] **Teste**: `test/unit/core/utils/backup_size_calculator_test.dart` (≥80%)
- [x] **B4** — `BackupArtifactUtils` (C3)
  - [x] Criar `lib/core/utils/backup_artifact_utils.dart` com `safeDeletePartial/waitForStableFile`
  - [x] Mover métodos do SQL Server service e aplicar nos demais
  - [x] **Teste**: `test/unit/core/utils/backup_artifact_utils_test.dart` (≥80%)
- [x] **B5** — `getDatabaseSizeBytes` na strategy interface (B11)
  - [x] Estender `IDatabaseBackupStrategy` com `getDatabaseSizeBytes({required Object databaseConfig, Duration? timeout})`
  - [x] Implementar nas 3 strategies existentes (cast interno)
  - [x] Refatorar `BackupOrchestratorService._estimateRequiredSpaceBytes` para chamar `strategy.getDatabaseSizeBytes(...)`
  - [x] Eliminar `switch (databaseType)` na linha 648
  - [x] **Teste**: `test/unit/application/services/strategies/database_backup_strategy_get_size_test.dart`
- [x] **B6** — `ToolPathHelp` família Firebird (preparatório)
  - [x] Adicionar `_firebirdTools = {'gbak', 'nbackup', 'gstat', 'isql', 'isql-fb'}`
  - [x] Adicionar case `_ToolFamily.firebird` em `_classify` e `buildMessage`
  - [x] **Teste**: `tool_path_help_test.dart` cobre todas as famílias
- [x] **Documentação**: atualizar `architectural_patterns.mdc` com nova seção "Helpers de Backup"

---

## 8. PR-C — Design System foundation

**Objetivo**: estabelecer base sólida de **tokens semânticos**,
**ThemeExtension**, **regras de composition over inheritance** e
**hierarquia atomic design** documentada. Pré-requisito do PR-D —
todos os widgets refatorados no PR-D já consomem este design system.

**Esforço**: 1,5 dia. **Critério**: zero regressão visual; tokens
adotados em pelo menos 5 widgets atômicos como prova de conceito;
`architectural_patterns.mdc` ganha seção "Design System".

### Etapa 1 — Reorganização de cores (`AppPalette` vs `AppSemanticColors`)

- [x] **C0.1** — Criar `lib/core/theme/tokens/app_palette.dart`
  - [x] Migrar do atual `AppColors`: cores **imutáveis** entre temas
        (cores de marca, SGBD, status absolutos):
        `databaseSqlServer/Sybase/Postgresql/Firebird`,
        `destinationLocal/Ftp/GoogleDrive/Dropbox/Nextcloud`,
        `scheduleDaily/Weekly/Monthly/Interval`, `googleDriveSignedIn`
  - [x] Atualizar para cores oficiais (U9):
    - `databaseSqlServer = Color(0xFFCC2927)` (Microsoft red)
    - `databaseSybase = Color(0xFF009688)` (Sybase teal — manter)
    - `databasePostgresql = Color(0xFF336791)` (Postgres blue — manter)
    - `databaseFirebird = Color(0xFFF40F02)` (Firebird red — preparatório)
  - [x] Construtor privado `AppPalette._()` com cores `static const`
  - [x] **Teste**: `app_palette_test.dart` valida que cores são `const`

- [x] **C0.2** — Criar `lib/core/theme/extensions/app_semantic_colors.dart`
      como `ThemeExtension<AppSemanticColors>`:
  ```dart
  class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
    const AppSemanticColors({
      required this.success,
      required this.warning,
      required this.danger,
      required this.info,
      required this.surface,
      required this.surfaceVariant,
      required this.onSurface,
      required this.outline,
      required this.divider,
      required this.disabled,
    });

    final Color success;
    final Color warning;
    final Color danger;
    final Color info;
    final Color surface;
    final Color surfaceVariant;
    final Color onSurface;
    final Color outline;
    final Color divider;
    final Color disabled;

    static const light = AppSemanticColors(/* paleta clara */);
    static const dark = AppSemanticColors(/* paleta escura */);

    @override
    AppSemanticColors copyWith({...}) => AppSemanticColors(...);

    @override
    AppSemanticColors lerp(AppSemanticColors? other, double t) =>
        AppSemanticColors(
          success: Color.lerp(success, other?.success, t)!,
          /* ... */
        );
  }

  extension AppSemanticColorsX on BuildContext {
    AppSemanticColors get colors =>
        Theme.of(this).extension<AppSemanticColors>() ??
        AppSemanticColors.light;
  }
  ```
  - [x] **Teste**: `app_semantic_colors_test.dart` valida `lerp` e
        fallback do `extension` getter

- [x] **C0.3** — Atualizar `app_theme.dart` para registrar a extensão:
  ```dart
  static FluentThemeData get lightFluentTheme => theme.copyWith(
    extensions: <ThemeExtension>[AppSemanticColors.light],
    // ... resto
  );
  ```
  Idem para dark
  - [x] **Teste**: widget test confirma que `Theme.of(context).extension<AppSemanticColors>()` retorna instância correta em ambos modos

- [x] **C0.4** — Manter `AppColors` legado como wrapper (sem `@Deprecated` em
      massa para não disparar `deprecated_member_use_from_same_package` em
      centenas de usos internos; remoção gradual via `AppPalette` / tema):
  ```dart
  /// Prefer AppPalette / context.appSemanticColors em código novo.
  class AppColors { ... }
  ```
  - [x] Migração incremental: PRs futuros (D, E, F do firebird) já
        consomem `AppPalette`/`context.appSemanticColors`; código legado fica
        marcado como TODO

### Etapa 2 — Tokens primitivos (spacing/radius/elevation/motion)

- [x] **C0.5** — Criar `lib/core/theme/tokens/app_spacing.dart`
  ```dart
  class AppSpacing {
    AppSpacing._();
    static const double xs = 4;
    static const double sm = 8;
    static const double md = 16;
    static const double lg = 24;
    static const double xl = 32;
    static const double xxl = 48;

    // Atalhos para EdgeInsets comuns
    static const EdgeInsets paddingXs = EdgeInsets.all(xs);
    static const EdgeInsets paddingSm = EdgeInsets.all(sm);
    static const EdgeInsets paddingMd = EdgeInsets.all(md);
    static const EdgeInsets paddingLg = EdgeInsets.all(lg);

    // SizedBox pré-construídos (const = zero-cost)
    static const Widget gapXs = SizedBox(width: xs, height: xs);
    static const Widget gapSm = SizedBox(width: sm, height: sm);
    static const Widget gapMd = SizedBox(width: md, height: md);
    static const Widget gapLg = SizedBox(width: lg, height: lg);
  }
  ```

- [x] **C0.6** — Criar `lib/core/theme/tokens/app_radius.dart`
  ```dart
  class AppRadius {
    AppRadius._();
    static const double sm = 4;
    static const double md = 8;
    static const double lg = 12;
    static const double xl = 16;
    static const double pill = 999;

    static const BorderRadius circularSm = BorderRadius.all(Radius.circular(sm));
    static const BorderRadius circularMd = BorderRadius.all(Radius.circular(md));
    static const BorderRadius circularLg = BorderRadius.all(Radius.circular(lg));
  }
  ```

- [x] **C0.7** — Criar `lib/core/theme/tokens/app_elevation.dart`
  ```dart
  class AppElevation {
    AppElevation._();
    static const double none = 0;
    static const double low = 2;
    static const double medium = 4;
    static const double high = 8;
  }
  ```

- [x] **C0.8** — Criar `lib/core/theme/tokens/app_duration.dart` +
      `app_curves.dart`:
  ```dart
  class AppDuration {
    AppDuration._();
    static const Duration fast = Duration(milliseconds: 150);
    static const Duration normal = Duration(milliseconds: 250);
    static const Duration slow = Duration(milliseconds: 400);
  }

  class AppCurves {
    AppCurves._();
    static const Curve standard = Curves.easeInOut;
    static const Curve decelerate = Curves.decelerate;
    static const Curve accelerate = Curves.fastOutSlowIn;
  }
  ```

- [x] **C0.9** — Criar `lib/core/theme/tokens/app_breakpoints.dart`
  ```dart
  class AppBreakpoints {
    AppBreakpoints._();
    static const double compact = 720;
    static const double medium = 1024;
    static const double wide = 1440;
    // > wide = ultrawide
  }

  extension AppBreakpointsX on BuildContext {
    bool get isCompactWindow =>
        MediaQuery.sizeOf(this).width < AppBreakpoints.compact;
    bool get isMediumWindow =>
        MediaQuery.sizeOf(this).width < AppBreakpoints.medium;
    bool get isWideWindow =>
        MediaQuery.sizeOf(this).width >= AppBreakpoints.medium;
  }
  ```
  - **Justificativa**: mesmo o app sendo desktop-only Windows,
    janelas redimensionáveis exigem layout responsivo (data grids,
    sidebars colapsáveis). Validado em [Saad Ali 2026 (Medium)](https://medium.com/@saadalidev/building-beautiful-responsive-ui-in-flutter-a-complete-guide-for-2026-ea43f6c49b85)
    como prática 2026.

- [x] **C0.10** — Criar `lib/core/theme/tokens/app_density.dart`
  ```dart
  enum AppDensity {
    compact(spacingMultiplier: 0.75, targetSize: 36),
    comfortable(spacingMultiplier: 1, targetSize: 44),
    spacious(spacingMultiplier: 1.25, targetSize: 52);

    const AppDensity({
      required this.spacingMultiplier,
      required this.targetSize,
    });

    final double spacingMultiplier;
    final double targetSize;
  }
  ```
  - [x] Persistir escolha em `IUserPreferencesRepository` (`getUiDensity` /
        `setUiDensity` + `SharedPreferences`); **UI**: Aparência → combo
        "Densidade das tabelas" em `general_settings_tab.dart`;
        `AppDensityProvider` + `InheritedAppDensity`; `AppDataGrid` aplica
        `spacingMultiplier` em paddings e coluna de ações
  - [x] **Teste**: `user_preferences_repository_test.dart`,
        `app_density_provider_test.dart`, harness com
        `InheritedAppDensity` em `app_data_grid_test` /
        `database_config_data_grid_test`
  - **Justificativa**: Windows desktop tem usuários power que
    preferem alta densidade de informação (DBAs olhando 50 schedules
    de uma vez). Densidade configurável é padrão em ferramentas
    pro-grade (VS Code, JetBrains).

- [x] **C0.11** — Criar `lib/core/theme/tokens/app_target_size.dart`
  ```dart
  class AppTargetSize {
    AppTargetSize._();
    /// WCAG 2.1 AA minimum target size for click/tap (44×44 dp)
    static const double minimum = 44;
    /// Material recommended (48×48 dp)
    static const double comfortable = 48;
  }
  ```
  - **Justificativa**: WCAG 2.1 AA exige mínimo 44×44 px para
    targets clicáveis. Documentado em [Flutter docs](https://docs.flutter.dev/ui/accessibility/accessibility-testing).

- [x] **C0.12** — Criar `lib/core/theme/tokens/app_z_index.dart`
  ```dart
  class AppZIndex {
    AppZIndex._();
    static const int base = 0;
    static const int dropdown = 100;
    static const int tooltip = 200;
    static const int modal = 300;
    static const int snackbar = 400;
    static const int notification = 500;
  }
  ```
  - [x] `AppZIndex.stackByZIndex(...)` ordena filhos por constante; uso em
        `backup_progress_dialog.dart` (`_CustomProgressBar`); novos `Stack`
        multi-camada devem preferir este helper em vez de ordem manual
  - **Justificativa**: ordem implícita por children-order é frágil;
    z-index nomeado previne "modal atrás do dropdown"

- [x] **C0.13** — Criar barrel `lib/core/theme/tokens/tokens.dart`
      reexportando todos; `lib/core/theme/theme.dart` exporta
      `tokens/tokens.dart` (inclui `app_palette`).

### Etapa 3 — Refatorar átomos existentes para consumir tokens

Como prova de conceito, refatorar 5 widgets atômicos para usar
tokens em vez de literais:

- [x] **C0.14** — `AppCard` (usar `AppSpacing.paddingMd`,
      `AppRadius.circularLg`, `AppElevation.low`)
- [x] **C0.15** — `AppButton` — refatorar para slot pattern
      (`leading`/`trailing` slots + factories
      `.primary/.icon/.loading`); aplicar `AppSpacing.sm`;
      garantir `AppTargetSize.minimum` mínimo
- [x] **C0.16** — `AppTextField` — usar `AppSpacing.xs` para
      padding interno; `context.colors.danger` para erro
- [x] **C0.17** — `MessageModal` — usar `AppSpacing.paddingLg`,
      `AppDuration.normal` para animação
- [x] **C0.18** — `EmptyState` — usar tokens
- [x] Doc-comments adicionados em cada um sinalizando nível atomic
      (`/// **Atom**`, `/// **Molecule**`, `/// **Organism**`)
- [x] **Acessibilidade**: cada átomo refatorado deve ter
      `Semantics` adequado (label/hint/button) e respeitar
      `AppTargetSize.minimum`
- [x] **Teste regressão crítico**: golden test para `AppCard`,
      `AppButton`, `AppTextField`, `MessageModal`, `EmptyState`
      (`test/golden/widgets/common/design_system_atoms_golden_test.dart`;
      usar `flutter test ... --update-goldens` quando o layout mudar de
      forma intencional)
- [x] **Teste a11y**: `meetsGuideline(androidTapTargetGuideline)` +
      `meetsGuideline(iOSTapTargetGuideline)` +
      `meetsGuideline(textContrastGuideline)` com `ensureSemantics` e
      `dispose` em `try/finally` — um caso por categoria (atom/molecule/
      organism) em
      `test/widget/presentation/widgets/common/design_system_accessibility_test.dart`

### Etapa 4 — Documentação e regras

- [x] **C0.19** — Atualizar `architectural_patterns.mdc` com nova
      **seção 8 — Design System & Componentização**:
  - [x] Tabela "qual token usar quando"
  - [x] Regra "composition over inheritance" com exemplos do
        `AppButton` antes/depois
  - [x] Regra "cores semânticas via `context.colors` vs cores de marca
        via `AppPalette`"
  - [x] Regra "doc-comment com nível atomic" para componentes
        em `widgets/common/`
  - [x] Regra "novo widget composition-first" — checklist no PR review
  - [x] Regra "responsividade dentro do desktop" (`AppBreakpoints`)
  - [x] Regra "acessibilidade obrigatória" (`AppTargetSize`,
        `Semantics`, contraste 3:1)
- [x] **C0.20** — Criar **ADR-009** em `docs/adr/`:
  - [x] "Design System: tokens semânticos via ThemeExtension +
        composition over inheritance"
  - [x] Contexto, decisão, alternativas (m3e_design package vs custom),
        consequências
- [x] **C0.21** — Criar `docs/onboarding/design_system.md`:
  - [x] Catálogo visual dos tokens
  - [x] Como criar um widget novo seguindo o design system
  - [x] Exemplos de slot pattern
  - [x] Checklist de acessibilidade para novos componentes

### Etapa 5 — Lint custom (preparatório, não bloqueante)

- [x] **C0.22** — Adicionar **TODO M9** ao roadmap (PR futuro):
      criar `custom_lint` ou script CI que detecta:
  - [x] `SizedBox(height: NN)` literal em widgets do projeto (deve
        usar `AppSpacing.gapXX`)
  - [x] `BorderRadius.circular(NN)` literal (deve usar `AppRadius`)
  - [x] `Duration(milliseconds: NN)` literal em transições (deve
        usar `AppDuration`)
  - [x] Acesso a `AppColors.X` quando equivalente em `context.colors`
        existe
  - [x] `MediaQuery.of(context).size.width > N` literal (deve usar
        `context.isWideWindow` ou similar)
  - [x] Targets clicáveis com `width/height < AppTargetSize.minimum`
  - **Nota**: escopo e tarefas de implementação já estão em **§ M9 —
    Custom lint para guardrails do Design System** (roadmap abaixo);
    C0.22 apenas amarrou o item ao PR-C.

### Critério de aceite consolidado

- [x] `dart analyze` **0 issues** no `analysis_options.yaml` atual (2026-05-16:
      `dart fix --apply .` + `dart format`; regras extra em **§ M2** ainda
      desligadas)
- [x] `flutter test` suíte completa verde (última corrida local **2026-05-16**,
      pós `dart fix`/`dart format` em massa: **+1305**, **~11** skip,
      **0** fail; goldens dos átomos em `test/golden/widgets/common/` +
      `design_system_atoms_golden_test.dart`)
- [x] `architectural_patterns.mdc` seção 8 publicada
- [x] ADR-009 commitada
- [x] `docs/onboarding/design_system.md` publicado
- [x] Cada etapa em commit separado (**2026-05-18**: script
      `tools/plan_commit_groups.ps1 -Execute`; ver `git log` dos commits
      por camada domain / app-infra / presentation / ci / docs / deps)

---

## 9. PR-D — Refator DRY de UI + UX

**Objetivo**: eliminar duplicação na presentation, quebrar god dialog em
3 dialogs especializados, entregar 4 UX wins. **Todos os widgets novos
consomem o design system do PR-C** (tokens, slot pattern,
`ThemeExtension`).

**Esforço**: 2 dias. **Critério**: ~520 linhas eliminadas, zero regressão visual.

### TODO list

- [x] **D1** — Eliminar `String _t(...)` inline em 17 widgets (B7)
  - [x] Substituir todas as definições por `appLocaleString(context, pt, en)` (já existe); `destination_dialog` mantém `_dialogLabel` fino por `mounted`
  - [x] **Teste**: CI (`grep` em `.github/workflows/test.yml`) falha se `String _t(String pt, String en)` ou variante com `BuildContext` reaparecer em `lib/`
- [x] **D2** — `DatabaseTypeMetadata` (C4 + U8 + U9)
  - [x] Criar `lib/core/utils/database_type_metadata.dart`
  - [x] Usar cores oficiais já definidas em `AppPalette` (PR-C0.1)
  - [x] Migrar `schedule_grid.dart`, `schedule_list_item.dart`, `database_config_page.dart` (+ `schedule_dialog` dropdown alinhado ao metadata)
  - [x] **Teste**: `test/unit/core/utils/database_type_metadata_test.dart` — falha se algum `DatabaseType.values` não tiver entry no mapa
- [x] **D3** — `DatabaseConfigDataGrid<T>` genérico — **Organism**
       (C5)
  - [x] Criar `lib/presentation/widgets/common/database_config_data_grid.dart`
  - [x] Doc-comment `/// **Organism**`
  - [x] Usa `AppSpacing` no estado vazio; status com `Expanded` + ellipsis; largura da coluna de ações corrigida em `AppDataGrid`
  - [x] Substituir `SqlServerConfigList`, `SybaseConfigList`, `PostgresConfigGrid`
  - [x] **Teste**: `database_config_data_grid_test.dart` (renderiza com diferentes T)
- [x] **D4** — `DatabaseConfigListItem<T>` genérico — **Molecule**
       (C6 + B8)
  - [x] Criar `lib/presentation/widgets/common/database_config_list_item.dart`
  - [x] Doc-comment `/// **Molecule**`
  - [x] Resolve B8 (Postgres coberto pelo genérico em teste; sem `PostgresConfigListItem` dedicado)
  - [x] **Teste**: `database_config_list_item_test.dart` — cada SGBD + cor via `DatabaseTypeMetadata`
- [x] **D5** — Quebrar `SqlServerConfigDialog` em 3 dialogs especializados (B9, B10, B3)
  - [x] **D5.1** — Criar `DatabaseConfigDialogShell` — **Organism**
        (header + body + actions + atalhos U4); usa `AppSpacing.lg`
        para padding; **teste**: `database_config_dialog_shell_test.dart`
  - [x] **D5.2** — Criar `TestConnectionRunner<TConfig>` (C7) com
        `validate/buildConfig/runTest` callbacks; **resultado como
        sealed class** `TestConnectionOutcome` (Dart 3 pattern
        matching); `TestConnectionSucceeded` com `databases` /
        `listWarning`; `execute(afterValidation: …)`; integrado em
        `SqlServerConfigDialog`, `PostgresConfigDialog`,
        `SybaseConfigDialog`; **teste**: `test_connection_runner_test.dart`
  - [x] **D5.3** — Reescrever `SqlServerConfigDialog` (apenas SQL
        Server) — `DatabaseConfigDialogShell` por composição; sem
        `initialType` / branches multi-SGBD
  - [x] **D5.4** — Criar
        `lib/presentation/widgets/postgres/postgres_config_dialog.dart`
        (composição do shell); **teste**: `postgres_config_dialog_test.dart`
  - [x] **D5.5** — Atualizar `database_config_page._showPostgresConfigDialog`
        (elimina hack B3); **Nova configuração** abre seletor de tipo
        (SQL / Sybase / PostgreSQL) antes do dialog específico
  - [x] **D5.6** — `SybaseConfigDialog` usa `DatabaseConfigDialogShell`
  - [x] **Teste regressão crítico**: `database_config_dialogs_regression_test.dart`
        — `DatabaseConfigDialogShell` + títulos/labels exclusivos por SGBD
        (widget contract; sem golden)
- [x] **D6** — `MessageModal.showConfirm` (C10)
  - [x] Adicionar método se não existir
  - [x] Substituir diálogos inline em `database_config_page`
        (`_confirmDeleteConfiguration` / `_confirmDuplicateConfiguration`)
  - [x] **Teste**: `message_modal_test.dart` cobre `showConfirm`
- [x] **D7** — `PasswordField` com toggle "mostrar senha" (U5) —
       **Molecule**
  - [x] `IconButton` com estado interno `_obscureText` + `Semantics` /
        `Tooltip` (PT/EN via `appLocaleString`)
  - [x] Doc-comment `/// **Molecule**`
  - [x] `AnimatedSwitcher` com `AppDuration.fast` no ícone
  - [x] **Teste**: `password_field_test.dart` (toggle + `enabled: false`)
- [x] **D8** — `_SectionHeader` com badge ativas/inativas (U1) —
       **Molecule**
  - [x] `SectionHeaderWithStatusBadges` + uso nas 3 seções de
        `database_config_page.dart` (contagem `enabled`)
  - [x] Badges usam `context.appSemanticColors.success` / `.danger`
  - [x] **Teste**: `section_header_with_status_badges_test.dart`
- [x] **D9** — Atalhos de teclado em dialogs (U4)
  - [x] `Esc` → `maybePop` ou `onDismiss`; `Ctrl+Enter` → `onSubmitIntent`
        (Enter sozinho evitado — `CallbackShortcuts` no shell)
  - [x] `DatabaseConfigDialogShell` (`CallbackShortcuts` + `Focus` autofocus)
  - [x] **Teste**: `database_config_dialog_shell_test.dart` (Escape + Ctrl+Enter)

---

## 10. PR-E — Hexagonal foundation: ports + base classes genéricas

**Objetivo**: consolidar duplicação SGBD-específica em ports
parametrizados + base classes (Template Method); preparar Firebird (e
SGBDs futuros) para ser uma operação trivial.

**Esforço**: 2,5 dias. **Critério**: ~430 linhas eliminadas, zero
regressão funcional, **3 SGBDs migrados em commits separados** (Sybase
POC primeiro).

### Etapa 1 — Domain (definir ports e abstrações)

- [x] **E1** — `DatabaseConnectionConfig` abstract class
  - [x] Criar `lib/domain/entities/database_connection_config.dart`
  - [x] Campos comuns + getters `databaseType`, `host`, `primaryDatabase`;
        `backupTarget` opcional (default `null`); `portValue` herdado
  - [x] `SqlServerConfig`, `SybaseConfig`, `PostgresConfig` estendem a
        base (`host` unificado; `primaryDatabase` para o `DatabaseName`
        alvo)
  - [x] **Teste**: `database_connection_config_test.dart` (LSP / visão unificada)
- [x] **E2** — `IDatabaseConfigRepository<T>` port genérico
  - [x] Criar `lib/domain/repositories/i_database_config_repository.dart`
  - [x] `ISqlServerConfigRepository` / `ISybaseConfigRepository` /
        `IPostgresConfigRepository` como markers (`implements
        IDatabaseConfigRepository<...>`)
  - [x] **Teste**: `database_config_repository_markers_test.dart`
- [x] **E3** — `IDatabaseBackupPort<T>` port genérico
  - [x] Criar `lib/domain/services/i_database_backup_port.dart`
  - [x] Criar `BackupExecutionContext` DTO encapsulando 12 args
  - [x] Manter `I*BackupService` como marker interfaces
  - [x] **Teste**: `database_backup_port_markers_test.dart`

### Etapa 2 — Infrastructure (base class de repositório)

- [x] **E4** — `BaseDatabaseConfigRepository<T, TData>`
  - [x] Criar `lib/infrastructure/repositories/base_database_config_repository.dart` com Template Method (CRUD comum + hooks `fetch*`/`write*`/`rowToEntity`/`onBeforeDelete`)
  - [x] Usa `RepositoryGuard` + `SecureCredentialHelper` (PR-B)
  - [x] **Teste**: `base_database_config_repository_test.dart` com fake DAO
        (create/getById/delete, getAll, getEnabled, update, `NotFoundFailure`)
- [x] **E5** — Migrar `SybaseConfigRepository` (POC)
  - [x] Reescrever para `extends BaseDatabaseConfigRepository<SybaseConfig, QueryRow>`
  - [x] Preservar `_tableExists` defensivo (hook implícito em `getAll`/`getEnabled`/`getById` + `_selectMany`)
  - [x] **Teste**: testes existentes passam idêntico (sem suite dedicada ao repositório)
- [x] **E6** — Migrar `SqlServerConfigRepository`
  - [x] **Teste**: idem (comportamento preservado; sem suite dedicada)
- [x] **E7** — Migrar `PostgresConfigRepository`
  - [x] Override `onBeforeDelete` com `_dropWalReplicationSlotBestEffort` (via DAO + `rowToEntity`, sem `getById` recursivo)
  - [x] **Teste**: idem

### Etapa 3 — Application (provider base + strategy genérica)

- [x] **E8** — `DatabaseConfigProviderBase<T>`
  - [x] Criar `lib/application/providers/database_config_provider_base.dart`
  - [x] Hook `verifyToolsOrThrow()` (default no-op)
  - [x] Hook abstrato `duplicateConfigCopy(T source) -> T`
  - [x] **Teste**: `database_config_provider_base_test.dart` com fake repo
        (load/create/delete vinculado/duplicata/delete ok/delete falha repo,
        update, create/update com falha no repo, toggleEnabled,
        delete com falha schedules + mensagem genérica se não-Failure,
        getConfigById, active/inactive, erro em getAll, falha em
        `_reloadConfigs` pós-create/update)
- [x] **E9** — Migrar `SybaseConfigProvider`
  - [x] Override `verifyToolsOrThrow` (`_toolVerificationService.verifySybaseTools`)
  - [x] Override `duplicateConfigCopy`
  - [x] **Teste**: testes existentes passam
- [x] **E10** — Migrar `SqlServerConfigProvider`
  - [x] Override `verifyToolsOrThrow` (verifica `sqlcmd`)
  - [x] **Teste**: testes existentes passam
- [x] **E11** — Migrar `PostgresConfigProvider`
  - [x] Sem override (usa default)
  - [x] **Teste**: testes existentes passam

### Etapa 4 — Application (strategy genérica)

- [x] **E12** — `GenericDatabaseBackupStrategy<T>` + `BackupValidationRule<T>` + `BackupResultEnricher<T>`
  - [x] Criar `lib/application/services/strategies/generic_database_backup_strategy.dart`
  - [x] Criar `lib/application/services/strategies/rules/`:
    - `PostgresRejectConvertedTypesRule`
    - `SqlServerRejectConvertedTypesRule`
    - `SybaseRejectDifferentialRule` (extraída de `SybaseBackupStrategy:45-51`)
    - `SybaseLogBackupPreflightRule` (extraída de `SybaseBackupStrategy:54-75`)
    - `SybaseRejectTruncateInReplicationRule` (extraída de `SybaseBackupStrategy:90-101`)
  - [x] Criar `lib/application/services/strategies/enrichers/`:
    - `SybaseChainMetadataEnricher` (extraída de `SybaseBackupStrategy:121-144`)
  - [x] **Teste**: `rules/*_rule_test.dart`, `enrichers/sybase_chain_metadata_enricher_test.dart`,
        `generic_database_backup_strategy_test.dart` (execute: rules, port,
        enrichers, falha do port, exceção no enricher; `databaseType`;
        `getDatabaseSizeBytes` com/sem timeout)
- [x] **E13** — Factories de strategies
  - [x] `SqlServerBackupStrategyFactory.create(service)`
  - [x] `SybaseBackupStrategyFactory.create({service, validatePreflight})` — 3 rules + 1 enricher
  - [x] `PostgresBackupStrategyFactory.create(service)`
  - [x] **Teste**: `backup_strategy_factories_test.dart`
- [x] **E14** — Refatorar `BackupOrchestratorService._buildDefaultStrategies`
  - [x] Usa factories (`*BackupStrategyFactory.create`); fachadas `*BackupStrategy` delegam ao generic
  - [x] **Teste**: suíte `test/unit/application/services/strategies/` + `dart analyze` (sem `backup_orchestrator_service_test` dedicado)

### Etapa 5 — DI (helper `registerSgbd`)

- [x] **E15** — Criar `lib/core/di/sgbd_registration.dart`
  - [x] Extension method `registerSgbd<TConfig, TData>` em `GetIt` +
        `registerBackupDatabaseDefaultSgbds` (repos + ports + providers)
  - [x] **Teste**: `test/unit/core/di/sgbd_registration_test.dart`

### Extensão PR-E — Firebird no runtime (acompanha plano Firebird)

- [x] `IFirebirdBackupService` + `FirebirdBackupService` (`gbak`, `gstat`,
      métricas, limpeza de `.fbk` parcial)
- [x] `FirebirdBackupStrategy` / factory / regra de tipos de backup;
      `BackupOrchestratorService` + DI (`sgbd_registration` /
      `application_module`)
- [x] `ToolVerificationService.verifyFirebirdCliTools` +
      `FirebirdConfigProvider.verifyToolsOrThrow`
- [x] UI: `FirebirdConfigDialog` (teste de conexão); `ProcessService` paths
      Windows para `bin` do Firebird

### Etapa 6 — Documentação

- [x] **E16** — Atualizar `architectural_patterns.mdc`:
  - [x] Nova seção "Padrão Hexagonal/Generic para SGBDs" (§9)
  - [x] Quando usar `BaseDatabaseConfigRepository<T,TData>` vs implementação direta
  - [x] Quando usar `GenericDatabaseBackupStrategy<T>` + `Rule`/`Enricher`
  - [x] Cookbook "Como adicionar um novo SGBD" (resumo §9.4)
- [x] **E17** — Criar **ADR-004** em `docs/adr/`:
  - [x] `004-generic-hexagonal-ports-sgbds.md` — ports genéricos + template SGBD
  - [x] Contexto, decisão, alternativas consideradas, consequências

### Critério de aceite consolidado

- [x] `dart analyze` **0 issues** no `analysis_options.yaml` atual (2026-05-16;
      **§ M2** trata de re-habilitar regras adicionais)
- [x] `flutter test` 100% verde (última corrida local **2026-05-16**: +1305,
      ~11 skip, 0 fail; `ipc_service_test` usa portas efêmeras no Windows)
- [x] Coverage helpers/base classes ≥80% (última medição local no conjunto
      `sgbd_registration` + `base_database_config_repository` +
      `database_config_provider_base` + `generic_database_backup_strategy` +
      `repository_guard` + `async_state_mixin`, rodando apenas os testes
      unitários desse bundle com `--coverage`: **~99% combinado**;
      `sgbd_registration.dart` **100%** após smoke DI com
      `AppDatabase.inMemory()`, resolução dos três `*ConfigProvider` e stub
      genérico de `ProcessService.run` para `verifySybaseToolsDetailed`;
      `database_config_provider_base` **~98.5%**; `repository_guard` **~94%**)
- [x] Cada etapa em commit separado (mesmo script `tools/plan_commit_groups.ps1`)
- [x] PR description com benchmark de linhas eliminadas SGBD por SGBD
      (**2026-05-18**: secao no `.github/pull_request_template.md` +
      `dart run tools/sgbd_loc_report.dart [--markdown]`; rascunho LOC abaixo
      permanece como referencia historica)

#### Rascunho — benchmark LOC (HEAD atual)

Contagem **snapshot** em `lib/**/*.dart`, **excluindo** `*.g.dart`, por
substring no caminho (útil na descrição do PR). Valores gerados em
2026-05-15 (ambiente local).

| Área | Arquivos | Linhas (~) |
|------|----------|------------|
| SQL Server (`…sql_server…`) | 19 | 2376 |
| PostgreSQL (`…postgres…`) | 15 | 2774 |
| Sybase (`…sybase…`) | 29 | 4034 |
| Núcleo PR-E (5 arquivos: `database_connection_config.dart`, `sgbd_registration.dart`, `base_database_config_repository.dart`, `database_config_provider_base.dart`, `generic_database_backup_strategy.dart`) | 5 | 491 |

**Linhas eliminadas** (critério original): exige baseline Git. Após
definir a branch base (ex.: `main` antes do merge do PR-E):

```bash
git fetch origin
git diff --stat origin/main...HEAD -- \
  lib/domain lib/application lib/infrastructure lib/presentation
```

Opcional: filtrar por SGBD com caminhos, por exemplo
`lib/**/*sql_server*`, `lib/**/*postgres*`, `lib/**/*sybase*`.

---

## 11. Roadmap de melhorias futuras (não-bloqueantes)

Itens identificados na pesquisa de 2026 que **não bloqueiam** Firebird
mas valem trackear como dívida técnica positiva.

### M1 — Adoção de `freezed` para entities

**Esforço**: 1,5 dia. **ROI**: ~175 linhas eliminadas + sealed
classes nativas + JSON serialization automática.

**Pré-requisito**: PR-E mergeado (`DatabaseConnectionConfig` precisa
estar estável).

**Plano**:
- [x] Adicionar `freezed`, `freezed_annotation` ao `pubspec.yaml`
      (**2026-05-16**). `json_serializable` fica para a etapa em que
      entities/DTOs ganharem JSON automático.
- [x] Migrar entities: `SqlServerConfig`, `SybaseConfig`,
      `PostgresConfig`, `FirebirdConfig` (**2026-05-18** — `@freezed` +
      `implements DatabaseConnectionConfig`; `DatabaseConnectionConfig` virou
      `abstract interface class`; overrides explícitos de `backupTarget` /
      `portValue`; codegen `*.freezed.dart`; testes:
      `sql_server_config_test.dart`, `postgres_config_test.dart`,
      `sybase_config_test.dart`, `firebird_config_test.dart`,
      `database_connection_config_test.dart`).
      ~~`BackupExecutionContext`~~ (**piloto freezed 2026-05-16** —
      `lib/domain/services/backup_execution_context.dart`).
      ~~`Schedule`~~ — ver bullet abaixo.
- [x] Criar **ADR-006**: "Adoção de freezed para entities/DTOs"
      (`docs/adr/006-freezed-for-entities-and-dtos.md`)
- [x] Migrar `BackupLog` para freezed (igualdade por `id` preservada;
      `test/unit/domain/entities/backup_log_test.dart`)
- [x] Migrar `BackupHistory` para freezed (igualdade por `id` preservada;
      `test/unit/domain/entities/backup_history_test.dart`)
- [x] **Teste**: re-rodar suíte unitária após migrações freezed
      (`BackupLog`, `BackupHistory`; CI `flutter test test/unit/`)
- [x] Migrar `Schedule` para freezed (composição:
      `sqlServerBackupOptions` / `sybaseBackupOptions`; removidas
      `SqlServerBackupSchedule` / `SybaseBackupSchedule`;
      `test/unit/domain/entities/schedule_test.dart`)

### M2 — Lint cleanup (re-habilitar regras desligadas)

**Esforço**: 0,5-1 dia. **ROI**: detecção precoce de bugs futuros.

- **Incremento (2026-05-15)**: `unawaited(...)` / awaits onde coube —
      **(1)** ctors/filtros dos providers (`DatabaseConfigProviderBase`,
      `DestinationProvider`, `LicenseProvider`, `LogProvider`,
      `NotificationProvider`, `ServerCredentialProvider`,
      `ServerConnectionProvider`), `SchedulerService`, e
      `LoggerService._enqueueFileLog`; **(2)** shutdown/IPc/socket:
      `ServiceShutdownHandler` (sinais → `_handleShutdown`),
      `IpcService` (`socket.close` no `onDone`),
      `ConnectionManager._handleFileTransferMessage`,
      `TcpSocketClient` (heartbeat send, disconnect/reconnect timers,
      `await` em `close`/`cancel` onde async, `logReceived`/`logSent`),
      `ClientHandler` (auth `.then`, `disconnect`),
      `TcpSocketServer._enqueueHandlerFuture` para todos os
      `*.handle(...)`. **Continuação (2026-05-15)**: `main.dart`,
      presentation (tray/window/modais/páginas), `general_settings_tab`
      (callbacks `Future<void>`), testes (`push` com `unawaited`,
      `getIt.unregister` com `setUp`/`tearDown` **async** +
      `registerTestFeatureAvailability`/`unregisterTestFeatureAvailability`
      como `Future<void>`). Ajustes: `Navigator.pop` síncrono (Fluent) **sem**
      `unawaited`; `trayManager.destroy()` permanece com `unawaited` (retorna
      `Future`).
- **Medição inicial (2026-05-16)**: `discarded_futures: true` → **~160**
      `info` (padrão intencional: `loadConfigs()` no ctor dos providers,
      logging assíncrono, UI que dispara `Navigator`/modais sem `await`).
      **Após incrementos 2026-05-15**: **~108** `info` restantes; **após
      continuação 2026-05-15** (com `discarded_futures: true` no
      `analysis_options.yaml`): **`flutter analyze` → 0 issues**.
- **Nota (2026-05-16)**: `dart fix --apply .` limpou estilo (`omit_local`,
      `use_super_parameters`, imports, etc.); `database_config_list_item_test`
      precisou de `as Icon` após remover tipo explícito (evitar regressão
      `undefined_getter`).
- **Fecho M2 (2026-05-15)**: `avoid_dynamic_calls: true` e
      `unawaited_futures: true` re-habilitados no `analysis_options.yaml`.
      Ajustes principais: `unawaited(MessageModal.*)` / `await` em
      `ZipFileEncoder` / `StreamController.close` / `StreamSubscription.cancel`
      em fluxos async; `NotificationProvider`/`RealDatabaseConnectionProber`
      com tipagem estática em vez de `dynamic` (Google Drive `FileList`
      genérico em `_executeWithTokenRefresh<T>`); `NotificationService` sem
      `fold` async não aguardado; `ConnectionManager` com
      `// ignore: cancel_subscriptions` nas duas subscriptions (canceladas em
      [disconnect], não em `dispose` de widget).
- [x] Re-habilitar `avoid_dynamic_calls: true` e `unawaited_futures: true` em
      `analysis_options.yaml` (~~`discarded_futures`~~ já ativo; manter **0 issues**)
- [x] Tratar warnings que aparecerem (**estado 2026-05-15**: `flutter analyze` → **0 issues** com as três regras ligadas)
- [x] **Teste**: `flutter analyze` com **0 issues** após re-habilitar as
      regras acima
- [x] Documentar em PR description as exceções justificadas
      (**material**: `cancel_subscriptions` em `ConnectionManager` — ver bullet
      “Fecho M2” acima)

### M3 — Sealed classes para state machines

**Esforço**: variável (1-3 dias dependendo do escopo).

**Candidatos**:
- `BackupStatus` — atualmente enum simples; sealed class permitiria
  carregar dados específicos por estado (ex.: `BackupRunning(progress)`,
  `BackupError(failure, retryable)`)
- `ConnectionState` no socket
- `TransferState` em `RemoteFileTransferProvider`

**Recomendação**: aplicar **caso a caso quando refatorar a área**, não
em PR único.

### M4 — ADR adicionais

- [x] **ADR-005**: "Decisão sobre folder structure (manter layer-first)"
      — para evitar discussão recorrente (`docs/adr/005-layer-first-code-organization.md`)
- [x] **ADR-006**: M1 (freezed)
- [x] **ADR-007**: remoção de `PortNumber.isDefault` (sem uso em `lib/`;
      defaults por SGBD nas configs — `docs/adr/007-port-number-is-default-removal.md`)

### M5 — Documentação para onboarding

- [x] Criar `docs/onboarding/adicionar_sgbd.md` com cookbook do PR-D
      (extração da secao **9** de `architectural_patterns.mdc`; o plano
      citava "secao 14" por deslize — o cookbook oficial e a §9)
- [x] Criar `docs/onboarding/architecture_overview.md` com diagrama
      mermaid das camadas
- [x] Atualizar `README.md` com link para os ADRs e onboarding
      (Arquitetura → `docs/adr/README.md`; pasta `docs/onboarding/` com
      `adicionar_sgbd`, `architecture_overview`, `design_system`)

### M6 — Estatística de cobertura no CI

Atualmente cobertura é gerada localmente via `coverage` package.
Subir relatório em PR (Codecov ou similar) ajuda a identificar
regressões rapidamente.

**Esforço**: 0,5 dia.

**Plano**:
- [x] `flutter test test/unit/ --coverage` no workflow `Test`
      (`.github/workflows/test.yml`)
- [x] Filtrar `coverage/lcov.info` com `python scripts/coverage.py --filter-only`
      (ignora `.g.dart`, `.freezed.dart`, `test/`)
- [x] Publicar artefacto `coverage/lcov.filtered.info` no GitHub Actions
- [x] Integração Codecov / badge no README (**2026-05-18**:
      `codecov/codecov-action@v5` no workflow `Test` com
      `coverage/lcov.filtered.info`; badge no README; requer secret
      `CODECOV_TOKEN` no GitHub para upload ativo)

### M7 — Migração futura para feature-first (avaliar quando)

Não migrar agora. Reavaliar quando:
- Houver 3+ features ortogonais (ex.: backup + dashboard analytics +
  audit module)
- Time crescer para >5 desenvolvedores trabalhando em paralelo
- Surgir necessidade de extrair módulos para packages separados

- [x] Decisao registrada em **ADR-005** (manter layer-first; gatilhos de
      reavaliacao no proprio ADR). **ADR-008** reservado se/quando a migracao
      feature-first for retomada formalmente.

### M8 — Atomic Design folder hierarchy

**Esforço**: 1 dia. **ROI**: navegação mais clara entre níveis de
componente; alinhamento com convenção de mercado 2026 ([Rodrigo
Nepomuceno 2026](https://rodrigonepomuceno.medium.com/atomic-design-in-flutter-modular-ui-architecture-with-design-systems-72f813c18af4)).

**Pré-requisito**: PR-C mergeado (componentes já documentam nível
atomic em doc-comments).

**Plano**:
- [x] Mover `widgets/common/` para hierarquia explícita (`atoms/`,
      `molecules/`, `organisms/`); `common/common.dart` reexporta os barrels
- [x] Atualizar imports diretos para novos caminhos (`lib/`, `test/`,
      `widgetbook/`)
- [x] Manter pastas por feature (`widgets/sql_server/`, `widgets/postgres/`,
      etc.) — moléculas/organismos específicos de feature ficam lá
- [x] **Teste**: widget/golden tests do design system verdes
- [x] Documentar como **ADR-010**

### M9 — Custom lint para guardrails do Design System

**Origem**: checklist **C0.22** do PR-C (Etapa 5 do plano de refatoração).

**Esforço**: 1 dia. **ROI**: previne degradação do design system.

**Pré-requisito**: PR-C mergeado (tokens estabilizados).

**Plano** (referenciado como C0.22 no PR-C):
- [x] Script CI `tools/design_system_guard.dart` (alternativa a `custom_lint`
      neste ciclo; escopo: `atoms/`, `molecules/`, `organisms/`)
- [x] Regras no guard:
  - `prefer_app_spacing`, `prefer_app_radius`, `prefer_app_duration`
  - `prefer_app_palette` (`AppColors` legado)
  - `atomic_doc_comment` (`**Atom|Molecule|Organism**`)
  - `prefer_app_breakpoints`
- [x] `custom_lint` package + regras IDE (**2026-05-18**: **não adotado** neste
      ciclo — `tools/design_system_guard.dart` + `--enforce-target-size` cobrem CI;
      reavaliar `analysis_server_plugin` quando for conveniente duplicar regras no
      analyzer; evita manter `custom_lint_builder` em paralelo ao guard)
- [x] `enforce_target_size` — alvos com `onPressed`/`onTap` e
      `minHeight`/`minWidth`/`minimumSize` literais &lt; 44px em
      atoms/molecules/organisms (`--enforce-target-size` no CI)
- [x] **Teste**: `dart run tools/design_system_guard.dart --fail-on-findings`
      no workflow `Test`; design system sem violações

### M10 — Widgetbook (component catalog)

**Esforço**: 2 dias. **ROI**: catálogo visual interativo de todos
os componentes; designers/PMs podem revisar UI sem rodar o app;
golden tests automáticos por variante.

**Pré-requisito**: PR-C mergeado (componentes estáveis e tokenizados).

**Plano**:
- [x] Adicionar `widgetbook` + `widgetbook_annotation` (deps) e
      `widgetbook_generator` + `build_runner` (`dev_dependencies`) no
      pacote `widgetbook_workspace` em `widgetbook/pubspec.yaml`
      (catálogo como app irmão; não poluir `backup_database/pubspec.yaml`)
- [x] Criar `widgetbook/` separate Flutter app (entry point
      `widgetbook/lib/main.dart`, pacote `widgetbook_workspace`)
- [x] Criar **stories** para átomos/moléculas/organismos prioritários do
      design system (expandir outros em `widgets/common/` sob demanda):
  - [x] `AppButton` — variantes default, primary, icon, loading,
        disabled (sem danger/secondary dedicados: não existem fábricas
        no widget atual)
  - [x] `AppTextField` — default, autofocus (“Focused”), erro
        (validator), disabled, prefix/suffix, use-case **Knobs**
        (label/hint/enabled)
  - [x] `PasswordField` — default, com valor, erro de validação,
        disabled
  - [x] `MessageModal` — success, info, warning, erro, rótulo de
        botão customizado (surface `ContentDialog` sem `showDialog`)
  - [x] `DatabaseConfigDataGrid` — linhas + ações, coluna de último
        teste, vazio, vazio com “adicionar”
  - [x] `EmptyState` — mensagem só; com ação
- [x] Adicionar **knobs** (ex.: use-case `AppTextField` / **Knobs**)
      — expandir para mais widgets conforme necessário
- [x] Add-ons de **densidade** (`ThemeAddon<AppDensity>` +
      `InheritedAppDensity`: compact / comfortable / spacious)
- [x] Add-on de **tema** Light/Dark (`ThemeAddon<FluentThemeData>` em
      `widgetbook/lib/main.dart`)
- [x] Configurar **golden tests** por use case via
      **`widgetbook_golden_test`** (o pacote `widgetbook_test` no pub.dev
      é placeholder sem API); ficheiro
      `widgetbook/test/widgetbook_use_cases_golden_test.dart`, PNGs em
      `widgetbook/test/goldens/widgetbook/`; ver **ADR-011**
- [x] Documentar como **ADR-011**
- [x] Avaliar **Widgetbook Cloud** para integração com Figma e
      revisão visual de PRs (**2026-05-18**: **adiado** — catálogo local
      `widgetbook/` + goldens (`ADR-011`) cobrem revisao de componentes;
      Cloud e pago e nao bloqueia entregas; reavaliar se o time adotar Figma
      como fonte unica de verdade)

### M11 — Skeleton loaders (substituir spinners)

**Esforço**: 1 dia. **ROI**: UX melhor — usuários percebem o app
mais rápido (validado em [Aman Sharma 2026 (Medium)](https://medium.com/@aks.sharma312/ditch-the-spinner-implementing-skeleton-loading-for-better-ux-in-flutter-2a5402ba99d5)).

**Pré-requisito**: PR-C mergeado (tokens de cor disponíveis).

**Plano**:
- [x] Adicionar `shimmer` package (v3.0.0+) ao `dependencies`
- [x] Criar átomo `AppShimmer` em `widgets/common/` que aplica
      cores do tema (`baseColor` + `highlightColor` de
      `AppSemanticColors`)
- [x] Criar moléculas `SkeletonCard`, `SkeletonListItem`,
      `SkeletonGrid` para layouts comuns
- [x] Substituir `ProgressRing` em telas list-heavy:
  - `database_config_page` (carga inicial dos 4 SGBDs)
  - `schedules_page` (carga de schedules)
  - `dashboard_page` (carga de métricas)
  - `logs_page` (carga de logs)
- [x] **Manter** `ProgressRing` em ações inline curtas
      (botão "Salvar", "Testar conexão") — skeleton só faz sentido
      em load de tela cheia
- [x] Flag de feature em `IUserPreferencesRepository` para
      desabilitar (acessibilidade — usuários sensíveis a animação)
- [x] **Teste**: widget tests confirmam que `enabled: false`
      desabilita animação para testes determinísticos

### M12 — Auditoria de acessibilidade (a11y) completa

**Esforço**: 1,5 dia. **ROI**: conformidade WCAG 2.1 AA; preparação
para distribuição corporativa onde a11y é requisito legal (ADA,
Section 508, EN 301 549).

**Pré-requisito**: PR-C + PR-D mergeados (componentes finalizados).

**Plano**:
- [x] `meetsGuideline(textContrastGuideline)` em páginas principais
      (`database_config_page`, `schedules_page`, `dashboard_page`,
      `logs_page`) — light e dark; ver
      `test/widget/presentation/pages/main_pages_accessibility_test.dart`
      e teste em `database_config_page_empty_sections_test.dart`
- [x] `meetsGuideline(androidTapTargetGuideline)` /
      `meetsGuideline(iOSTapTargetGuideline)` na **shell** principal
      (`MainLayout`: itens do painel lateral + ícones da barra superior);
      ver `test/widget/presentation/pages/main_layout_accessibility_test.dart`.
      Botões/ícones densos **dentro** de cada página (ex.: grids, diálogos)
      seguem em auditoria incremental
- [x] Adicionar `Semantics` / `ExcludeSemantics` em widgets customizados
      reutilizaveis em `widgets/common/`: `AppButton` (leading com texto),
      `ActionButton` (icone + `Semantics` no botao; loading com rotulo),
      `CancelButton`, `EmptyState` (icone grande decorativo),
      `PasswordField` (prefixo cadeado), `MessageModal` (icone do titulo),
      `MainLayout` (navegacao — sessao anterior); telas e dialogos
      especificos: continuar ao tocar no ficheiro
- [x] Validar suporte a escala de texto do sistema
      (`MediaQuery.textScaler`) — testar com 1.5× e 2.0× em
      `schedules_page`, `dashboard_page`, `logs_page` e estado vazio de
      `database_config_page`; ver
      `test/widget/presentation/pages/main_pages_accessibility_test.dart` e
      `test/widget/presentation/pages/database_config_page_empty_sections_test.dart`
- [x] Validar navegação por teclado (`Tab`/`Shift+Tab`/`Enter`/`Esc`) —
      **cobertura inicial**: `MessageModal.show` / `MessageModal.showConfirm`
      (Esc), ciclo `Tab` / `Shift+Tab` na shell `MainLayout`; dialogos de
      config: `test/widget/presentation/widgets/common/database_config_dialog_shell_test.dart`
      (Esc, Ctrl+Enter). Ver tambem
      `test/widget/presentation/a11y/critical_keyboard_navigation_test.dart` e
      `test/widget/presentation/pages/main_layout_accessibility_test.dart`;
      demais fluxos criticos: auditoria incremental
- [x] Documentar como **ADR-012** "Conformidade WCAG 2.1 AA" —
      `docs/adr/012-wcag-2-1-aa-accessibility-baseline.md`
- [x] Adicionar checklist de a11y ao template de PR —
      `.github/pull_request_template.md`

### M13 — Design tokens em formato W3C JSON (interop com Figma)

**Esforço**: 1 dia. **ROI**: design tokens podem ser editados por
designers no Figma e exportados para o código (round-trip);
validado em [Figma 2026 release](https://figma.obra.studio/design-tokens-community-group-w3c-release/).

**Pré-requisito**: PR-C mergeado.

**Plano**:
- [x] Criar `design-tokens/` na raiz do repo com JSON files
      seguindo a [W3C Design Tokens Spec](https://design-tokens.github.io/community-group/format/):
  - `colors.tokens.json` (palette + semânticas)
  - `spacing.tokens.json`
  - `radius.tokens.json`
  - `motion.tokens.json`
- [x] Criar script `tools/generate_tokens.dart` que lê o JSON
      e gera snapshot Dart (`lib/core/theme/tokens/generated/w3c_token_snapshot.g.dart`);
      uso: `dart run tools/generate_tokens.dart` ou `--check` em CI
- [x] Documentar fluxo: `design-tokens/README.md` (Figma/export → JSON →
      `dart run tools/generate_tokens.dart` → PR)
- [x] Avaliar se vale o esforço dado o tamanho do projeto;
      **decisao**: manter `AppSpacing` / `AppPalette` como API de runtime;
      JSON + snapshot como fonte verificavel; geracao total de Dart fica
      opcional para evolucao futura

### M14 — Integração nativa Windows (Mica/Acrylic effects)

**Esforço**: 1 dia. **ROI**: app "parece nativo Windows" com
efeitos visuais modernos do Windows 11 (Mica, Acrylic
backdrop). Validado em [arhaminfo 2026](https://www.arhaminfo.com/2025/11/flutter-windows-application.html).

**Pré-requisito**: PR-C mergeado (tokens de cor estáveis).

**Plano**:
- [x] Adicionar `flutter_acrylic` package
- [x] Adicionar `system_theme` package (accent do Windows → `FluentThemeData.accentColor` quando a opção está ativa)
- [x] Habilitar Mica backdrop na janela principal (`flutter_acrylic`; Win 10/11)
- [x] Adicionar setting "Cor de destaque do sistema" / accent Fluent
      (default: `false`; quando `true`, `accentColor` do tema segue o Windows)
- [ ] **Teste**: smoke manual em Windows 10 (sem Mica) e Windows 11
      (com Mica) — runbook: `docs/notes/smoke_windows_mica_m14.md`; gate CI:
      `windows_native_chrome_bootstrap_test.dart` (no-op fora do Windows)
- [x] Documentar como **ADR-013**

---

## 12. Riscos e mitigações consolidados

| Risco | PR | Mitigação |
|---|---|---|
| Generics em Dart com runtime type erasure | E | `instanceName` em DI; tests por tipo concreto |
| Drift DAOs concretos (sem base universal) | E | Hooks abstratos `daoX` na base; subclasses fazem ponte |
| Marker interfaces podem confundir | E | Doc-comment explícito + `architectural_patterns.mdc` cobre |
| Migração de 3 SGBDs em PR única | E | Sub-commits (Sybase POC → SqlServer → Postgres); `git revert` parcial |
| Equipe não familiar com generics | E | Doc dedicada + cookbook + revisão pareada |
| D5 (split god dialog) afeta 3 SGBDs simultaneamente | D | Snapshot de testes widget ANTES; cada SGBD em commit separado |
| Refator de tokens no PR-C pode quebrar visualmente componentes existentes | C | Golden tests dos 5 átomos refatorados (etapa 3) ANTES; rodar IDÊNTICO depois |
| `AppColors` deprecado mas ainda usado em centenas de pontos | C | Migração incremental — `@Deprecated` annotation + warnings; PRs futuros migram conforme tocam |
| `ThemeExtension.lerp` mal implementado quebra animações de tema | C | Cobertura via `app_semantic_colors_test.dart` testando `lerp(t=0.5)` para todos os campos |
| Composition over inheritance pode parecer over-engineering em widgets simples | C | Permitir inheritance para "is-a" forte (documentado); slot pattern só obrigatório em widgets reusáveis (`widgets/common/`) |
| `freezed` adiciona codegen step (latência local) | M1 | Aceitável — já temos `build_runner` para Drift |
| Re-habilitar lints pode gerar avalanche de warnings | M2 | Tratar incrementalmente; `// ignore:` por linha quando justificado |
| M8 (atomic folder migration) gera centenas de import changes | M8 | `dart fix --apply` automatiza; rodar suíte completa para validar |

---

## 13. Como adicionar SGBDs após PR-E (cookbook)

Depois dos 5 PRs, adicionar SGBD novo (ex.: MySQL) seguirá template
mínimo:

1. **Domain** (~20 minutos):
   - `MySqlConfig extends DatabaseConnectionConfig`
   - `IMySqlConfigRepository extends IDatabaseConfigRepository<MySqlConfig>`
   - `IMySqlBackupService extends IDatabaseBackupPort<MySqlConfig>`
   - Adicionar `DatabaseType.mysql` em `schedule.dart`
   - Atualizar `DatabaseTypeMetadata._byType` (1 entrada — usa
     `AppPalette.databaseMysql` que adiciona ao palette)

2. **Infrastructure** (~3 horas):
   - Tabela Drift + DAO + bump `schemaVersion` + migration
   - `MySqlConfigRepository extends BaseDatabaseConfigRepository<...>` (~50 linhas)
   - `MySqlBackupService implements IDatabaseBackupPort<MySqlConfig>`
     (a única parte SGBD-específica — wrap do `mysqldump`)

3. **Application** (~30 minutos):
   - `MySqlConfigProvider extends DatabaseConfigProviderBase<MySqlConfig>` (~30 linhas)
   - `MySqlBackupStrategyFactory.create(port)`

4. **DI** (~5 minutos):
   - Em `infrastructure_module.dart`, após dependências compartilhadas:
     `getIt.registerSgbd<MySqlConfig, MySqlConfigsTableData,
     IMySqlConfigRepository, IMySqlBackupService, MySqlConfigProvider>(...)`
     (mesmo padrão das três entradas em `registerBackupDatabaseDefaultSgbds`;
     opcional extrair `registerMySql...` se o bloco crescer)

5. **UI** (~3 horas):
   - `MySqlConfigDialog` usando `DatabaseConfigDialogShell` (~200
     linhas; já segue tokens do design system + slot pattern)
   - `_MySqlConfigSection` em `database_config_page` (~50 linhas)
   - Adicionar entry ao `_AdvancedSection` factory do `schedule_dialog`

6. **Remoto** (~30 minutos):
   - Atualizar `supportsMysql` em capabilities; golden tests

**Total**: ~7-8 horas vs ~5 dias antes dos PRs A-E. UI segue
identidade visual automaticamente graças aos tokens.

---

## 14. Cross-references

- Plano de Firebird: [`plano_suporte_firebird_2026-04-19.md`](./plano_suporte_firebird_2026-04-19.md)
- Plano de execução remota cliente↔servidor: [`plano_cliente_recursos_servidor_execucao_remota_2026-02-21.md`](./plano_cliente_recursos_servidor_execucao_remota_2026-02-21.md)
- Auditoria de qualidade prévia: [`auditoria_qualidade_2026-04-18.md`](./auditoria_qualidade_2026-04-18.md)
- Rule de padrões arquiteturais: [`.cursor/rules/architectural_patterns.mdc`](../../.cursor/rules/architectural_patterns.mdc)
- Rule de Clean Architecture: [`.cursor/rules/clean_architecture.mdc`](../../.cursor/rules/clean_architecture.mdc)
