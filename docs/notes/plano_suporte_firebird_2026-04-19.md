# Plano: Suporte a Backup de Bancos Firebird

Data base: 2026-04-19
Revisão documental: 2026-05-18 (§3.0 / §8.2 alinhados ao repositório;
`dart analyze` + `flutter test` reverificados — ver §8.2).
Status: **Plano concluído (MVP no repositório, 2026-05-18).** O critério **§3.0**
e a verificação automática **§8.2** estão satisfeitos. **§8.1** (smokes manuais)
e o backlog em **§3.0** (*Fora do escopo actual do código*) e na subsecção **E4**
da secção documental **§3** (*PR-E*; pós-MVP) não fazem parte deste fecho.

**Entrega que cumpre o objetivo MVP** (PR-E + PR-F + PR-G): núcleo **PR-E**
(domain, Drift v32, repository, `FirebirdBackupService` gbak +
`nbackup -B 0` / `-B 1` + gstat, strategy, DI, CLI, scripts `isql`), **PR-F** (UI,
grid, U7/`schedule_dialog`, testes de widget), **PR-G** (capabilities,
protocolo, CRUD remoto com `supportsFirebird`, goldens de protocolo, U10,
UI condicional no cliente) cobrem o fluxo **MVP** (Full / Full Single /
Diferencial / Log com `nbackup`, gate remoto, métricas com hint de versão).

**Fora do MVP** (não bloqueia merge nem CI): fixture SQLite legada v29-only;
**smokes manuais** §8 (**§8.1**; opcionais para o critério §3.0); **código
futuro** — §3.0 (*Fora do escopo actual do código*) e subsecção **E4** na secção
documental **§3** (*PR-E*).
**Fecho do plano (MVP / repositório) concluído com código + CI:** **§8.2**
(2026-05-18).

**No MVP já entregue:** **Cascata auth / WireCrypt §1.6** na execução (retry
`-PROVIDER Engine12`, mensagens WireCrypt alargadas) em
`firebird_backup_service.dart`. **`gbak` / `nbackup -SE service_mgr`**
condicionados (`serviceManagerMode` + hint §1.6.7; helper
`_firebirdServiceManagerSwitch`) no mesmo serviço. **Métricas (2026-05-18):** em
backups Firebird **bem-sucedidos** (`gbak` ou `nbackup`), `BackupMetrics.flags`
inclui `tool: gbak` ou `tool: nbackup` e `firebirdVersion` (`auto` \| `v25` \| `v30` \| `v40`; com hint **Auto**, sonda
`gbak -z` pode enriquecer para `auto|WI-V…` quando o token é parseável).
Gate `supportsFirebird` no servidor cobre
CRUD (`ScheduleCrudMessageHandler`), `executeSchedule` (`ScheduleMessageHandler`)
e `startBackup`/fila (`ExecutionMessageHandler`); DI usa default `true` nos
handlers e `kSocketServerSupportsFirebird` em `CapabilitiesMessageHandler`.
O pré-requisito do plano de refatoração (PR-A–E) está atendido para o que já foi
mergeado.

*Leitura rápida:* **`## Objetivo`** (topo) = metas MVP, exclusões e *Conclusão* do
plano; **`Meta (PR-E/F/G)`** em **§3–§5** = rubricas de planeamento *por PR*
(histórico, não o estado entregue); **§3.0** = critério e rastreio do MVP no
repositório; **§8** = smokes manuais (opcionais para esse critério); **§8.2** =
fecho documental do plano no repositório sem QA manual; **código ainda por
fazer** = parágrafo **Fora do escopo actual do código** no §3.0 + inventário na
subsecção **E4** na secção documental **§3** (*PR-E*; p.ex. `nbackup` >1,
`listDatabases` (Firebird em `IFirebirdBackupService`; §10), …); **§9 Fecho** = mapa de secções e hiperligações; **§10** =
continuação **pós-MVP** (checklist opcional no fim do ficheiro).

*Nota de navegação:* **§3.0** é a secção “Rastreio código ↔ plano” (estado MVP
no repositório) — **não** é o “capítulo 3” do documento. O capítulo **§3** é
*PR-E — Domain + Infraestrutura + CLI* e contém a subsecção **E4**; **§4**–**§7**
seguem a ordem do índice; **§8**–**§9** cobrem pré-entrega / smokes e
referências cruzadas; **§10** (fim do ficheiro) rastreia **continuação pós-MVP**
opcional.

## Objetivo

1. **Produto:** disponibilizar Firebird **2.5, 3.0 e 4.0** como **quarto SGBD**
   em paridade com SQL Server, Sybase ASA e PostgreSQL — cadastro, tipos de
   backup suportados (`gbak` / `nbackup`), agendamentos, execução **local** e
   **remota** (socket + capability `supportsFirebird`).
2. **Engenharia:** implementar sobre o stack do plano de refatoração
   (repositórios base, estratégia genérica, design system, DI) com **CI verde**
   (`dart analyze`, `flutter test`, `build_runner` / `.g.dart` alinhados ao
   schema — **§3.0** / **§8.2**).
3. **Fora do objetivo deste plano (registados para evolução):** matriz manual
   **§8.1**; backlog **E4** (subsecção na secção documental **§3** / *PR-E*) / *Fora do escopo actual do código* (§3.0).

**Conclusão:** o **objetivo MVP** (itens 1 e 2) foi **atingido**; o plano
considera-se **fechado para o repositório** em **2026-05-18** ao abrigo de
**§8.2**. Quem precisar de **evidência operacional** (motores reais,
cliente↔servidor) segue **§8.1**; quem continuar funcionalidades Firebird trata
**E4** (subsecção na secção documental **§3** / *PR-E*) / prioridade sugerida em **§3.0** como trabalho **posterior** a este
documento.

> **Pré-requisito**: este plano assume que o
> [`plano_refatoracao_e_melhorias_2026-04-19.md`](./plano_refatoracao_e_melhorias_2026-04-19.md)
> está mergeado (PRs A, B, C, D, E). Sem ele, a implementação de
> Firebird seria ~3× maior por reintroduzir duplicações que foram
> eliminadas, perder os helpers/abstrações genéricas e ficar fora do
> design system consolidado (tokens, ThemeExtension, slot pattern).

---

## Sumário executivo

O suporte MVP a Firebird **foi entregue** em **três PRs sequenciais** após o
plano de refatoração (faseamento histórico):

| PR | Esforço | Linhas | Resultado |
|---|---|---|---|
| **PR-E** Firebird domain + infra + CLI | 1,5 dia | +350 | backup coberto por testes unitários (CLI mock) no CI |
| **PR-F** Firebird UI + UX (U2/U3/U6/U7) | 1,5 dia | +400 | utilizador cadastra e executa pelo app |
| **PR-G** Firebird remoto (socket) + U10 | 1 dia | +150 | servidor expõe Firebird ao cliente |
| **Total** | **4 dias** | **+900** | MVP **concluído no repositório** (2026-05-18); evolução técnica → §3.0 (*Fora do escopo actual*) + subsecção **E4** (**§3** / *PR-E*) |

*Fecho do plano (MVP / repositório): **§8.2** — **concluído** 2026-05-18 (código + CI).*
*Smoke operacional opcional:* **§8** / **§8.1**.

**Comparativo**: sem o plano de refatoração precedente, a entrega
seria ~7-8 dias e +1500 linhas. O ROI vem do reuso de:
- `BaseDatabaseConfigRepository` (PR-E hexagonal)
- `DatabaseConfigProviderBase` (PR-E)
- `GenericDatabaseBackupStrategy` (PR-E)
- `DatabaseConfigDialogShell` (PR-D refator UI)
- `DatabaseTypeMetadata` (PR-D)
- `AppPalette`, `AppSpacing`, `AppRadius`, `AppDuration`,
  `AppSemanticColors` (PR-C design system) — **identidade visual
  Firebird vem automaticamente alinhada com SGBDs existentes**

---

## 1. Estado da Arte: Backup em Firebird (pesquisa 2026-04)

