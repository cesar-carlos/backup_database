# Plano: Refatoração e Melhorias de Código

Data base: 2026-04-19
Status: Proposto (aguardando primeiro PR)
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
| `discarded_futures: false` | Alto — mesmo problema do `unawaited_futures` | Reabilitar |
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
recorrente.

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

- [ ] **A1** — Eliminar `enum DatabaseType` duplicado (B1)
  - [ ] Remover linha 16 de `sql_server_config_dialog.dart`
  - [ ] Importar `package:backup_database/domain/entities/schedule.dart`
  - [ ] Verificar via `rg "enum DatabaseType"` que não há outras cópias
  - [ ] **Teste regressão**: criar lint custom (ou doc-test) que falha se outro `enum DatabaseType` aparecer
- [ ] **A2** — Remover heurística de detecção de tipo (B2)
  - [ ] Eliminar bloco `sql_server_config_dialog.dart:81-92`
  - [ ] Confiar em `widget.initialType` passado pelo caller
  - [ ] **Teste**: widget test garante que `initialType=Postgres` permanece após `initState`
- [ ] **A3** — Substituir mensagem hardcoded de psql por `ToolPathHelp` (B4)
  - [ ] Substituir bloco `sql_server_config_dialog.dart:943-963`
  - [ ] **Teste**: `tool_path_help_test.dart` cobre o caso
- [ ] **A4** — `int.tryParse` defensivo (B6)
  - [ ] `sql_server_config_dialog.dart:1116`: `int.parse` → `int.tryParse(...) ?? <default>`
  - [ ] Auditar grep `int.parse(_portController` em todos dialogs
  - [ ] **Teste**: widget test simula save com porta vazia e verifica que não crasha
- [ ] **A5** — `PortNumber.isDefault` atualizado ou deprecado (B5)
  - [ ] Adicionar 2638 (Sybase) e 3050 (Firebird) ao set
  - [ ] OU `@deprecated` se confirmar que ninguém usa (preferível)
  - [ ] **Teste**: `port_number_test.dart` cobre portas conhecidas

### Notas

- B3, B9, B10 (god dialog) **NÃO** são corrigidos aqui — fazem parte
  do PR-C porque exigem refatoração estrutural
- Cada item em commit separado para facilitar `git bisect`

---

## 7. PR-B — Refator DRY de domínio/infra

**Objetivo**: extrair 6 padrões duplicados em camadas de domínio e
infraestrutura.

**Esforço**: 1,5 dia. **Critério**: ~220 linhas eliminadas, zero regressão.

### TODO list

- [ ] **B1** — `SecureCredentialHelper` (C1)
  - [ ] Criar `lib/infrastructure/repositories/secure_credential_helper.dart` com `storePasswordOrThrow/readPasswordOrEmpty/deletePassword`
  - [ ] Migrar `SqlServerConfigRepository`, `SybaseConfigRepository`, `PostgresConfigRepository`
  - [ ] **Teste**: `test/unit/infrastructure/repositories/secure_credential_helper_test.dart` (cobertura ≥80%)
- [ ] **B2** — `SecureCredentialKeys` (C9)
  - [ ] Criar `lib/core/constants/secure_credential_keys.dart`
  - [ ] Substituir prefixos locais nos 3 repos
  - [ ] **Teste**: trivial
- [ ] **B3** — `BackupSizeCalculator` (C2)
  - [ ] Criar `lib/core/utils/backup_size_calculator.dart` com `ofFile/ofDirectory/ofFiles`
  - [ ] Migrar Postgres, SQL Server, Sybase
  - [ ] **Teste**: `test/unit/core/utils/backup_size_calculator_test.dart` (≥80%)
- [ ] **B4** — `BackupArtifactUtils` (C3)
  - [ ] Criar `lib/core/utils/backup_artifact_utils.dart` com `safeDeletePartial/waitForStableFile`
  - [ ] Mover métodos do SQL Server service e aplicar nos demais
  - [ ] **Teste**: `test/unit/core/utils/backup_artifact_utils_test.dart` (≥80%)
- [ ] **B5** — `getDatabaseSizeBytes` na strategy interface (B11)
  - [ ] Estender `IDatabaseBackupStrategy` com `getDatabaseSizeBytes({required Object databaseConfig, Duration? timeout})`
  - [ ] Implementar nas 3 strategies existentes (cast interno)
  - [ ] Refatorar `BackupOrchestratorService._estimateRequiredSpaceBytes` para chamar `strategy.getDatabaseSizeBytes(...)`
  - [ ] Eliminar `switch (databaseType)` na linha 648
  - [ ] **Teste**: confirma 3 SGBDs sem switch