Pesquisa em [`firebirdsql.org/manual`](https://www.firebirdsql.org/),
[`firebirdsql.org/pdfmanual`](https://www.firebirdsql.org/pdfmanual/),
issues do `FirebirdSQL/jaybird` no GitHub, fórum oficial e
documentação Tetrasys (FB 5).

### 1.1 Modelos de backup oficiais

| Modelo | Ferramenta | Tipo |
|---|---|---|
| Lógico full single-file | `gbak` | exporta estrutura + dados em formato portável (`.fbk`) |
| Físico full | `nbackup -B 0` | snapshot binário das páginas (rápido, não-portável) |
| Físico incremental N-níveis | `nbackup -B 1..N` | apenas páginas alteradas; cadeia até 9 níveis |
| Lock/Unlock para ferramenta externa | `nbackup -L`/`-N` | congela `.fdb` redirecionando writes para `.delta` |
| Hot backup via SQL | `ALTER DATABASE BEGIN/END BACKUP` | equivalente SQL ao `-L`/`-N` |
| Services API | `gbak -SE service_mgr` ou `nbackup -SE service_mgr` | até **30% mais rápido em conexões remotas** |

### 1.2 Verificação de integridade — descoberta importante

**Não existe `gbak -t` ou flag dedicada de verify** em nenhuma versão.
A pesquisa confirmou que:

- `-V[ERIFY]` no manual significa **verbose**, não verify
- A única forma robusta de validar integridade de backup gbak é
  **restaurar para banco temporário** (`gbak -C`)
- nbackup também não tem verify; integridade depende da cadeia
  GUID/SCN registrada em `RDB$BACKUP_HISTORY`

**Implicação para o app**:
- Modo `none`/`bestEffort` (default): pula verify + log informativo
- Modo `strict` (opt-in): restore para ficheiro temporário (caro,
  exige espaço extra; documentado no tooltip)

### 1.3 Tamanho do banco — query oficial

```sql
SELECT MON$PAGE_SIZE * MON$PAGES AS size_bytes FROM MON$DATABASE
```

Disponível desde Firebird 2.1, idêntico em 2.5/3.0/4.0. Na implementação
actual (`FirebirdBackupService.getDatabaseSizeBytes`): `isql` executa o
`SELECT` acima; se falhar ou for inválido, tenta-se `gstat -h` (parse de
cabeçalho); se `gstat` também falhar e o modo for **embedded**, usa-se
`File(databaseFile).length()` como último recurso (tamanho em disco, não
necessariamente igual ao uso lógico de páginas).

### 1.4 Diferenças relevantes entre 2.5 / 3.0 / 4.0

| Aspecto | FB 2.5 | FB 3.0 | FB 4.0 |
|---|---|---|---|
| ODS (On-Disk Structure) | 11.2 | 12.0 | 13.0 |
| Auth padrão | `Legacy_Auth` | `Srp` | `Srp256` |
| Auth fallback (config no servidor) | — | `AuthServer = Legacy_Auth, Srp` | `AuthServer = Legacy_Auth, Srp, Srp256` |
| WireCrypt | inexistente | opcional | **`Required` por default** — clientes 2.5/3.0 antigos sem WireCrypt são rejeitados |
| Connection string | `host/port:path` ou `host:port:path` | `host/port:path` | `host/port:path` ou `inet://host:port/path` |
| `gbak -SE service_mgr` | disponível | disponível (~30% mais rápido) | disponível (~30% mais rápido) |
| `nbackup -SE service_mgr` | indisponível | disponível | disponível |
| `nbackup` GUID-based | não | não | **sim** (`-B GUID`) |
| `gbak` encryption | n/a | via plugin externo | nativo (`-CRYPT`, `-KEYHOLDER`, `-KEYNAME`, `-FE`) |
| Embedded plugin | só `fbclient.dll` | + `engine12.dll` em `plugins/` | + `engine13.dll` em `plugins/` |
| Replication nativa | inexistente | inexistente | sim (não cobrimos backup de replica nesta entrega) |

**MVP no código:** `FirebirdBackupService` aplica **`-SE`** só na linha
**`gbak` e `nbackup`** (§1.6.7): ambos podem usar **`-SE host/port:service_mgr`**
via `_firebirdServiceManagerSwitch` no `FirebirdBackupService` (`gbak` após
`-b`/`-c`; `nbackup` após `-PASSWORD`, antes de `-B`).

### 1.5 Mapeamento `BackupType` do app → ferramenta Firebird

| `BackupType` no app | Ferramenta Firebird | Justificativa |
|---|---|---|
| `BackupType.fullSingle` | `gbak -B` (com `-SE service_mgr` condicionado §1.6.7) | backup lógico portável; restore via `gbak -C`/`-R` |
| `BackupType.full` | `nbackup -B 0` (com `-SE` condicionado §1.6.7 em FB 3+) | snapshot físico nível 0 |
| `BackupType.differential` | `nbackup -B 1` (MVP; `-SE` §1.6.7 quando aplicável; **níveis >1** / cadeia completa = backlog) | incremental físico na mesma base após nível 0 |
| `BackupType.log` | `nbackup -B 1` (MVP; `-SE` §1.6.7 quando aplicável) | sem WAL exportável; execução alinhada a incremental; histórico pode gravar como Diferencial |
| `BackupType.convertedDifferential` / `convertedLog` | `nbackup -B 1` | compatível com agendamentos convertidos do Sybase |
| `BackupType.convertedFullSingle` | **rejeitado** (`FirebirdSupportedBackupTypesRule`) | usar Full Single (gbak) ou Full (`nbackup -B 0`) |

### 1.6 Implicações de design

1. **Detecção de versão (hint)**: no código, `FirebirdServerVersionHint`
   (`auto` \| `v25` \| `v30` \| `v40`) em `firebird_config_enums.dart` — não há
   ficheiro `firebird_server_version.dart` com enum `{ unknown, … }` nem helpers
   estáticos listados no rascunho original; parsing de saída `gbak -z` /
   `gstat -h` vive no `FirebirdBackupService` (métricas / UI).
2. **Cache de versão (parcial)**: `gbak -z` com cache em memória por chave de
   instalação no serviço (`_gbakZTaglineCache`); invalidação completa por
   `host:port:db` como no desenho original = backlog fino.
3. **Resolução em ordem (operacional)**: respeitar `serverVersionHint`; com
   **Auto**, sonda `gbak -z` antes de backup quando activo; hint ODS/WI-V na UI
   via `probeGstatHeaderConnection` (`gstat -h`).
4. **WireCrypt em FB 4.0**: mensagens dedicadas + variantes em
   `_failureFromProcess` (`firebird_backup_service.dart`).
5. **Auth fallback em cascata (entregue)**: após `your user name and password are
   not defined`, segunda tentativa com `-PROVIDER Engine12` quando
   `serverVersionHint != v25` (`_runFirebirdCliWithOptionalLegacyRetry` em
   `gbak` / `nbackup` / `gstat` / `isql` / verify `gbak -c`).
6. **Embedded validation**: `_validateEmbeddedEnginePlugins` (Windows + FB3+)
   antes de `gstat`/`gbak` / backup.
7. **`-SE service_mgr` em `gbak` e `nbackup` (entregue)**: `serviceManagerMode`
   na entidade (Drift/UI); `FirebirdBackupService` insere `-SE` e o par
   `host/port:service_mgr` via `_firebirdServiceManagerSwitch`: em **`gbak`**
   após `-b` (Full Single) e após `-c` (verify); em **`nbackup`** após
   `-PASSWORD` e antes de `-B` (Full / Diferencial / Log). **Omitido** em
   `useEmbedded` ou `never`; em **`always`**, excepto `serverVersionHint == v25`;
   em **`auto`**, só para hints **v30** e **v40** (não para `auto` nem `v25`).
   Testes em `firebird_backup_service_test.dart`.
8. **Criptografia lógica**: campo `cryptKey` na config; CLI actual usa **`-key`**
   no `gbak -b`/`-c` (não `-KEYNAME`/`-CRYPT` do manual FB4); evolução para
   flags completas = backlog.

---

## 2. Faseamento (3 PRs sequenciais)

```
┌──────────────────────────────────────────────────────────────────┐
│ PR-E  Firebird domain + infra + CLI   (1.5 dia)  →  +350 linhas  │
│        Entity, repository (Base), service, strategy (Generic)    │
├──────────────────────────────────────────────────────────────────┤
│ PR-F  Firebird UI + UX (U2/U3/U6/U7)  (1.5 dia)  →  +400 linhas  │
│        DatabaseConfigDialog Firebird; refator schedule_dialog    │
├──────────────────────────────────────────────────────────────────┤
│ PR-G  Firebird remoto + U10           (1 dia)    →  +150 linhas  │
│        Capabilities, protocol, golden tests, InfoBar UX          │
└──────────────────────────────────────────────────────────────────┘
                              Total: 4 dias / +900 linhas (líquido)
```

---

## 3.0 Rastreio código ↔ plano (atualizado 2026-05-18)

**Nota:** para além do checklist evolutivo **§10** (pós-MVP), os únicos `- [ ]`
que permanecem neste ficheiro como foco de QA são os **smokes manuais** do §8 (evidência de release; roteiro **§8.1**). O **fecho do plano no
repositório sem** essa evidência manual está em **§8.2**. O critério de MVP no
repositório está no parágrafo seguinte.

**Sincronização recente (doc ↔ código):** `-SE` em **`gbak`** e **`nbackup`**
(`_firebirdServiceManagerSwitch`, §1.6.7); matriz §8.1 (v25 sem `-SE`; 3.x/4.x
com `-SE` quando a política aplica). Número actual de testes no bullet **PR-E**
do §8 (`flutter test`: **1454** pass, **11** skip, 2026-05-18). **Fecho do plano
no repositório** sem QA manual: ver **§8.2**.

**Critério “plano MVP concluído”:** PR-E/F/G implementados, `dart analyze` /
`flutter analyze` sem issues, `flutter test` verde, `build_runner` sem erros
e artefactos `.g.dart` **coerentes** com o schema (incluir no commit do PR —
ver §8). **Os `- [ ]` do §8 são só QA manual / evidência de release** (§8.1);
cumprir o critério acima **não** exige marcá-los (**§8.2**). A lista **Entregas
incrementais** abaixo (só `[x]`), o parágrafo **Fora do escopo actual do
código**, e esses smokes manuais expandem o produto ou QA operacional; **não**
reabrem o MVP.

**Já entregue (repositório atual):**

- [x] Domain: `DatabaseType.firebird`, `FirebirdConfig` estendendo
      `DatabaseConnectionConfig`, enums em `firebird_config_enums.dart`
      (cobre hints de versão / service manager em vez do ficheiro
      `firebird_server_version.dart` isolado do rascunho original)
- [x] Ports: `IFirebirdConfigRepository`, `IFirebirdBackupService`,
      exports em `repositories.dart` / `services.dart`, `GetDatabaseConfig`
- [x] Drift: `FirebirdConfigsTable`, `FirebirdConfigDao`, migration **v32**
      em `AppDatabase`, `FirebirdConfigRepository` via
      `BaseDatabaseConfigRepository`
- [x] Backup: `FirebirdBackupService` (**Full** = `nbackup -B 0` + `.nbk`;
      **Full Single** = `gbak -b` + `.fbk`; **Diferencial** / **Log** (e
      convertidos, exceto `convertedFullSingle`) = `nbackup -B 1` + avisos;
      rejeita `cryptKey` em backup **físico** / `nbackup`), `gstat -h` para
      teste de conexão (mesma validação embedded Win+FB3+ que o backup, antes
      do `gstat`); tamanho = `isql` + `MON$DATABASE`
      (`MON$PAGE_SIZE * MON$PAGES`) → `gstat -h` → `File.length()` (só
      embedded se `gstat` falhar); **embedded Win + FB3+**: validação antes de
      `gstat`/`gbak` de `fbclient.dll` + `plugins/engine12.dll` ou `engine13.dll`
      (hint); `FirebirdBackupStrategy` + factory +
      `FirebirdSupportedBackupTypesRule`; **`-SE`** em Full Single + verify
      (`gbak`) e em **Full / Diferencial / Log** (`nbackup`) via
      `_firebirdServiceManagerSwitch`, §1.6.7; cascata auth §1.6
      (`_runFirebirdCliWithOptionalLegacyRetry`)
- [x] `ToolVerificationService.verifyFirebirdCliTools` (**gbak**, **nbackup**,
      **gstat**, **isql** via `-?`), `FirebirdConfigProvider.verifyToolsOrThrow`, registo
      em `sgbd_registration.dart` + `BackupOrchestratorService` /
      `application_module.dart`
- [x] Teste DI (stack default + Firebird):
      `test/unit/core/di/sgbd_registration_test.dart` — após
      `registerBackupDatabaseDefaultSgbds`, resolve `IFirebirdConfigRepository` /
      `IFirebirdBackupService` / `FirebirdConfigProvider` com implementações
      concretas (junto com SQL Server, Sybase, PostgreSQL)
- [x] UI: pasta `presentation/widgets/firebird/` (barrel), `FirebirdConfigDialog`
      (`DatabaseConfigDialogShell`, teste de conexão + hint via
      `probeGstatHeaderConnection`), `FirebirdConfigGrid`,
      seção Firebird em `database_config_page.dart`
- [x] `schedule_dialog`: picker Firebird com **Full**, **Full Single**,
      **Diferencial**, **Log** (`nbackup -B 0` / `-B 1`; histórico pode gravar
      Log como Diferencial); `convertedFullSingle` rejeitado na regra
      `FirebirdSupportedBackupTypesRule`; `_normalizeBackupTypeForDatabase`
      força **Full** ao mudar SGBD quando o agendamento trazia tipos incompatíveis;
      `ScheduleDialogLabels` por tipo (gbak vs nbackup).
- [x] `ProcessService`: busca de `bin` no Windows + sanitização de log
      (`-pas`/`-password`; env `FIREBIRD_PASSWORD`, `ISC_PASSWORD`)
- [x] `FirebirdBackupService._failureFromProcess`: mensagens com remediação
      para **WireCrypt** (`incompatible wire encryption` e variação
      `encryption requirements between client`) e plugin/protocolo
      (`your user name and password are not defined` / **AuthServer**), antes
      do fallback genérico de senha

**Entregas incrementais após o núcleo MVP** (registo histórico; itens abaixo
já estão `[x]` no repo; não bloqueavam o critério de MVP):

- [x] Verify pós-backup **Full Single (gbak)**: `gbak -c` para `.fdb`
      temporário (diretório temporário do SO), `verifyDuration` + `flags.verifyPolicy`
      nas métricas; **strict** falha o fluxo se `-c` falhar; **nbackup** com
      verify **strict** rejeitado antes do backup; **nbackup** com verify não
      strict apenas aviso (`firebird_backup_service.dart`;
      `firebird_backup_strategy_factory` passa `verifyPolicy` / `enableChecksum`;
      testes em `firebird_backup_service_test.dart`; texto UI
      `schedule_dialog_compression_verify_section.dart`)
- [x] `nbackup` incremental (`-B 1`) para tipos **Diferencial** / **Log** (e
      `convertedDifferential` / `convertedLog`): avisos operacionais em
      `LoggerService.warning` na execução; `BackupExecutionResult.executedBackupType`
      mapeia **Log** → **Diferencial** no histórico; ficheiro `*_nbackup_B1_*.nbk`;
      regra `FirebirdSupportedBackupTypesRule` + `firebird_backup_service.dart`;
      testes em `firebird_backup_service_test.dart`, `firebird_backup_strategy_test.dart`,
      `backup_strategy_factories_test.dart`; rótulos em `schedule_dialog_labels.dart`.
- [x] Métricas Firebird em `BackupMetrics.flags`: `tool: gbak` ou
      `tool: nbackup` e `firebirdVersion` a partir de
      `FirebirdConfig.serverVersionHint` após backup bem-sucedido; com
      `serverVersionHint == auto`, probe opcional `gbak -z` (cache em memória
      por instalação) enriquece métricas para `auto|WI-V…` quando o token é
      parseável (`firebird_backup_service.dart`; `enableGbakZRuntimeProbe` /
      `resetGbakZProbeCacheForTest`; serialização em `backup_metrics.dart`).
      **Full** = `nbackup -B 0` + `.nbk`; **Full Single** = `gbak` + `.fbk`.
- [x] Scripts pós-backup (`BackupScriptOrchestratorImpl` +
      `SqlScriptExecutionService` + `isql`, 2026-05-16). `isql` incluído em
      `ToolVerificationService.verifyFirebirdCliTools` (2026-05-16); teste de
      orquestrador pós-backup Firebird em
      `backup_script_orchestrator_impl_test.dart` (2026-05-18)
- [x] Cascata **§1.6 (execução)**: `FirebirdBackupService`
      `_runFirebirdCliWithOptionalLegacyRetry` — em `gbak`, `nbackup`, `gstat` e
      `isql` (MON$), após falha com `your user name and password are not defined`
      e `serverVersionHint != v25`, segunda tentativa com `-PROVIDER Engine12` +
      `LoggerService.warning` (AuthServer); **v25** não repete. `gbak -c` (verify)
      partilha o mesmo helper. Testes em `firebird_backup_service_test.dart`.
- [x] **`-SE service_mgr` (`gbak` + `nbackup`)**: `_firebirdServiceManagerPair` /
      `_firebirdServiceManagerSwitch` em `firebird_backup_service.dart` (§1.6
      ponto 7); regressão em `firebird_backup_service_test.dart` (ex.: **gbak**
      Full Single hint v30 + `auto` → `-SE`; **gbak** `never` + v40 → sem `-SE`;
      **nbackup** Full hint v30 + `auto` → `-SE` antes de `-B`; **nbackup**
      `never` + v40 → sem `-SE`).

**Fora do escopo actual do código** (mesmo inventário que **E4** / tabela §1.4;
**E4** = subsecção na secção documental **§3**, *PR-E*):
exposição de `nbackup` **-B 2..9** (UI / tipos), cadeia por **GUID** FB4,
restauro dedicado para artefactos **nbackup** (sem verify pós-backup além do
decidido em **§10**); resolução fina de versão.

**Prioridade sugerida (pós-MVP, sem prazo):** (1) **cadeia nbackup** —
validação no destino por convenção de nomes (`*_full_*.nbk` e, para `-B N` com
`N>1`, também `*_nbackup_B1_*` … `*_nbackup_B(N-1)_*` antes de executar
`nbackup`; ver `missingFirebirdNbackupChainPattern` + §10); (2)
**`-B 2..9` / GUID FB4** — nivel **0–9** opcional no agendamento + execucao
(`firebirdNbackupPhysicalLevel`); **GUID** / parent real pela GUID do motor
permanecem por definir (§6); (3)
**verify pós-`nbackup`** — **fechado (§10):** sem restauro/verify de `.nbk`;
manter **`gbak -c`** só em **Full Single** + aviso na UI (Configurações) +
runtime existente (`FirebirdBackupService`: strict bloqueado; best-effort
ignora o passo em `nbackup`); (4)
**`listDatabases` Firebird** — **fechado (§10):** sem catálogo multi-base; API
`IFirebirdBackupService.listDatabases` + `FirebirdBackupService` consulta
`MON$DATABASE_NAME` via `isql` com fallback para alias/caminho configurado;
`FirebirdConfigDialog` chama após `probeGstatHeaderConnection` (sucesso parcial
com `listWarning` se `isql` falhar). Testes: `firebird_backup_service_test`,
`firebird_config_dialog_test`.

*(Itens de **código** do plano Firebird concluídos; o §8 mantém `- [ ]` só para
QA manual.)*

- [x] Cobertura mínima LSP: `database_connection_config_test.dart` inclui
      `FirebirdConfig`
- [x] Testes unitários dedicados: `firebird_backup_service_test.dart`,
      `firebird_nbackup_output_chain_check_test.dart`,
      `firebird_config_repository_test.dart`, `firebird_config_provider_test.dart`,
      `firebird_config_test.dart`, `firebird_config_enums_test.dart` (parse/wire
      para persistência), `sql_script_execution_service_test.dart` (ramo
      Firebird / `isql`), `firebird_backup_strategy_test.dart` (regra +
      `FirebirdBackupStrategy`; smoke extra em `backup_strategy_factories_test`),
      `get_database_config_test.dart` (use case → `IFirebirdConfigRepository`),
      `backup_script_orchestrator_impl_test.dart` (pós-backup → repo Firebird +
      `executeScript`)
- [x] **PR-G** (código): `supportsFirebird`, serialização/goldens, UI condicional,
      `ScheduleCrudMessageHandler` + integridade SQLite; execução remota reutiliza
      `ExecuteScheduledBackup` → `BackupOrchestratorService` → `GetDatabaseConfig`
      (ramo `DatabaseType.firebird` → `IFirebirdConfigRepository`). Widget test
      `database_config_page_client_firebird_visibility_test.dart` cobre cliente
      “ligado” sem Firebird e com Firebird na UI (`FakeConnectedLegacyRemoteConnectionManager`
      / `FakeConnectedFirebirdCapableRemoteConnectionManager`; **não** usar
      `pumpAndSettle` após montar a página — `ProgressRing` no loading e animações
      Fluent impedem idle; usar `pump` + avanço de relógio). `schedule_dialog_firebird_test`
      cobre o mesmo gate no dropdown do diálogo de agendamento. Socket:
      `schedule_message_handler_test` cobre Firebird permitido (default
      `supportsFirebird`) vs rejeitado em `executeSchedule`; idem
      `execution_message_handler_test` para `startBackup`, `queueIfBusy` e
      dreno da fila (`sendToClientResolver`). `scheduler_service_test` cobre
      `executeNow` local a encaminhar `Schedule` Firebird ao orquestrador.
      **Só fora do CI / automação:** smokes manuais §8 (socket real / backup
      remoto / matriz FB).
- [x] **PR-F** (código): U2/U3/U6/U7 (F5.1–F5.8), `schedule_dialog_firebird_test`
      (incl. grupo *remote client Firebird gate* no dropdown de tipo de BD),
      `firebird_config_dialog_test`, `database_config_page_empty_sections_test`,
      `schedule_dialog_settings_regression_test`. **Opcional**: goldens full-frame
      do `schedule_dialog`.

> **Nota**: as secções **§3 a §6** abaixo conservam o **roteiro original** da
> entrega (subsecções **Checklist (PR-E/F/G)** e restantes itens em `[x]`).
> **§3.0** é a fonte viva para o
> critério MVP, *Já entregue*, *Fora do escopo actual*, *Sincronização recente*
> e **§8.2** (fecho no repositório sem QA manual); evite reabrir itens históricos sem rever o repositório.
> A rubrica em negrito **`Meta (PR-E)`**, **`Meta (PR-F)`** ou **`Meta (PR-G)`**
> no início de **§3–§5** é a meta *daquele* PR (histórico); não confundir com
> **`## Objetivo`** no topo do ficheiro (objetivo global do plano + parágrafo
> *Conclusão*).

*Manutenção:* após merges no núcleo Firebird, rever **Sincronização recente**, a
contagem `flutter test` no bullet **PR-E** do §8 **e no `[x]` Verificação automática
do §8.2**, e alinhar **§3.0 (atualizado …)**,
**Revisão documental** e **Status** no topo; se o fecho do plano mudar, actualizar
também **`## Objetivo`** (*Conclusão*) e o **`[x]` Conclusão formal** em **§8.2**.
Trabalho **pós-MVP:** actualizar **§10** (`[x]` e texto), o parágrafo *Prioridade
sugerida* e a subsecção **E4** em **§3** quando o inventário ou a narrativa mudarem.

---

*As rubricas **Meta (PR-E/F/G)**, **Esforço** e **Critério** em **§3–§5**
descrevem o planeamento original (tempo verbal de desenho); o **estado entregue**
está em **§3.0** e no **Status** / **`## Objetivo`** no topo.*

## 3. PR-E — Firebird Domain + Infraestrutura + CLI

**Meta (PR-E):** criar entidade, repository, service, strategy Firebird
usando as abstrações do plano de refatoração; sem UI; fluxo de backup
coberto por **testes unitários** no CI (`firebird_backup_service_test.dart`,
`ProcessService` mock — sem suíte de integração Firebird obrigatória no repo).

**Esforço**: 1,5 dia (50% menor graças ao PR-D do plano de
refatoração). **Critério**: `flutter test` verde, `dart analyze` zero,
backup Firebird gera `.fbk` (gbak) e ficheiros `.nbk` (`nbackup`) válidos
em diretório temporário.

### Checklist (PR-E)

#### E1 — Domain

> **Estado código (2026-05-16)**: itens abaixo entregues; **Checklist (PR-E)**
> mantida como registo. Fonte viva: **§3.0**.

- [x] Adicionar `DatabaseType.firebird` em
      `lib/domain/entities/schedule.dart`
- [x] Criar `lib/domain/entities/firebird_config.dart` estendendo
      `DatabaseConnectionConfig` com `databaseFile`, `aliasName`,
      `useEmbedded`, `clientLibraryPath`, `serverVersionHint`,
      `serviceManagerMode`, `cryptKey`, overrides `host` / `backupTarget` /
      `databaseType`
- [x] **Rascunho `firebird_server_version.dart` não aplicado** — hints e
      wire para Drift em `lib/domain/value_objects/firebird_config_enums.dart`;
      parsing pesado de saída `gbak -z` / `gstat -h` fica no serviço (§1.6)
- [x] Criar `lib/domain/repositories/i_firebird_config_repository.dart`
      (marker `implements IDatabaseConfigRepository<FirebirdConfig>`)
- [x] Atualizar `lib/domain/repositories/repositories.dart`: export
- [x] Criar `lib/domain/services/i_firebird_backup_service.dart` como marker
      `implements IDatabaseBackupPort<FirebirdConfig>`
- [x] Atualizar `lib/domain/services/services.dart`: export
- [x] Atualizar `lib/domain/use_cases/backup/get_database_config.dart` com
      `case DatabaseType.firebird`
- [x] **Teste**: `test/unit/domain/use_cases/backup/get_database_config_test.dart`
      (ramo Firebird + falha propagada; outros SGBDs não consultados no caso
      Firebird)
- [x] **Teste**: `test/unit/domain/entities/firebird_config_test.dart`
      (LSP coberto também em `database_connection_config_test`; este ficheiro
      cobre alias/stem/sanitização/igualdade — ver §3.0)
- [x] **Teste**: `test/unit/domain/value_objects/firebird_config_enums_test.dart`
      (parse + `wireValue` para Drift; detecção fina `gbak -z` / `gstat -h` na
      §1.6 é responsabilidade do serviço, não deste VO)

#### E2 — Infrastructure data

> **Estado (2026-05-16)**: entregue. `schemaVersion` actual **32** (o
> rascunho falava 29→30). Ver §3.0.

- [x] `lib/infrastructure/datasources/local/tables/firebird_configs_table.dart`
      — inclui `serviceManagerMode` (não `useServiceManager` do rascunho),
      `cryptKey` em coluna texto; senha de login só em secure storage (coluna
      password vazia no companion)
- [x] Export em `tables.dart` / `daos.dart`; `FirebirdConfigDao`; `database.dart`
      (tabela + DAO + migration defensiva `_ensureFirebirdConfigsTableExists`)
- [x] `dart run build_runner build` (artefactos Drift)
- [x] **Teste regressão SQLite em ficheiro**:
      `test/unit/infrastructure/datasources/local/database_migration_v32_test.dart`
      (reopen com `user_version=31` + tabela ausente via `AppDatabase` → migra
      para **32**). Fixture binária legada “só v29” **não** incluída (fora de
      escopo).

#### E3 — Repository (trivial graças ao PR-D)

> **Estado**: `FirebirdConfigRepository` via `BaseDatabaseConfigRepository`;
> `SecureCredentialKeys.firebirdPasswordKey` apenas para **password** (o
> rascunho E3 com `cryptKey` em secure storage não foi adoptado).

- [x] `lib/infrastructure/repositories/firebird_config_repository.dart`
- [x] **Teste**:
      `test/unit/infrastructure/repositories/firebird_config_repository_test.dart`
      (ver §3.0)

#### E4 — Backup service (`IFirebirdBackupService` adapter)

> **Estado (2026-05-18)**: **MVP + sizing + nbackup `-B 1` + `-SE` (`gbak` e
> `nbackup`)** — `gbak` Full Single (com `-SE host/port:service_mgr` quando
> `_firebirdServiceManagerSwitch` aplica; verify `gbak -c` idem); `nbackup` Full
> (`-B 0`) e incremental (`-B 1`) para Diferencial/Log com o mesmo `-SE` quando
> a política §1.6.7 aplica;
> `gstat -h` para `testConnection` (socket / prober) e para
> `probeGstatHeaderConnection` (UI do diálogo: **um** `gstat` + hint ODS/WI-V);
> em seguida `listDatabases` (`isql` + `MON$DATABASE_NAME`, fallback alias/caminho);
> `getGstatHeaderVersionHint` reutiliza o mesmo probe interno sem logs de
> “testar conexão” (segunda invocação se chamado isoladamente); `getDatabaseSizeBytes` em cadeia:
> `isql` + `MON$PAGE_SIZE * MON$PAGES` (script temporário), depois
> `gstat -h` (`Page size` × `Data pages`), depois `File.length()` só em
> **embedded** quando `gstat` falha. Conexão `host/port:path` ou alias;
> embedded por path local; `-key` quando `cryptKey`; env `PATH` com
> `clientLibraryPath`. Usa `BackupArtifactUtils`, `BackupSizeCalculator`,
> `ByteFormat`, `ToolPathHelp`. **Trabalho futuro:** `nbackup` níveis **>1** /
> cadeia completa / GUID FB4, verify adicional para **nbackup**, resolução
> fina de versão. **listDatabases** (Firebird): ver **§10** — identificador da
> base ligada (`MON$DATABASE_NAME` via `isql` + fallback), não catálogo
> multi-base.
> **Ordem sugerida:** ver parágrafo *Prioridade sugerida* em **§3.0** (doc ↔
> código).

- [x] `lib/infrastructure/external/process/firebird_backup_service.dart`
- [x] `ProcessService.redactCommandForLogging` (`-pas`/`-password`) e
      `redactEnvForLogging` (`FIREBIRD_PASSWORD`, `ISC_PASSWORD`, …)
- [x] **Teste**:
      `test/unit/infrastructure/external/process/firebird_backup_service_test.dart`
      (mock `ProcessService`; MON / gstat / ficheiro local; regressão **`-SE`**
      §1.6.7 em `gbak` e `nbackup`; não é matriz contra servidores reais FB 2.5/3/4)
- [x] **Trabalho futuro (não duplicar):** mesmo inventário que **§3.0**
      (*Fora do escopo actual do código*) e a subsecção **E4** na secção documental
      **§3** (*PR-E — Domain + Infraestrutura + CLI*) —
      `nbackup` níveis >1 / cadeia completa, verify
      adicional (ex.: **nbackup**); decisões só em **§3.0** e nesta subsecção **E4**.

#### E5 — Strategy (factory)

> **Estado**: não há `firebird_reject_converted_types_rule` nem
> `firebird_log_to_differential_rule`. A fábrica regista
> `FirebirdSupportedBackupTypesRule` (Full, Full Single, Diferencial, Log e
> convertidos Diferencial/Log; **rejeita** `convertedFullSingle`). Stub
> `firebird_backup_strategy_stub.dart` para builds sem port.

- [x] `firebird_backup_strategy_factory.dart` +
      `firebird_backup_strategy.dart`
- [x] `rules/firebird_supported_backup_types_rule.dart`
- [x] **Teste**: `firebird_backup_strategy_test.dart` (regra + strategy;
      ver também `backup_strategy_factories_test.dart`)

#### E6 — Provider (trivial graças ao PR-D)

- [x] `lib/application/providers/firebird_config_provider.dart` (verificação
      de ferramentas via `ToolVerificationService` em fluxos de guarda)
- [x] `lib/application/providers/providers.dart` — export
- [x] **Teste**: `firebird_config_provider_test.dart` (§3.0)

#### E7 — DI registration

> **Estado**: Firebird **não** passa pelo `registerSgbd` genérico (a
> extensão não inclui `strategyBuilder`; strategy é composta no
> `BackupOrchestratorService`). Registo explícito em
> `sgbd_registration.dart`; `FirebirdConfigProvider` na árvore em
> `lib/presentation/app_widget.dart` (não via `presentation_module.dart`).

- [x] `lib/core/di/sgbd_registration.dart` — repo, factory do provider,
      `IFirebirdBackupService`
- [x] `domain_module.dart` — `GetDatabaseConfig` + repo Firebird
- [x] `application_module.dart` — port Firebird no orquestrador
- [x] `infrastructure_module.dart` — wiring que consome repo/port
- [x] **Teste DI (stack SGBD + Firebird)**: `test/unit/core/di/sgbd_registration_test.dart`
      — `registerBackupDatabaseDefaultSgbds` resolve `IFirebirdConfigRepository` /
      `IFirebirdBackupService` / `FirebirdConfigProvider` com implementações
      concretas (junto com SQL Server, Sybase, PostgreSQL). Smoke do módulo
      `setupInfrastructureModule` completo continua fora do repo (integração
      futura ou manual).

#### E8 — Scripts, SQL auxiliar, compressão, schedules

- [x] `backup_script_orchestrator_impl.dart` — `IFirebirdConfigRepository` +
      ramo `DatabaseType.firebird` + `firebirdConfig` em `executeScript`
- [x] `sql_script_execution_service.dart` — Firebird via `isql -q -user …
      -password … -i <temp.sql> <host/port:db>`; ficheiro temporário em
      `%TEMP%` / `systemTemp` com limpeza em `finally`
- [x] `schedule_repository.dart` — Firebird usa entidade `Schedule`
      genérica após ramos SQL Server / Sybase (sem tipo dedicado; OK para
      MVP)
- [x] `backup_cleanup_service_impl.dart` — sem caso especial Firebird
      (apenas Sybase tem guarda específica)
- [x] `backup_compression_orchestrator_impl.dart` — caso especial só
      Sybase full; backup Firebird é ficheiro `.fbk` único → fluxo default
- [x] `BackupOrchestratorService` + `application_module`: injeta
      `IFirebirdConfigRepository` no fluxo de script pós-backup
- [x] **Teste**:
      `test/unit/infrastructure/external/process/sql_script_execution_service_test.dart`
      (Firebird: config nula, embedded inválido, invocação `isql`)
- [x] **Teste**: `test/unit/infrastructure/scripts/backup_script_orchestrator_impl_test.dart`
      (pós-backup: ramo Firebird chama `IFirebirdConfigRepository.getById` e
      `ISqlScriptExecutionService.executeScript` com `firebirdConfig` preenchido)
- [x] **Teste (gate remoto, mock)**: `schedule_message_handler_test.dart` —
      `executeSchedule` com `DatabaseType.firebird` e `supportsFirebird`
      default (`true`) chama `ExecuteScheduledBackup`; com `supportsFirebird:
      false` devolve `unsupportedDatabaseType` sem invocar backup
- [x] **Teste (startBackup remoto, mock)**: `execution_message_handler_test.dart`
      — `startBackup` com agendamento Firebird e `supportsFirebird` default
      devolve 202 e invoca `ExecuteScheduledBackup`; com `supportsFirebird:
      false` devolve erro sem `executeBackup`; ramo `queueIfBusy` rejeita
      enfileiramento Firebird sem suporte; dreno da fila com item já
      enfileirado + `getById` Firebird e servidor sem suporte envia
      `backupFailed` ao cliente da fila via `sendToClientResolver` sem
      `executeBackup` para esse `scheduleId`
- [x] **Teste (scheduler local, mock)**: `scheduler_service_test.dart` —
      `executeNow` com agendamento `DatabaseType.firebird` invoca
      `BackupOrchestratorService.executeBackup` com o mesmo `Schedule`
- [x] **Validação com motor real** (pós-backup, `Schedule` Firebird): **fora
      do gate de CI** do repositório (opcional; requer instância Firebird +
      ficheiros). Cobertura automatizada = unit/widget + mocks em
      `firebird_backup_service_test.dart` e fluxo orquestrado.

---

## 4. PR-F — Firebird UI + UX (U2, U3, U6, U7)

**Meta (PR-F):** UI Firebird usando componentes genéricos do PR-C/D + 4
melhorias de UX que se beneficiam da chegada de Firebird.

**Esforço**: 1,5 dia. **Critério**: utilizador cadastra Firebird, cria
schedule, dispara backup; refator do `schedule_dialog` (U7) mantém
zero regressão em **SQL Server, Sybase e PostgreSQL** (SGBDs anteriores a Firebird).

### Checklist (PR-F)

#### F1 — `database_config_page.dart`

> **Estado (2026-05-16)**: secção Firebird + grelha + metadata + handlers
> estão no código. **U2** (mostrar sempre as 4 secções com CTA quando count=0)
> **feito** (2026-05-15).

- [x] `_FirebirdConfigSection` + `FirebirdConfigGrid`
- [x] Headers com `DatabaseTypeMetadata.of(DatabaseType.firebird)`
- [x] **U2 — placeholder em seção vazia** nas 4 secções (accordion / "+ Adicionar
      …" mesmo com 0 itens)
- [x] Handlers `_showFirebirdConfigDialog`, `_duplicateFirebirdConfig`,
      `_confirmDeleteFirebird`, `_toggleFirebirdEnabled`
- [x] **Teste**: widget das 4 secções + placeholder U2
      (`database_config_page_empty_sections_test.dart`)

#### F2 — `firebird_config_dialog.dart`

> **Estado**: diálogo Fluent funcional com `DatabaseConfigDialogShell`; teste
> de conexão via `IFirebirdBackupService.probeGstatHeaderConnection` (`gstat`
> uma vez + hint na mensagem de sucesso). `testConnection` mantém-se para
> prober remoto / port genérico. O plano
> pedia cache `_resolveServerVersion` na UI — isso **não** existe; sonda
> `gbak -z` para métricas (hint **Auto**) vive no `FirebirdBackupService`.
> Cascata auth / WireCrypt §1.6 na execução (`-PROVIDER Engine12`, ver §3.0).

- [x] `lib/presentation/widgets/firebird/` (`firebird.dart`, dialog, grid)
- [x] `firebird_config_dialog.dart` + `DatabaseConfigDialogShell`
- [x] Doc-comment `/// **Organism**` no `firebird_config_dialog.dart`
      (convenção design system §8.4)
- [x] `AppPalette.databaseFirebird` / `AppColors.databaseFirebird`
- [x] Entrada Firebird em `DatabaseTypeMetadata`
- [x] Secção básica + avançada (hint versão, `serviceManagerMode`, `cryptKey`,
      embedded, ficheiros, validações principais)
- [x] **Teste**: `test/unit/presentation/widgets/firebird/firebird_config_dialog_test.dart`
      (smoke EN: título novo/editar + campos principais; **Test connection** +
      `probeGstatHeaderConnection` stub → InfoBar com `Detected version`;
      falha → `MessageModal`; `gstat: command not found` → texto `ToolPathHelp`)

#### F3 — U6 Diálogo de duplicar permite editar nome

- [x] Adicionar `MessageModal.showInputConfirm` (ContentDialog + `TextBox`,
      confirmação desativada com nome vazio)
- [x] Substituir fluxo em `database_config_page` (`_promptDuplicateConfigurationName`
      + `createConfig(duplicateConfigCopy(...).copyWith(name: …))` para os 4 SGBDs)
- [x] **Teste**: `message_modal_input_confirm_test.dart` (confirmar / cancelar / trim)

#### F4 — U3 Indicador "última conexão testada"

- [x] Adicionar `lastTestedAt` + `lastTestStatus` no
      `DatabaseConfigProviderBase` (não persistir em DB; apenas
      cache em memória do provider) — implementado como
      `DatabaseConnectionTestSnapshot` + `recordConnectionTest` /
      `connectionTestSnapshotFor`; invalidado em `updateConfig` e `deleteConfig`
- [x] Adicionar coluna opcional "Última verificação" no
      `DatabaseConfigDataGrid` com badge verde/vermelho (coluna **Last check** quando `connectionTestSnapshot` é passado)
- [x] **Teste**: unit (`DatabaseConfigProviderBase`, `TestConnectionRunner`) + widget (`DatabaseConfigDataGrid` Last check)

#### F5 — U7 Refatorar `schedule_dialog.dart` em TabView

Esta é a parte mais delicada do PR-F. O `schedule_dialog.dart` (84
KB, 2200 linhas) precisa ganhar o branch Firebird mas adicionar mais
30 `if (_databaseType == X)` em ficheiro já gigante é inviável.

**Progresso**: `ScheduleDialogLabels`; `ScheduleDialogGeneralSection`; `ScheduleDialogSectionTitle`; `ScheduleDialogScheduleSection`; `schedule_dialog_compression_verify_section.dart`; `schedule_dialog_destinations_section.dart`; `schedule_dialog_timeouts_section.dart`; `schedule_dialog_advanced_database_section.dart` (SQL/Sybase performance + factory + `ScheduleDialogFirebirdAdvancedSummarySection`); `schedule_dialog_script_tab.dart` (`ScheduleDialogScriptTab`); `schedule_dialog_settings_tab.dart` (`ScheduleDialogSettingsTab`); `schedule_dialog_settings_regression_test.dart` (regressão separador Configurações por SGBD).

**Plano** (refator preventivo):
- [x] **F5.1** — `ScheduleDialogGeneralSection` (`schedule_dialog_general_section.dart`): nome, tipo de banco, dropdown de config, tipo de backup + descrição (equivalente ao núcleo do antigo topo do separador Geral)
- [x] **F5.2** — `ScheduleDialogScheduleSection` (`schedule_dialog_schedule_section.dart`): frequência (licença intervalo), Sybase log mode / truncar log, textos de ajuda, `_buildScheduleFields` via parâmetro
- [x] **F5.3** — `ScheduleDialogCompressionSchedulingSection` + `ScheduleDialogIntegritySection` (`schedule_dialog_compression_verify_section.dart`): opções compactação/agendamento ativo + verificação integridade (checksum SQL Server, verify, política)
- [x] **F5.4** — `ScheduleDialogDestinationsAndFolderSection` (`schedule_dialog_destinations_section.dart`): lista de destinos (widget injetado) + pasta de backup + descrição
- [x] **F5.5** — `ScheduleDialogTimeoutsSection`; `ScheduleDialogSqlServerAdvancedPerformanceSection` + `ScheduleDialogSybaseAdvancedPerformanceSection` + factory `ScheduleDialogAdvancedDatabaseSection.build` (`schedule_dialog_advanced_database_section.dart`)
- [x] **F5.6** — Firebird no factory: `ScheduleDialogFirebirdAdvancedSummarySection` (resumo read-only da config selecionada: embedded, service manager, hint de versão, chave definida)
- [x] **F5.7** — `ScheduleDialogScriptTab` (`schedule_dialog_script_tab.dart`): separador Script SQL pós-backup (licença + `TextBox` + infobars)
- [x] **F5.8** — `ScheduleDialogSettingsTab` (`schedule_dialog_settings_tab.dart`): coluna do separador Configurações (destinos, compressão, timeouts, integridade, advanced factory)
- [x] **Teste regressão crítico**: `schedule_dialog_settings_regression_test.dart` — widget tests do separador **Configurações** (secções advanced esperadas por SGBD: SQL Server, Sybase, PostgreSQL, Firebird com/sem config). Goldens full-frame do diálogo permanecem opcionais.
- [x] **Teste novo**: `schedule_dialog_firebird_test.dart`
  - tipos de backup oferecidos (sem `convertedXxx`)
  - cópia de descrição Log sem texto PostgreSQL WAL; tooltip verify Firebird

---

## 5. PR-G — Firebird remoto (socket cliente↔servidor) + U10

**Meta (PR-G):** cliente conectado a servidor com `supportsFirebird=true`
opera Firebird remoto.

**Esforço**: 1 dia. **Critério**: cliente moderno em servidor antigo
recebe `unsupportedDatabaseType` e UI esconde Firebird; cliente
moderno em servidor moderno opera Firebird remoto.

> **Pré-requisito**: este PR depende do trabalho descrito em
> [`plano_cliente_recursos_servidor_execucao_remota_2026-02-21.md`](./plano_cliente_recursos_servidor_execucao_remota_2026-02-21.md)
> estar com PR-1 (capabilities) já no main. Hoje (2026-04-19) está
> entregue.

### Checklist (PR-G)

#### G1 — Protocolo

- [x] `lib/infrastructure/protocol/schedule_serialization.dart`:
      `databaseType` wire inclui `firebird` via `DatabaseType.name` /
      `values.byName` (teste em `schedule_serialization_test.dart`)
- [x] `lib/infrastructure/protocol/capabilities_messages.dart`: campo
      `supportsFirebird` em `ServerCapabilities` (default `false`
      no `legacyDefault`) — já entregue antes deste passo
- [x] `lib/infrastructure/protocol/protocol_versions.dart`: bump
      `kCurrentProtocolVersion` para `2` (PR-G aditivo Firebird remoto)
- [x] `lib/infrastructure/protocol/error_codes.dart`: novo
      `unsupportedDatabaseType` + mapeamento `400` em `status_codes.dart`

#### G2 — Server-side

- [x] Integridade SQLite (`database.dart`): triggers de
      `schedules_table` aceitam `firebird` + `EXISTS` em
      `firebird_configs_table`; `trg_firebird_configs_restrict_delete`
- [x] `ScheduleCrudMessageHandler`: gate `supportsFirebird` +
      `ErrorCode.unsupportedDatabaseType` (parametro para testes/wiring futuro;
      em `infrastructure_module.dart` o registo usa o default `true`, alinhado
      a `kSocketServerSupportsFirebird` em `CapabilitiesMessageHandler`; testes
      `schedule_crud_message_handler_test` cobrem create Firebird rejeitado vs
      permitido com suporte default)
- [x] `ScheduleMessageHandler` / `ExecutionMessageHandler`: mesmo gate antes de
      `executeSchedule` e `startBackup` (incl. caminho de fila ao drenar item
      Firebird); testes em `schedule_message_handler_test` /
      `execution_message_handler_test`
- [x] Plano citava `schedule_message_handler.dart` — CRUD remoto de
      agendamentos está em `schedule_crud_message_handler.dart` (itens
      G2 acima). **Execução remota** (`ScheduleMessageHandler` /
      `ExecutionMessageHandler` → `ExecuteScheduledBackup`): não há handler
      dedicado ao repositório Firebird; o backup remoto usa a mesma pipeline
      que os outros SGBDs, carregando `FirebirdConfig` via `GetDatabaseConfig`
      (`lib/domain/use_cases/backup/get_database_config.dart`).

#### G3 — Capabilities flag e UI

- [x] `ConnectionManager.isFirebirdSupported` (passa-through)
- [x] `ServerConnectionProvider.isFirebirdSupported` (passa-through)
- [x] `database_config_page` esconde botão/seção Firebird quando
      conectado em modo remoto e `!isFirebirdSupported`
- [x] `schedule_dialog` filtra opção Firebird quando remoto e flag
      falsa

#### G4 — U10 InfoBar não-bloqueante

- [x] Substituir `MessageModal.showSuccess/showInfo` por
      `FluentInfoBarFeedback` (`displayInfoBar` / `InfoBar`) nos fluxos
      de **configuração de base** (`database_config_page` + diálogos
      SQL Server, Sybase, PostgreSQL, Firebird): save, duplicar,
      exclusão com sucesso, teste de conexão OK / info lista de bases;
      avisos de lista (`showWarning`) também em InfoBar; **agendamentos**
      locais (`schedules_page`) e remotos (`remote_schedules_page`) para
      sucesso de CRUD / execução / destinos; **destinos** (`destinations_page`,
      `destination_dialog`);       **logs** (`logs_page` export/limpeza); **cliente**
      (`connection_dialog` teste de conexão); **servidor** (`server_login_page`,
      `server_settings_page`, `server_credential_dialog`); **notificações**
      (`notifications_page`, `notification_config_dialog`); **definições**
      (`general_settings_tab`, `service_settings_tab`, `license_settings_tab`,
      `machine_storage_settings_section`); **páginas legadas** SQL Server/Sybase;
      **schedule_dialog** (avisos de licença/validação); **integrity**
      (`integrity_error_modal_helper` inconclusivo → InfoBar warning)
- [x] Manter `MessageModal.showError` (e confirm/input) para erros e
      fluxos que exigem modal
- [x] **Verificação**: não existe suíte E2E neste repositório; cobertura
      atual = widget/unit + `grep` (sem `MessageModal.showSuccess/showInfo/showWarning`
      em `lib/presentation`)
- [x] **Teste (E2E / changelog):** condição **quando** existir suíte E2E no
      repositório — atualizar seletores (modal vs InfoBar) e registar U10 no
      changelog da release. Hoje não há E2E; item é lembrete de infra, não
      pendência do MVP Firebird.

#### G5 — Golden tests

- [x] Criar `test/golden/protocol/fixtures/capabilities_response_with_firebird.golden.json`
- [x] Criar `test/golden/protocol/fixtures/schedule_message_firebird.golden.json`
      (`createSchedule` + `databaseType: firebird` / `backupType: fullSingle`;
      teste em `envelope_golden_test.dart`)
- [x] Atualizar fixture existente `capabilities_response_v1.golden.json`
      para refletir novo campo `supportsFirebird=false` no envelope
      legacy default

---

## 6. Riscos específicos de Firebird

| Risco | PR | Mitigação |
|---|---|---|
| `gbak` não tem verify nativo; utilizadores esperam o mesmo nível de garantia que SQL Server `CHECKSUM`/Postgres `pg_verifybackup` | E + F | Tooltip claro no schedule_dialog: "Firebird não suporta verify nativo. Use 'Strict' apenas se tiver espaço extra para restore temporário". Salvar `verifyMode=skipped\|restoreToTemp` em `BackupMetrics.flags` |
| Confusão `gbak` vs `nbackup` (artefatos com semânticas diferentes) | F | Tooltip por tipo no schedule_dialog explicando ferramenta usada; salvar `tool=gbak\|nbackup` + `firebirdVersion=v25\|v30\|v40` em `BackupMetrics.flags` para auditoria |
| FB 2.5 com Legacy_Auth pode falhar em servidores configurados só para SRP | E | Detectar mensagem `Your user name and password are not defined` e propagar erro com remediação (`AuthServer = Legacy_Auth, Srp` em `firebird.conf`) |
| FB 4.0 com `WireCrypt = Required` rejeita clientes 2.5/3.0 antigos sem WireCrypt | E | Detectar `Incompatible wire encryption requirements` e falhar fast com remediação (`WireCrypt = Enabled` no servidor ou atualizar binários) |
| Detecção automática de versão (`gbak -z`/`gstat -h`) pode falhar em ambientes restritos | E | Respeitar hints **v25/v30/v40** na UI; com **Auto**, falha da sonda não aborta o backup — métricas podem ficar `auto` sem token parseável; `-SE` em modo **auto** só com hints **v30/v40** (§1.6.7), não com **Auto** sozinho |
| Cache de versão pode ficar stale após upgrade do servidor | E + F | Cache em memória (perde no restart); botão "Testar conexão" no dialog força re-detecção; documentar que mudança de versão exige restart ou save da config |
| `cryptKey` salvo na storage segura mas utilizador muda `serverVersionHint` para `v25` (que ignora) | E + F | Service loga warning único por execução; UI mostra warning não-bloqueante no dialog |
| Backup nbackup com nível incremental sem o nível anterior gera erro críptico | E | **MVP:** avisos em log (`_warnFirebirdNbackupOperationalSemantics` em `firebird_backup_service.dart`); sem validação prévia da cadeia nem fallback automático para `-B 0` — o erro vem do `nbackup`. **Backlog:** validar cadeia (p.ex. `.nbk` de nível 0 no destino) e opcional fallback / `executedBackupType` alinhado a Postgres incremental. |
| `nbackup` em FB 4.0 com GUID-based incompatível com cadeia FB 3.0 antiga | E | Cache de versão impede misturar; ao detectar mudança de versão entre execuções na mesma cadeia, forçar fallback para `BackupType.full` (level 0) com log explicativo |
| Embedded em FB 3.0+ exige plugins (`engine12.dll`/`engine13.dll`) na pasta — utilizador aponta `clientLibraryPath` mas esquece plugins | E | `_validateEmbeddedEnginePlugins` em `firebird_backup_service.dart` (antes de `gstat`/`gbak`); falha com mensagem clara |
| Tamanho do banco indisponível (`MON$DATABASE` sem permissão, ficheiro remoto/UNC inacessível) | E | Cair em fallback `gstat -h` → `BackupConstants.minFreeSpaceForBackupBytes` com warning |
| Refator U7 (TabView no schedule_dialog) muda fluxo de UX a que os utilizadores estão habituados | F | Comunicar mudança no changelog; preferir fluxo conservador com tabs em ordem alinhada à dos campos atuais |
| Migration Drift v29→v30 em base existente pode falhar em ambientes com SQLite corrompido | E | `try { ... ensureTableExists } catch` defensivo igual `_ensureSybaseConfigsTableExists` |
| Capabilities flag `supportsFirebird=false` em clientes antigos quebra UI | G | `ServerConnectionProvider.isFirebirdSupported` cai em `legacyDefault=false`; UI consulta antes de exibir |
| Mudança `MessageModal` → `InfoBar` (U10) muda comportamento esperado em testes E2E | G | Atualizar testes E2E; documentar no changelog |

---

## 7. Fora de escopo

- Restore automatizado de backups Firebird (apenas backup é o foco
  do app)
- Backup de bancos Firebird em modo Embedded multi-ficheiro
  (`secondary files`) — usaremos sempre `databaseFile` único; bancos
  com secondaries vão falhar com mensagem clara
- Replicação Firebird 4.0 nativa (não há equivalente ao
  `is_replication_environment` do Sybase; pode entrar em PR futuro)
- Streaming WAL-like (não existe em Firebird; `nbackup` incremental
  é o substituto já coberto)
- Integração com `RDB$BACKUP_HISTORY` para reconstruir histórico de
  backups feitos fora do app (escopo de "import legado", futuro)
- `ALTER DATABASE BEGIN/END BACKUP` exposto directamente ao utilizador
  (usado internamente pelo nbackup; sem motivo para expor)

---

## 8. Checklist de Pré-Entrega Firebird

Itens com `- [ ]` **neste §8** restringem-se a **QA manual** ou **opcionais
documentados** (goldens pixel). Use **§8.1** como roteiro para marcar cada
checkbox após execução local. **Fechar o plano no repositório** (= critério
**§3.0**) não depende destes checkboxes (**§8.2**); servem para evidência
pós-merge / ambiente real. O **código ainda por fazer** (pós-MVP) está inventariado no
**§3.0** (parágrafo *Fora do escopo actual do código*) e na subsecção **E4** da
secção documental **§3** (*PR-E — Domain + Infraestrutura + CLI*; p.ex.
`nbackup` >1, etc.).

### PR-E
- [x] `dart analyze` / `flutter analyze` zero issues (`dart analyze` sem
      findings; reverificado com a toolchain actual)
- [x] `flutter test` todas suítes verde (**1454** pass, **11** `skip`,
      2026-05-18 — mesmo números registados em **§8.2**); suíte completa +
      `dart analyze` reverificados após cascata §1.6 e `-SE` em `gbak` /
      `nbackup`
- [x] `dart run build_runner build` executado (2026-05-18; concluiu sem erros;
      ~1657 outputs)
- [x] Artefactos Drift `*.g.dart` **coerentes com o schema** (ex.: managers em
      ~19 `*_dao.g.dart`). **Antes do merge do PR:** `git add
      lib/infrastructure/datasources/daos/*.g.dart` para não integrar só código
      Dart sem os gerados alinhados.
- [x] Migração **v32** (`firebird_configs_table`) testada em ficheiro SQLite
      real: `database_migration_v32_test.dart` (bootstrap v32 → `DROP` +
      `PRAGMA user_version=31` via `AppDatabase` → reabrir; `user_version=32`
      e colunas esperadas). *Fixture binário legado v29-only: não incluído.*
- [x] `gbak -z`, `nbackup -?`, `gstat -z`, `isql -z` documentados no
      **README** (secção *Requisitos do Sistema* → Firebird opcional)
- [x] `ToolPathHelp` reconhece família Firebird (`gbak`/`nbackup`/`gstat`/`isql`
      em `_firebirdTools`; mensagem Firebird em `buildMessage`; coberto em
      `firebird_config_dialog_test` para `gstat` not found)
- [x] `ProcessService` redact estendido para `-password`/`-pas` e
      `FIREBIRD_PASSWORD` / `ISC_PASSWORD` (env)
- [x] Logs de execução incluem `tool=gbak` ou `tool=nbackup` +
      `firebirdVersion` (hint `auto`\|`v25`\|`v30`\|`v40`) em `BackupMetrics.flags`
      para Firebird MVP
- [ ] Smoke manual ponta-a-ponta executado nas três versões (ver **§8.1**):
  - [ ] Firebird 2.5 com Legacy_Auth, sem WireCrypt, gbak full +
        nbackup nível 0 e incremental **-B 1** (MVP)
  - [ ] Firebird 3.0 com SRP, WireCrypt opcional, **Full Single** e **`nbackup`**
        (Full / Diferencial / Log): confirmar **-SE** + `host/port:service_mgr`
        na CLI quando §1.6.7 + servidor; nbackup **-B 0/-B 1** (MVP)
  - [ ] Firebird 4.0 com SRP256, WireCrypt=Enabled, gbak com
        `-KEYNAME`/chave (opcional, se tiver base criptografada), nbackup
        **-B 0/-B 1**; **níveis >1 / GUID** = fora do escopo §3.0 (não exigido neste smoke)
- [x] Embedded — validação de plugins no Windows coberta em testes:
      `engine12.dll` (hint 3.0) e `engine13.dll` (hint 4.0) em
      `firebird_backup_service_test.dart`. Smoke **real** com motor FB 3/4
      continua manual.
- [x] `gbak -z` em runtime (hint **Auto**): uma sonda antes de `gbak -b` /
      `nbackup`, resultado em cache por chave de instalação (processo);
      `BackupMetrics.flags.firebirdVersion` pode ficar `auto|WI-V…` quando o
      parse tem sucesso; testes em `firebird_backup_service_test.dart` (probe,
      cache, ordem com nbackup). Falhas da sonda não abortam o backup.
- [x] `getDatabaseSizeBytes`: ramos MON$DATABASE + `gstat -h` + ficheiro local
      (embedded) cobertos em `firebird_backup_service_test.dart` — **gate de
      CI**. Matriz opcional contra instâncias reais FB 2.5 / 3 / 4 = smoke
      manual (mesmo espírito do bloco abaixo).

### PR-F
- [x] Refactor F5 (TabView `schedule_dialog`): regressão **funcional** verde
      no CI — `schedule_dialog_sybase_test`, `schedule_dialog_firebird_test`,
      `schedule_dialog_labels_test`, `schedule_dialog_settings_regression_test`
      (SQL Server / Sybase / PostgreSQL / Firebird no separador Configurações);
      `flutter test test/unit/presentation/widgets/schedules/` (18 testes)
- [x] Goldens **pixel** full-frame do `schedule_dialog`: **fora do escopo
      planeado** — opcional; o repo mantém goldens de protocolo + átomos de
      design system, sem `matchesGoldenFile` para este diálogo (decisão
      mantida; não bloqueia MVP).
- [x] `database_config_page` com 4 seções renderizando em
      Light/Dark (`database_config_page_empty_sections_test.dart`: tema
      Fluent `AppTheme` light/dark + quatro CTAs)
- [x] Botão "Testar conexão" no `firebird_config_dialog` exibe
      versão detectada e mensagem amigável de erro (widget tests:
      sucesso + `ValidationFailure` + `gstat` not found → `ToolPathHelp`)
- [x] U2/U3/U6: UI e testes automatizados entregues (`schedule_dialog_*`,
      `firebird_config_dialog_test`, `database_config_page_*`). Capturas /
      screenshots no corpo do PR: **opcional** (documentação de release, não
      critério de merge).

### PR-G
- [x] Goldens de envelope (`envelope_golden_test.dart` + fixtures em
      `test/golden/protocol/fixtures/`, incl. `capabilities_response_*`
      e `schedule_message_firebird`)
- [x] Cliente conectado a servidor **sem** `supportsFirebird`: secção Firebird
      omitida na `database_config_page` — widget test
      `database_config_page_client_firebird_visibility_test.dart`
      (`FakeConnectedLegacyRemoteConnectionManager`; `pump` acumulado, não
      `pumpAndSettle`, por causa do `ProgressRing` / animações Fluent)
- [x] Cliente conectado a servidor **com** `supportsFirebird`: secção Firebird
      visível (scroll até CTA) — mesmo ficheiro
      (`FakeConnectedFirebirdCapableRemoteConnectionManager`)
- [x] Mesmo gate no **ScheduleDialog** (dropdown tipo de BD na aba Geral):
      grupo *remote client Firebird gate* em `schedule_dialog_firebird_test.dart`
- [ ] Smoke manual cliente + servidor antigo (validação visual / socket real;
      ver **§8.1** PR-G)
- [ ] Smoke manual cliente + servidor com Firebird remoto (backup executado
      fora do CI; ver **§8.1** PR-G)
- [x] Documentar em `protocol_versions.dart` o bump de
      `kCurrentProtocolVersion` (comentário em `kCurrentProtocolVersion`,
      versão `2` / PR-G Firebird remoto)
- [x] U10 entregue (InfoBar não-bloqueante para **sucesso**/info/aviso
      leve em toda a camada `lib/presentation` relevante; erros e
      confirmações/input seguem `MessageModal`)

### 8.1 Procedimento de smoke manual (referência)

**Propósito deste §8.1:** obter **evidência operacional** (máquina ou VM com Firebird real) e
marcar os `- [ ]` do §8. Isto **não** faz parte do critério **§3.0** de MVP no
repositório (já satisfeito por código + CI). O CI cobre mocks e fluxos sem motor.

Checklist consolidada: `docs/notes/smoke_firebird_operacional.md`. Sub-listas do §8
abaixo mantêm o detalhe por versão; para Mica/accent Windows ver
`docs/notes/smoke_windows_mica_m14.md` (plano de refatoração M14).
Quem só precisa de **declarar o MVP fechado no repositório** (sem matriz §8.1)
deve seguir **§8.2**.

**Pré-requisitos comuns**

- Build da app (`flutter run -d windows` ou instalador interno).
- Binários `gbak`, `nbackup`, `gstat`, `isql` acessíveis (PATH ou
  **Client library path** no dialog Firebird).
- Pasta de saída de backup com espaço e permissão de escrita.

**Pré-flight automático (recomendado no mesmo dia do smoke)**

Na raiz do repositório, com toolchain Flutter/Dart alinhada ao CI:

```text
dart analyze
flutter test
```

Falhas aqui devem corrigir-se **antes** da matriz manual (evita perder tempo
com binários ou regressões já detectáveis por teste).

**Pacote `schedule_dialog` (regressão UI, CI)** — mesmo dia do smoke:

```text
flutter test test/unit/presentation/widgets/schedules/
```

(18 testes na pasta; alinhado ao bullet PR-F do §8.)

**Matriz por versão (marque os sub-itens do §8 PR-E após cada coluna)**

1. **Firebird 2.5** (Legacy_Auth, sem WireCrypt): cadastrar config (host,
   porta, caminho ou alias), **Testar conexão** (gstat). Agendamentos: **Full**
   (`.nbk`, `nbackup -B 0`), **Full Single** (`.fbk`); opcional **Diferencial** /
   **Log** (`nbackup -B 1` após nível 0). Com **hint v25** (§1.6.7), a app **não**
   acrescenta `-SE` a `gbak` nem a `nbackup`. Confirmar ficheiros e histórico/logs.
2. **Firebird 3.0** (SRP, WireCrypt opcional): idem; na linha de comando, a app
   acrescenta **`-SE host/port:service_mgr`** em **Full Single (`gbak`)** e em
   **`nbackup`** (Full / Diferencial / Log) quando `serviceManagerMode` +
   `serverVersionHint` cumprem §1.6.7 (confirmar nos logs / histórico com motor
   real); se existir conta/plugin legado,
   observar **segunda tentativa** `-PROVIDER Engine12` nos logs após “user name
   and password are not defined” (§1.6).
3. **Firebird 4.0** (SRP256, WireCrypt *Enabled* vs *Required*): Full Single com
   chave se aplicável; **Full** físico; **Log**/Diferencial = `nbackup -B 1`
   (MVP; **níveis >1 / GUID** fora do escopo deste smoke). Validar **`-SE`** em
   `gbak` e `nbackup` quando §1.6.7 + política o permitirem. Cliente antigo:
   validar mensagem WireCrypt e remediação na UI.

**Smoke cliente + servidor (§8 PR-G)**

- **Servidor “antigo”** (`supportsFirebird` ausente ou falso): cliente não
  deve oferecer Firebird em config remota / dropdown de agendamento; sem crash.
- **Servidor com Firebird**: capabilities com Firebird; criar/editar agendamento
  remoto Firebird; **Executar agora** ou fila; confirmar backup no destino e
  resposta de socket (sem regressão de protocolo).

**Evidência sugerida**: nota curta na issue/PR (versão FB, SO, passos) ou
anexo de log redigido (`ProcessService` já mascara `-pas` / env).

**Mapeamento → checkboxes do §8**

- Marque **PR-E** “Smoke manual… três versões” e os três sub-itens (2.5 / 3.0 /
  4.0) após concluir a **matriz por versão** acima.
- Marque cada **PR-G** “Smoke manual cliente…” após o par correspondente em
  **Smoke cliente + servidor**.
- O critério **§3.0** (MVP no repositório) **não** exige estes checkboxes; são
  evidência opcional de release / ambiente real.

### 8.2 Fecho do plano no repositório (sem smoke manual)

**Critério:** o **MVP Firebird** está **concluído para o repositório** quando o
**§3.0** se verifica (código + `dart analyze` + `flutter test` + `build_runner`
+ `.g.dart` coerentes). **Não** é obrigatório passar os `- [ ]` do **§8** para
esse fecho. **Este documento declara o critério cumprido em 2026-05-18**
(verificação abaixo; secção **`## Objetivo`** — *Conclusão*).

- [x] Verificação automática **2026-05-18**: `dart analyze` sem issues;
      `flutter test` **1454** pass, **11** `skip` — confirma o critério §3.0
      **sem** os smokes manuais §8.1.
- [x] **Conclusão formal do plano (documento, 2026-05-18):** **Status** no
      cabeçalho, secção **`## Objetivo`** (metas + *Conclusão*) e Sumário executivo
      alinhados a **fechado (MVP / repositório)**.

Para **reverificar** localmente esse critério após novos merges (ou antes de
actualizar contagens no §3.0 / §8), use o bloco **Pré-flight automático** do
**§8.1** (`dart analyze`, `flutter test`). Se as contagens de testes mudarem,
actualize o **`[x]` Verificação automática** em **§8.2**, o bullet **PR-E** do
§8 e **Sincronização recente** no §3.0. Se alterou schema Drift, execute
também `dart run build_runner build` (bullet PR-E do §8).

Os checkboxes **§8** permanecem `[ ]` até existir **evidência** da matriz **§8.1**
(ambiente com motor Firebird real e, para PR-G, cliente↔servidor). Quem
executar os smokes pode: (a) marcar `[x]` neste ficheiro num commit de release
/ QA; ou (b) anexar a mesma evidência noutro sítio (issue, notas de release) e
deixar o §8 inalterado — ambos são aceitáveis; o **§3.0** não discrimina entre
(a) e (b).

---

## 9. Cross-references

### Fecho (onde procurar)

**Remissão ao topo:** a *Nota de navegação* (logo após a *Leitura rápida*)
esclarece **§3.0** vs capítulo **§3** e a subsecção **E4**; **§10** (fim do
ficheiro) rastreia a continuação pós-MVP.

- **Conclusão MVP no repositório:** **`## Objetivo`** (topo) — *Conclusão*;
  **Status** no cabeçalho; **§3.0** (critério, *Já entregue*, *Sincronização
  recente*); **§8.2** com dois **`[x]`** (verificação automática com contagens
  `dart analyze` / `flutter test` + conclusão formal do documento,
  **2026-05-18**). O fecho **não** exige matriz **§8.1** nem `[x]` no **§8**;
  evidência manual ou externa continua opcional.
- **Roteiro histórico §3–§6:** subsecções **Checklist (PR-E/F/G)** e narrativa
  por PR (**Meta (PR-E/F/G)** em §3–§5); não substituem **§3.0** nem **§8.2**.
- **Código futuro (Firebird):** §3.0 (*Fora do escopo actual do código*) e subsecção
  **E4** na secção documental **§3** (*PR-E — Domain + Infraestrutura + CLI*).
- **Continuação do plano (pós-MVP):** §10 — checklist opcional alinhada a §3.0 e
  subsecção **E4**; marcar `[x]` quando o código existir no repositório.

### Documentação e regras relacionadas

- **Plano de refatoração** (pré-requisito): [`plano_refatoracao_e_melhorias_2026-04-19.md`](./plano_refatoracao_e_melhorias_2026-04-19.md)
- Plano de execução remota cliente↔servidor: [`plano_cliente_recursos_servidor_execucao_remota_2026-02-21.md`](./plano_cliente_recursos_servidor_execucao_remota_2026-02-21.md)
- Auditoria de qualidade prévia: [`auditoria_qualidade_2026-04-18.md`](./auditoria_qualidade_2026-04-18.md)
- Rule de padrões arquiteturais: [`.cursor/rules/architectural_patterns.mdc`](../../.cursor/rules/architectural_patterns.mdc)
- Regras do projecto (camadas, dependências, desktop): [`.cursor/rules/project_specifics.mdc`](../../.cursor/rules/project_specifics.mdc)
- ADR-004 (ports genéricos / SGBDs): [`004-generic-hexagonal-ports-sgbds.md`](../adr/004-generic-hexagonal-ports-sgbds.md)
- Cookbook **novo SGBD** (onboarding): [`adicionar_sgbd.md`](../onboarding/adicionar_sgbd.md)
- Visão de arquitetura (onboarding): [`architecture_overview.md`](../onboarding/architecture_overview.md)
- Design system / UI (onboarding): [`design_system.md`](../onboarding/design_system.md)
- **README** (requisitos de CLI Firebird / sistema): [`README.md`](../../README.md)

---

## 10. Continuação do plano (pós-MVP)

> **Relação com o MVP:** fora do fecho **§8.2**; não altera **§3.0** nem a
> subsecção **E4** em **§3** — esta secção é **rastreio evolutivo** opcional para
> quem retoma o trabalho após o MVP.

**Fonte técnica:** §3.0 (*Fora do escopo actual do código*, *Prioridade sugerida*)
e **E4** na secção documental **§3** (*PR-E*); ver também §6 (riscos).

**Checklist** (marcar `[x]` quando existir implementação + testes no repositório):

- [x] **Cadeia nbackup:** validação no destino (`missingFirebirdNbackupChainPattern`
      — nível 0 + ficheiros `*_nbackup_Bk_*` para `k < N` quando `N>1`; mensagem
      antes de `nbackup`; testes em `firebird_nbackup_output_chain_check_test.dart`
      e `firebird_backup_service_test.dart`). **Não** cobre GUID FB4 nem escolha
      automática do ficheiro-pai (ver item seguinte e §6).
- [x] **`nbackup` -B 2..9 / GUID FB4:** nivel fisico **0–9** opcional
      (`Schedule.firebirdNbackupPhysicalLevel` em `scheduleConfig` JSON;
      `schedule_serialization`; `BackupExecutionContext.firebirdNbackupPhysicalLevel`;
      campo no dialogo de agendamento Firebird; `FirebirdBackupService` +
      `firebird_backup_strategy_factory`; testes em `firebird_backup_service_test`,
      `schedule_serialization_test`, `firebird_backup_strategy_test`). **GUID
      FB4** e escolha automatica do ficheiro-pai pela GUID do motor **nao**
      implementados (continuam §3.0 *Fora do escopo* / §6).
- [x] **Verify pós-`nbackup`:** decisão de produto **sem** restauro/verify de
      `.nbk`; manter **`gbak -c`** apenas em **Full Single** (`.fbk`). UI:
      `ScheduleDialogIntegritySection` — `InfoBar` (aviso) quando Firebird +
      tipo ≠ Full Single, alinhado a `FirebirdBackupService` (strict rejeitado;
      best-effort ignora verify em `nbackup`). Testes:
      `schedule_dialog_firebird_test.dart`.
- [x] **`listDatabases` Firebird:** sem equivalente a `sys.databases`; API
      `listDatabases` em `IFirebirdBackupService` — `MON$DATABASE_NAME` via
      `isql`, fallback alias/caminho; integração no teste de conexão do dialogo
      (`firebird_config_dialog.dart`); testes em `firebird_backup_service_test`,
      `firebird_config_dialog_test`; stub em `firebird_backup_service_stub.dart`.

*Manutenção:* ao fechar um item, actualizar o parágrafo *Prioridade sugerida* e
o texto da subsecção **E4** em **§3** se a narrativa ou o inventário mudarem.