- [ ] **B6** — `ToolPathHelp` família Firebird (preparatório)
  - [ ] Adicionar `_firebirdTools = {'gbak', 'nbackup', 'gstat', 'isql', 'isql-fb'}`
  - [ ] Adicionar case `_ToolFamily.firebird` em `_classify` e `buildMessage`
  - [ ] **Teste**: `tool_path_help_test.dart` cobre todas as famílias
- [ ] **Documentação**: atualizar `architectural_patterns.mdc` com nova seção "Helpers de Backup"

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

- [ ] **C0.1** — Criar `lib/core/theme/tokens/app_palette.dart`
  - [ ] Migrar do atual `AppColors`: cores **imutáveis** entre temas
        (cores de marca, SGBD, status absolutos):
        `databaseSqlServer/Sybase/Postgresql/Firebird`,
        `destinationLocal/Ftp/GoogleDrive/Dropbox/Nextcloud`,
        `scheduleDaily/Weekly/Monthly/Interval`, `googleDriveSignedIn`
  - [ ] Atualizar para cores oficiais (U9):
    - `databaseSqlServer = Color(0xFFCC2927)` (Microsoft red)
    - `databaseSybase = Color(0xFF009688)` (Sybase teal — manter)
    - `databasePostgresql = Color(0xFF336791)` (Postgres blue — manter)
    - `databaseFirebird = Color(0xFFF40F02)` (Firebird red — preparatório)
  - [ ] Construtor privado `AppPalette._()` com cores `static const`
  - [ ] **Teste**: `app_palette_test.dart` valida que cores são `const`

- [ ] **C0.2** — Criar `lib/core/theme/extensions/app_semantic_colors.dart`
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
  - [ ] **Teste**: `app_semantic_colors_test.dart` valida `lerp` e
        fallback do `extension` getter

- [ ] **C0.3** — Atualizar `app_theme.dart` para registrar a extensão:
  ```dart
  static FluentThemeData get lightFluentTheme => theme.copyWith(
    extensions: <ThemeExtension>[AppSemanticColors.light],
    // ... resto
  );
  ```
  Idem para dark
  - [ ] **Teste**: widget test confirma que `Theme.of(context).extension<AppSemanticColors>()` retorna instância correta em ambos modos

- [ ] **C0.4** — Manter `AppColors` legado como wrapper deprecado:
  ```dart
  @Deprecated('Use AppPalette para cores fixas ou context.colors para semânticas')
  class AppColors { ... }
  ```
  - [ ] Migração incremental: PRs futuros (D, E, F do firebird) já
        consomem `AppPalette`/`context.colors`; código legado fica
        marcado como TODO

### Etapa 2 — Tokens primitivos (spacing/radius/elevation/motion)

- [ ] **C0.5** — Criar `lib/core/theme/tokens/app_spacing.dart`
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

- [ ] **C0.6** — Criar `lib/core/theme/tokens/app_radius.dart`
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

- [ ] **C0.7** — Criar `lib/core/theme/tokens/app_elevation.dart`
  ```dart
  class AppElevation {
    AppElevation._();
    static const double none = 0;
    static const double low = 2;
    static const double medium = 4;
    static const double high = 8;
  }
  ```

- [ ] **C0.8** — Criar `lib/core/theme/tokens/app_duration.dart` +
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

- [ ] **C0.9** — Criar `lib/core/theme/tokens/app_breakpoints.dart`
  ```dart
  class AppBreakpoints {
    AppBreakpoints._();
    static const double compact = 720;
    static const double medium = 1024;
    static const double wide = 1440;
    // > wide = ultrawide
  }

  extension AppBreakpointsX on BuildContext {
    bool get isCompactWindow => MediaQuery.of(this).size.width < AppBreakpoints.compact;
    bool get isMediumWindow => MediaQuery.of(this).size.width < AppBreakpoints.medium;
    bool get isWideWindow => MediaQuery.of(this).size.width >= AppBreakpoints.medium;
  }
  ```
  - **Justificativa**: mesmo o app sendo desktop-only Windows,
    janelas redimensionáveis exigem layout responsivo (data grids,
    sidebars colapsáveis). Validado em [Saad Ali 2026 (Medium)](https://medium.com/@saadalidev/building-beautiful-responsive-ui-in-flutter-a-complete-guide-for-2026-ea43f6c49b85)
    como prática 2026.

- [ ] **C0.10** — Criar `lib/core/theme/tokens/app_density.dart`
  ```dart
  enum AppDensity { compact, comfortable, spacious }

  class AppDensityValues {
    const AppDensityValues._({required this.spacingMultiplier, required this.targetSize});
    final double spacingMultiplier;
    final double targetSize;

    static const compact = AppDensityValues._(spacingMultiplier: 0.75, targetSize: 36);
    static const comfortable = AppDensityValues._(spacingMultiplier: 1.0, targetSize: 44);
    static const spacious = AppDensityValues._(spacingMultiplier: 1.25, targetSize: 52);
  }
  ```
  - Persistir escolha em `IUserPreferencesRepository` (já existe);
    aplicar em data grids principais
  - **Justificativa**: Windows desktop tem usuários power que
    preferem alta densidade de informação (DBAs olhando 50 schedules
    de uma vez). Densidade configurável é padrão em ferramentas
    pro-grade (VS Code, JetBrains).

- [ ] **C0.11** — Criar `lib/core/theme/tokens/app_target_size.dart`
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

- [ ] **C0.12** — Criar `lib/core/theme/tokens/app_z_index.dart`
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
  - Aplicar em `Stack` overlays existentes
  - **Justificativa**: ordem implícita por children-order é frágil;
    z-index nomeado previne "modal atrás do dropdown"

- [ ] **C0.13** — Criar barrel `lib/core/theme/tokens/tokens.dart`
      reexportando todos

### Etapa 3 — Refatorar átomos existentes para consumir tokens

Como prova de conceito, refatorar 5 widgets atômicos para usar
tokens em vez de literais:

- [ ] **C0.14** — `AppCard` (usar `AppSpacing.paddingMd`,
      `AppRadius.circularLg`, `AppElevation.low`)
- [ ] **C0.15** — `AppButton` — refatorar para slot pattern
      (`leading`/`trailing` slots + factories
      `.primary/.icon/.loading`); aplicar `AppSpacing.sm`;
      garantir `AppTargetSize.minimum` mínimo
- [ ] **C0.16** — `AppTextField` — usar `AppSpacing.xs` para
      padding interno; `context.colors.danger` para erro
- [ ] **C0.17** — `MessageModal` — usar `AppSpacing.paddingLg`,
      `AppDuration.normal` para animação
- [ ] **C0.18** — `EmptyState` — usar tokens
- [ ] Doc-comments adicionados em cada um sinalizando nível atomic
      (`/// **Atom**`, `/// **Molecule**`, `/// **Organism**`)
- [ ] **Acessibilidade**: cada átomo refatorado deve ter
      `Semantics` adequado (label/hint/button) e respeitar
      `AppTargetSize.minimum`
- [ ] **Teste regressão crítico**: golden test para `AppCard`,
      `AppButton`, `AppTextField`, `MessageModal`, `EmptyState`
      ANTES da migração; rodar IDÊNTICO depois (zero regressão visual
      garantida)
- [ ] **Teste a11y**: usar `tester.expectAccessibilitySemanticGuidelines`
      com `androidTapTargetGuideline`, `iOSTapTargetGuideline`,
      `textContrastGuideline` em pelo menos 1 widget de cada
      categoria (atom/molecule)

### Etapa 4 — Documentação e regras

- [ ] **C0.19** — Atualizar `architectural_patterns.mdc` com nova
      **seção 8 — Design System & Componentização**:
  - [ ] Tabela "qual token usar quando"
  - [ ] Regra "composition over inheritance" com exemplos do
        `AppButton` antes/depois
  - [ ] Regra "cores semânticas via `context.colors` vs cores de marca
        via `AppPalette`"
  - [ ] Regra "doc-comment com nível atomic" para componentes
        em `widgets/common/`
  - [ ] Regra "novo widget composition-first" — checklist no PR review
  - [ ] Regra "responsividade dentro do desktop" (`AppBreakpoints`)
  - [ ] Regra "acessibilidade obrigatória" (`AppTargetSize`,
        `Semantics`, contraste 3:1)
- [ ] **C0.20** — Criar **ADR-009** em `docs/adr/`:
  - [ ] "Design System: tokens semânticos via ThemeExtension +
        composition over inheritance"
  - [ ] Contexto, decisão, alternativas (m3e_design package vs custom),
        consequências
- [ ] **C0.21** — Criar `docs/onboarding/design_system.md`:
  - [ ] Catálogo visual dos tokens
  - [ ] Como criar um widget novo seguindo o design system
  - [ ] Exemplos de slot pattern
  - [ ] Checklist de acessibilidade para novos componentes

### Etapa 5 — Lint custom (preparatório, não bloqueante)

- [ ] **C0.22** — Adicionar **TODO M9** ao roadmap (PR futuro):
      criar `custom_lint` ou script CI que detecta:
  - [ ] `SizedBox(height: NN)` literal em widgets do projeto (deve
        usar `AppSpacing.gapXX`)
  - [ ] `BorderRadius.circular(NN)` literal (deve usar `AppRadius`)
  - [ ] `Duration(milliseconds: NN)` literal em transições (deve
        usar `AppDuration`)
  - [ ] Acesso a `AppColors.X` quando equivalente em `context.colors`
        existe
  - [ ] `MediaQuery.of(context).size.width > N` literal (deve usar
        `context.isWideWindow` ou similar)
  - [ ] Targets clicáveis com `width/height < AppTargetSize.minimum`

### Critério de aceite consolidado

- [ ] `dart analyze` zero issues
- [ ] `flutter test` 100% verde (golden tests dos 5 átomos
      refatorados passam idênticos antes/depois)
- [ ] `architectural_patterns.mdc` seção 8 publicada
- [ ] ADR-009 commitada
- [ ] `docs/onboarding/design_system.md` publicado
- [ ] Cada etapa em commit separado

---

## 9. PR-D — Refator DRY de UI + UX

**Objetivo**: eliminar duplicação na presentation, quebrar god dialog em
3 dialogs especializados, entregar 4 UX wins. **Todos os widgets novos
consomem o design system do PR-C** (tokens, slot pattern,
`ThemeExtension`).

**Esforço**: 2 dias. **Critério**: ~520 linhas eliminadas, zero regressão visual.

### TODO list

- [ ] **D1** — Eliminar `String _t(...)` inline em 17 widgets (B7)
  - [ ] Substituir todas as definições por `appLocaleString(context, pt, en)` (já existe)
  - [ ] **Teste**: lint custom (grep no CI) falha se `String _t(String pt, String en)` reaparecer
- [ ] **D2** — `DatabaseTypeMetadata` (C4 + U8 + U9)
  - [ ] Criar `lib/core/utils/database_type_metadata.dart`
  - [ ] Usar cores oficiais já definidas em `AppPalette` (PR-C0.1)
  - [ ] Migrar `schedule_grid.dart`, `schedule_list_item.dart`, `database_config_page.dart`
  - [ ] **Teste**: falha se algum `DatabaseType.values` não tiver entry — força adicionar Firebird amanhã
- [ ] **D3** — `DatabaseConfigDataGrid<T>` genérico — **Organism**
       (C5)
  - [ ] Criar `lib/presentation/widgets/common/database_config_data_grid.dart`
  - [ ] Doc-comment `/// **Organism**`
  - [ ] Usa `AppSpacing/AppRadius` (PR-C tokens)
  - [ ] Substituir `SqlServerConfigList`, `SybaseConfigList`, `PostgresConfigGrid`
  - [ ] **Teste**: `database_config_data_grid_test.dart` (renderiza com diferentes T)
- [ ] **D4** — `DatabaseConfigListItem<T>` genérico — **Molecule**
       (C6 + B8)
  - [ ] Criar `lib/presentation/widgets/common/database_config_list_item.dart`
  - [ ] Doc-comment `/// **Molecule**`
  - [ ] Resolve B8 (não precisa criar `PostgresConfigListItem`)
  - [ ] **Teste**: widget test cobre cada SGBD via `DatabaseTypeMetadata`
- [ ] **D5** — Quebrar `SqlServerConfigDialog` em 3 dialogs especializados (B9, B10, B3)
  - [ ] **D5.1** — Criar `DatabaseConfigDialogShell` — **Organism**
        (header + body + actions + atalhos U4); usa `AppSpacing.lg`
        para padding
  - [ ] **D5.2** — Criar `TestConnectionRunner<TConfig>` (C7) com
        `validate/buildConfig/runTest` callbacks; **resultado como
        sealed class** `TestConnectionOutcome` (Dart 3 pattern
        matching)
  - [ ] **D5.3** — Reescrever `SqlServerConfigDialog` (apenas SQL
        Server, ~250 linhas) — usar `DatabaseConfigDialogShell` via
        composição (NÃO `extends`)
  - [ ] **D5.4** — Criar
        `lib/presentation/widgets/postgres/postgres_config_dialog.dart`
        (composição do shell)
  - [ ] **D5.5** — Atualizar `database_config_page._showPostgresConfigDialog` (elimina hack B3)
  - [ ] **D5.6** — Garantir que `SybaseConfigDialog` segue mesmo padrão
  - [ ] **Teste regressão crítico**: snapshot dos 3 dialogs ANTES via golden test ou widget test detalhado; rodar IDÊNTICO depois
  - [ ] **Teste novo**: `postgres_config_dialog_test.dart`
- [ ] **D6** — `MessageModal.showConfirm` (C10)
  - [ ] Adicionar método se não existir
  - [ ] Substituir diálogos inline em `database_config_page`
  - [ ] **Teste**: `message_modal_test.dart` cobre `showConfirm`
- [ ] **D7** — `PasswordField` com toggle "mostrar senha" (U5) —
       **Molecule**
  - [ ] Adicionar `IconButton` com `_obscured` interno
  - [ ] Doc-comment `/// **Molecule**`
  - [ ] Usa `AppDuration.fast` para animação do ícone
  - [ ] **Teste**: widget test toggle visibility
- [ ] **D8** — `_SectionHeader` com badge ativas/inativas (U1) —
       **Molecule**
  - [ ] Estender em `database_config_page.dart`
  - [ ] Usa `context.colors.success/danger` para badges
  - [ ] **Teste**: widget test renderiza badges
- [ ] **D9** — Atalhos de teclado em dialogs (U4)
  - [ ] `Esc` → cancel; `Ctrl+Enter` → save (Enter sozinho conflita com TextField multiline)
  - [ ] Aplicar em `DatabaseConfigDialogShell`
  - [ ] **Teste**: widget test simula tecla e valida ação

---

## 10. PR-E — Hexagonal foundation: ports + base classes genéricas

**Objetivo**: consolidar duplicação SGBD-específica em ports
parametrizados + base classes (Template Method); preparar Firebird (e
SGBDs futuros) para ser uma operação trivial.

**Esforço**: 2,5 dias. **Critério**: ~430 linhas eliminadas, zero
regressão funcional, **3 SGBDs migrados em commits separados** (Sybase
POC primeiro).

### Etapa 1 — Domain (definir ports e abstrações)

- [ ] **E1** — `DatabaseConnectionConfig` abstract class
  - [ ] Criar `lib/domain/entities/database_connection_config.dart`
  - [ ] Campos universais: `id`, `name`, `enabled`, `host`, `port`, `username`, `password`, `databaseType`, `createdAt`, `updatedAt`, `backupTarget`
  - [ ] Migrar `SqlServerConfig`, `SybaseConfig`, `PostgresConfig` para `extends DatabaseConnectionConfig` com aliases (`@override host => server`, etc.)
  - [ ] **Teste**: `database_connection_config_test.dart` confirma LSP
- [ ] **E2** — `IDatabaseConfigRepository<T>` port genérico
  - [ ] Criar `lib/domain/repositories/i_database_config_repository.dart`
  - [ ] Manter `ISqlServerConfigRepository`, etc. como **marker interfaces** (back-compat)
  - [ ] **Teste**: marker interfaces compilam
- [ ] **E3** — `IDatabaseBackupPort<T>` port genérico
  - [ ] Criar `lib/domain/services/i_database_backup_port.dart`
  - [ ] Criar `BackupExecutionContext` DTO encapsulando 12 args
  - [ ] Manter `I*BackupService` como marker interfaces
  - [ ] **Teste**: marker interfaces compilam

### Etapa 2 — Infrastructure (base class de repositório)

- [ ] **E4** — `BaseDatabaseConfigRepository<T, TData>`
  - [ ] Criar `lib/infrastructure/repositories/base_database_config_repository.dart` com Template Method (CRUD comum + hooks `daoX/toEntity/onBeforeDelete`)
  - [ ] Usa `RepositoryGuard` + `SecureCredentialHelper` (PR-B)
  - [ ] **Teste**: `base_database_config_repository_test.dart` com fake DAO
- [ ] **E5** — Migrar `SybaseConfigRepository` (POC)
  - [ ] Reescrever para `extends BaseDatabaseConfigRepository<SybaseConfig, SybaseConfigsTableData>`
  - [ ] Preservar `_tableExists` defensivo (vira hook opcional)
  - [ ] **Teste**: testes existentes passam idêntico
- [ ] **E6** — Migrar `SqlServerConfigRepository`
  - [ ] **Teste**: idem
- [ ] **E7** — Migrar `PostgresConfigRepository`
  - [ ] Override `onBeforeDelete` com `_dropWalReplicationSlotBestEffort`
  - [ ] **Teste**: testes existentes passam (incluindo WAL slot cleanup)

### Etapa 3 — Application (provider base + strategy genérica)

- [ ] **E8** — `DatabaseConfigProviderBase<T>`
  - [ ] Criar `lib/application/providers/database_config_provider_base.dart`
  - [ ] Hook `verifyToolsOrThrow()` (default no-op)
  - [ ] Hook abstrato `duplicateConfigCopy(T source) -> T`
  - [ ] **Teste**: `database_config_provider_base_test.dart` com fake repo
- [ ] **E9** — Migrar `SybaseConfigProvider`
  - [ ] Override `verifyToolsOrThrow` (`_toolVerificationService.verifySybaseTools`)
  - [ ] Override `duplicateConfigCopy`
  - [ ] **Teste**: testes existentes passam
- [ ] **E10** — Migrar `SqlServerConfigProvider`
  - [ ] Override `verifyToolsOrThrow` (verifica `sqlcmd`)
  - [ ] **Teste**: testes existentes passam
- [ ] **E11** — Migrar `PostgresConfigProvider`
  - [ ] Sem override (usa default)
  - [ ] **Teste**: testes existentes passam

### Etapa 4 — Application (strategy genérica)

- [ ] **E12** — `GenericDatabaseBackupStrategy<T>` + `BackupValidationRule<T>` + `BackupResultEnricher<T>`
  - [ ] Criar `lib/application/services/strategies/generic_database_backup_strategy.dart`
  - [ ] Criar `lib/application/services/strategies/rules/`:
    - `PostgresRejectConvertedTypesRule`
    - `SqlServerRejectConvertedTypesRule`
    - `SybaseRejectDifferentialRule` (extraída de `SybaseBackupStrategy:45-51`)
    - `SybaseLogBackupPreflightRule` (extraída de `SybaseBackupStrategy:54-75`)
    - `SybaseRejectTruncateInReplicationRule` (extraída de `SybaseBackupStrategy:90-101`)
  - [ ] Criar `lib/application/services/strategies/enrichers/`:
    - `SybaseChainMetadataEnricher` (extraída de `SybaseBackupStrategy:121-144`)
  - [ ] **Teste**: cada `Rule` e `Enricher` ganha teste isolado
- [ ] **E13** — Factories de strategies
  - [ ] `SqlServerBackupStrategyFactory.create(port)`
  - [ ] `SybaseBackupStrategyFactory.create({port, validatePreflight})` — 3 rules + 1 enricher
  - [ ] `PostgresBackupStrategyFactory.create(port)`
  - [ ] **Teste**: factory tests confirmam rules corretas
- [ ] **E14** — Refatorar `BackupOrchestratorService._buildDefaultStrategies`
  - [ ] **Teste**: `backup_orchestrator_service_test.dart` passa equivalente

### Etapa 5 — DI (helper `registerSgbd`)

- [ ] **E15** — Criar `lib/core/di/sgbd_registration.dart`
  - [ ] Extension method `registerSgbd<TConfig, TData>` em `GetIt`
  - [ ] **Teste**: `sgbd_registration_test.dart` registra fake e valida resolução

### Etapa 6 — Documentação

- [ ] **E16** — Atualizar `architectural_patterns.mdc`:
  - [ ] Nova seção "Padrão Hexagonal/Generic para SGBDs"
  - [ ] Quando usar `BaseDatabaseConfigRepository<T,TData>` vs implementação direta
  - [ ] Quando usar `GenericDatabaseBackupStrategy<T>` + `Rule`/`Enricher`
  - [ ] Cookbook "Como adicionar um novo SGBD" (passo a passo, < 1 página)
- [ ] **E17** — Criar **ADR-004** em `docs/adr/`:
  - [ ] "Adoção de Generic Hexagonal Ports para SGBDs"
  - [ ] Contexto, decisão, alternativas consideradas, consequências

### Critério de aceite consolidado

- [ ] `dart analyze` zero issues
- [ ] `flutter test` 100% verde
- [ ] Coverage helpers/base classes ≥80%
- [ ] Cada etapa em commit separado
- [ ] PR description com benchmark de linhas eliminadas SGBD por SGBD

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
- [ ] Adicionar `freezed`, `freezed_annotation`, `json_serializable`
      ao `pubspec.yaml`
- [ ] Migrar entities: `SqlServerConfig`, `SybaseConfig`,
      `PostgresConfig`, `FirebirdConfig` (após PR-E),
      `BackupHistory`, `BackupLog`, `Schedule`,
      `BackupExecutionContext`
- [ ] Criar **ADR-006**: "Adoção de freezed para entities/DTOs"
- [ ] **Teste**: re-rodar suíte completa; equality/copyWith devem
      ser equivalentes

### M2 — Lint cleanup (re-habilitar regras desligadas)

**Esforço**: 0,5-1 dia. **ROI**: detecção precoce de bugs futuros.

- [ ] Re-habilitar em `analysis_options.yaml`:
  - `avoid_dynamic_calls: true` (com exceções pontuais via `// ignore:`)
  - `unawaited_futures: true` (substituir fire-and-forget intencional por `unawaited(...)`)
  - `discarded_futures: true`
- [ ] Tratar warnings que aparecerem (estimativa: 30-50 spots)
- [ ] **Teste**: `dart analyze` zero
- [ ] Documentar em PR description as exceções justificadas

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

- [ ] **ADR-005**: "Decisão sobre folder structure (manter layer-first)"
      — para evitar discussão recorrente
- [ ] **ADR-006**: M1 (freezed)
- [ ] **ADR-007**: "Deprecação de PortNumber.isDefault" (se decidirmos
      remover em vez de atualizar)

### M5 — Documentação para onboarding

- [ ] Criar `docs/onboarding/adicionar_sgbd.md` com cookbook do PR-D
      (extração da seção 14 do `architectural_patterns.mdc`)
- [ ] Criar `docs/onboarding/architecture_overview.md` com diagrama
      mermaid das camadas
- [ ] Atualizar `README.md` com link para os ADRs e onboarding

### M6 — Estatística de cobertura no CI

Atualmente cobertura é gerada localmente via `coverage` package.
Subir relatório em PR (Codecov ou similar) ajuda a identificar
regressões rapidamente.

**Esforço**: 0,5 dia.

### M7 — Migração futura para feature-first (avaliar quando)

Não migrar agora. Reavaliar quando:
- Houver 3+ features ortogonais (ex.: backup + dashboard analytics +
  audit module)
- Time crescer para >5 desenvolvedores trabalhando em paralelo
- Surgir necessidade de extrair módulos para packages separados

Documentar como **ADR-008** (futuro) quando houver.

### M8 — Atomic Design folder hierarchy

**Esforço**: 1 dia. **ROI**: navegação mais clara entre níveis de
componente; alinhamento com convenção de mercado 2026 ([Rodrigo
Nepomuceno 2026](https://rodrigonepomuceno.medium.com/atomic-design-in-flutter-modular-ui-architecture-with-design-systems-72f813c18af4)).

**Pré-requisito**: PR-C mergeado (componentes já documentam nível
atomic em doc-comments).

**Plano**:
- [ ] Mover `widgets/common/` para hierarquia explícita:
  ```
  presentation/widgets/
    atoms/        (AppButton, AppTextField, AppCard, AppIcon, EmptyState)
    molecules/    (PasswordField, SaveButton, _SectionHeader,
                  DatabaseConfigListItem, DatabaseConfigDialogShell)
    organisms/    (MessageModal, DatabaseConfigDataGrid, AppDataGrid)
  ```
- [ ] Atualizar imports em massa via `dart fix`
- [ ] Manter pastas por feature (`widgets/sql_server/`, `widgets/postgres/`,
      etc.) — moléculas/organismos específicos de feature ficam lá
- [ ] **Teste**: re-rodar suíte completa (sem mudança funcional)
- [ ] Documentar como **ADR-010**

### M9 — Custom lint para guardrails do Design System

**Esforço**: 1 dia. **ROI**: previne degradação do design system.

**Pré-requisito**: PR-C mergeado (tokens estabilizados).

**Plano** (referenciado como C0.22 no PR-C):
- [ ] Adicionar `custom_lint` package ao `dev_dependencies`
- [ ] Criar regras custom (ou script CI alternativo):
  - `prefer_app_spacing` — flag `SizedBox(height: NN)` literal
    (deve usar `AppSpacing.gapXX` ou `AppSpacing.md`)
  - `prefer_app_radius` — flag `BorderRadius.circular(NN)` literal
  - `prefer_app_duration` — flag `Duration(milliseconds: NN)` em
    transições de UI
  - `prefer_semantic_colors` — flag `AppColors.X` quando equivalente
    em `context.colors` existe
  - `widget_must_document_atomic_level` — widgets em
    `widgets/common/` devem ter doc-comment com `**Atom**`,
    `**Molecule**` ou `**Organism**`
  - `prefer_app_breakpoints` — flag `MediaQuery.of(context).size.width > N`
    literal
  - `enforce_target_size` — flag `width/height < 44` em widgets
    clicáveis (`GestureDetector`, `IconButton`, `Button`)
- [ ] **Teste**: lints aplicadas a código existente devem passar
      (ou ter justificativas via `// ignore:`)

### M10 — Widgetbook (component catalog)

**Esforço**: 2 dias. **ROI**: catálogo visual interativo de todos
os componentes; designers/PMs podem revisar UI sem rodar o app;
golden tests automáticos por variante.

**Pré-requisito**: PR-C mergeado (componentes estáveis e tokenizados).

**Plano**:
- [ ] Adicionar `widgetbook` + `widgetbook_generator` ao
      `dev_dependencies`
- [ ] Criar `widgetbook/` separate Flutter app (entry point
      `widgetbook/main.dart`)
- [ ] Criar **stories** para cada átomo/molécula/organismo do
      design system:
  - `AppButton` — todas as variantes (primary/secondary/danger,
    com/sem ícone, loading, disabled)
  - `AppTextField` — estados (default/focused/error/disabled);
    com/sem prefix/suffix
  - `PasswordField`, `MessageModal`, `EmptyState`,
    `DatabaseConfigDataGrid`, etc.
- [ ] Adicionar **knobs** (controles interativos) para variar
      props em runtime (cor, tamanho, tema)
- [ ] Adicionar **add-ons** para troca de tema (Light/Dark) e
      densidade (compact/comfortable/spacious)
- [ ] Configurar **golden tests automáticos** por variante via
      `widgetbook_test`
- [ ] Documentar como **ADR-011**
- [ ] Avaliar **Widgetbook Cloud** para integração com Figma e
      revisão visual de PRs (opcional, paga)

### M11 — Skeleton loaders (substituir spinners)

**Esforço**: 1 dia. **ROI**: UX melhor — usuários percebem o app
mais rápido (validado em [Aman Sharma 2026 (Medium)](https://medium.com/@aks.sharma312/ditch-the-spinner-implementing-skeleton-loading-for-better-ux-in-flutter-2a5402ba99d5)).

**Pré-requisito**: PR-C mergeado (tokens de cor disponíveis).

**Plano**:
- [ ] Adicionar `shimmer` package (v3.0.0+) ao `dependencies`
- [ ] Criar átomo `AppShimmer` em `widgets/common/` que aplica
      cores do tema (`baseColor` + `highlightColor` de
      `AppSemanticColors`)
- [ ] Criar moléculas `SkeletonCard`, `SkeletonListItem`,
      `SkeletonGrid` para layouts comuns
- [ ] Substituir `ProgressRing` em telas list-heavy:
  - `database_config_page` (carga inicial dos 4 SGBDs)
  - `schedules_page` (carga de schedules)
  - `dashboard_page` (carga de métricas)
  - `logs_page` (carga de logs)
- [ ] **Manter** `ProgressRing` em ações inline curtas
      (botão "Salvar", "Testar conexão") — skeleton só faz sentido
      em load de tela cheia
- [ ] Flag de feature em `IUserPreferencesRepository` para
      desabilitar (acessibilidade — usuários sensíveis a animação)
- [ ] **Teste**: widget tests confirmam que `enabled: false`
      desabilita animação para testes determinísticos

### M12 — Auditoria de acessibilidade (a11y) completa

**Esforço**: 1,5 dia. **ROI**: conformidade WCAG 2.1 AA; preparação
para distribuição corporativa onde a11y é requisito legal (ADA,
Section 508, EN 301 549).

**Pré-requisito**: PR-C + PR-D mergeados (componentes finalizados).

**Plano**:
- [ ] Rodar `tester.expectAccessibilitySemanticGuidelines` em
      **todas as páginas principais** (`database_config_page`,
      `schedules_page`, `dashboard_page`, etc.)
- [ ] Validar contraste de texto ≥ 3:1 em ambos os temas
      (Light/Dark) usando `textContrastGuideline`
- [ ] Validar target size mínimo (44×44) usando
      `androidTapTargetGuideline`
- [ ] Adicionar `Semantics(label:, hint:)` em widgets customizados
      onde falta (auditoria por arquivo)
- [ ] Adicionar `excludeFromSemantics: true` em ícones decorativos
- [ ] Validar suporte a escala de texto do sistema
      (`MediaQuery.textScaler`) — testar com 1.5× e 2.0×
- [ ] Validar navegação completa por teclado (`Tab`/`Shift+Tab`/
      `Enter`/`Esc`) em todos os fluxos críticos
- [ ] Documentar como **ADR-012** "Conformidade WCAG 2.1 AA"
- [ ] Adicionar checklist de a11y ao template de PR

### M13 — Design tokens em formato W3C JSON (interop com Figma)

**Esforço**: 1 dia. **ROI**: design tokens podem ser editados por
designers no Figma e exportados para o código (round-trip);
validado em [Figma 2026 release](https://figma.obra.studio/design-tokens-community-group-w3c-release/).

**Pré-requisito**: PR-C mergeado.

**Plano**:
- [ ] Criar `design-tokens/` na raiz do repo com JSON files
      seguindo a [W3C Design Tokens Spec](https://design-tokens.github.io/community-group/format/):
  - `colors.tokens.json` (palette + semânticas)
  - `spacing.tokens.json`
  - `radius.tokens.json`
  - `motion.tokens.json`
- [ ] Criar script `tools/generate_tokens.dart` que lê o JSON
      e gera os arquivos Dart (`AppPalette`, `AppSpacing`, etc.)
      automaticamente
- [ ] Documentar fluxo: designer edita Figma → exporta JSON →
      script gera Dart → PR de revisão
- [ ] Avaliar se vale o esforço dado o tamanho do projeto;
      pode ficar como **opcional** se o time não tiver designer
      dedicado

### M14 — Integração nativa Windows (Mica/Acrylic effects)

**Esforço**: 1 dia. **ROI**: app "parece nativo Windows" com
efeitos visuais modernos do Windows 11 (Mica, Acrylic
backdrop). Validado em [arhaminfo 2026](https://www.arhaminfo.com/2025/11/flutter-windows-application.html).

**Pré-requisito**: PR-C mergeado (tokens de cor estáveis).

**Plano**:
- [ ] Adicionar `flutter_acrylic` package
- [ ] Adicionar `system_theme` package (lê accent color do Windows
      e aplica em `AppSemanticColors` opcionalmente)
- [ ] Habilitar Mica backdrop em `main_layout.dart` (Windows 11)
- [ ] Adicionar setting "Usar accent color do sistema"
      (default: `false`; quando `true`, sobrescreve
      `AppPalette.brandPrimary` em runtime)
- [ ] **Teste**: smoke manual em Windows 10 (sem Mica) e Windows 11
      (com Mica)
- [ ] Documentar como **ADR-013**

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
   - `getIt.registerSgbd<MySqlConfig, MySqlConfigsTableData>(...)`

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
