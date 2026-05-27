# ADR-014: Suposições válidas sobre CLIs Firebird (gbak / nbackup / gstat / isql)

- Status: accepted
- Data: 2026-05-27
- Decisores: time aplicativo (Clean Architecture + desktop Windows)
- Contexto relacionado:
  - `docs/notes/plano_suporte_firebird_2026-04-19.md` §1.6.5, §1.6.7, §1.6.8 (rev. 2026-05-27)
  - `lib/infrastructure/external/process/firebird_backup_service.dart`
  - `lib/core/utils/firebird_embedded_support.dart`

## Contexto

Durante o MVP Firebird (PR-E / PR-F / PR-G entregues em 2026-05-18) três
mecanismos foram implementados com base em interpretação de fórum /
issues GitHub, mas **sem verificação contra a documentação oficial nem
contra binários reais**:

1. **Retry de auth com `-PROVIDER Engine12`** em `gbak`, `nbackup`,
   `gstat` e `isql` quando a stderr contém *"your user name and password
   are not defined"* — implementado em
   `_runFirebirdCliWithOptionalLegacyRetry` + `_argumentsWithInjectedLegacyProvider`.
2. **`-SE host/port:service_mgr`** acrescentado a `nbackup` (Full /
   Diferencial / Log) por analogia ao `gbak` (que **suporta** `-SE` desde
   FB 2.5).
3. **Criptografia** com `gbak -KEYNAME <chave>` (FB4) ou `gbak -key
   <chave>` (FB 2.5/3.0) via `_gbakCryptCliArgs`.

A bateria de testes mockados validava mecanicamente os argumentos
construídos, mas **mocks não exercitam a CLI real**. Auditoria de
2026-05-27 confirmou contra (a) docs oficiais
([nbackup](https://www.firebirdsql.org/file/documentation/html/en/firebirddocs/nbackup/firebird-nbackup.html),
[gstat](https://www.firebirdsql.org/file/documentation/html/en/firebirddocs/gstat/firebird-gstat.html),
[gbak](https://www.firebirdsql.org/file/documentation/html/en/firebirddocs/gbak/firebird-gbak.html),
[isql](https://www.firebirdsql.org/file/documentation/html/en/firebirddocs/isql/firebird-isql.html))
e (b) parser do `nbackup_action_in_sw_table` em
[`nbackup.cpp` no FirebirdSQL/firebird](https://github.com/FirebirdSQL/firebird/blob/master/src/utilities/nbackup/nbackup.cpp)
que **nenhuma das três suposições é válida**:

1. `-PROVIDER` **não existe** como switch CLI em nenhum dos tools
   Firebird. `Engine12` é nome de provider configurado em
   `firebird.conf` (chave `Providers = Remote,Engine12,Loopback`) ou em
   `databases.conf` por base. Tentar passar pela CLI produz erro
   *"invalid switch"* — **pior** que o erro original de auth, pois
   mascara a causa real.
2. `nbackup` **não tem switch `-SE`/`-SERVICE`**. Para nbackup remoto
   via Services Manager o Firebird exige a ferramenta separada
   `fbsvcmgr` com switches próprios (`-action_nbak`, `-nbk_level n`,
   `-dbname`, `-nbk_file`).
3. `gbak` **não tem switch `-key`**; tem apenas `-K(EYHOLDER)` e
   `-K(EYNAME)`. `-KEYNAME` sozinho (FB4) é incompleto — a doc oficial
   estabelece que *"this option must generally be combined with
   `-KEYHOLDER` and `-CRYPT`"*. Encriptação `gbak` real exige o trio.

A pressão original para implementar (1) veio de relatos comuns em
Firebird-support de utilizadores com servidores FB 3+ exigindo SRP que
têm contas legacy. A "solução" correta é configurar `AuthServer =
Legacy_Auth, Srp` em `firebird.conf` **no servidor**, ou usar provider
correto via `firebird.conf` **no cliente** (não via CLI).

## Decisão

1. **Não inventar switches de linha de comando**. Qualquer flag passada
   à CLI Firebird deve estar documentada na página oficial daquela
   ferramenta para aquela versão alvo. Issues de fórum não são
   substituto de doc oficial. Em caso de dúvida, consultar o `switch
   table` no source do FirebirdSQL.
2. **Auth fallback é responsabilidade do utilizador**, não da app.
   Quando a stderr indicar `your user name and password are not
   defined`, devolver mensagem amigável com remediação textual
   (configuração `AuthServer` em `firebird.conf`). Não tentar retry
   automático com flags inventadas. Implementado em
   `_failureFromProcess` no `FirebirdBackupService`.
3. **`-SE` apenas em `gbak`** (`_gbakServiceManagerSwitch`). nbackup
   remoto via Services Manager fica como item de roadmap usando
   `fbsvcmgr`.
4. **`cryptKey` rejeitado upfront** em `executeBackup` com
   `ValidationFailure` clara (`_rejectCryptKeyIfPresent`) até existir
   suporte completo `-CRYPT` + `-KEYHOLDER` + `-KEYNAME` com UI dedicada
   para os três campos. `cryptKey` é mantido em secure storage
   (`SecureCredentialKeys.firebirdCryptKeyKey`) para preservar valor
   entre versões da app.
5. **`Path` env var** para `fbclient.dll` (já implementado) é a forma
   correta de orientar o loader Firebird; manter.

## Consequências

### Positivas

- Comportamento da app alinha com CLI real. Em servidores FB 3.0/4.0
  com Legacy_Auth, o utilizador recebe a mensagem real *"your user name
  and password are not defined"* mapeada para texto com a remediação
  correta (`AuthServer = Legacy_Auth, Srp`), em vez de erro críptico
  *"-PROVIDER is not a valid switch"* do retry quebrado.
- Em FB 2.5 com `serviceManagerMode = always` + `serverVersionHint =
  v25`, app loga warning explicando que `-SE` foi omitido (o utilizador
  marcou Sempre usar, mas a política evita Services Manager).
- `cryptKey` deixa de gerar comando inválido ao backup; rejeitado cedo
  com mensagem clara.
- Suíte de testes mockados agora valida a **ausência** dos switches
  inválidos (regressões reintroduzem os bugs imediatamente).
- `cryptKey` em secure storage elimina texto puro na coluna SQLite —
  mesma proteção que a senha do utilizador.

### Negativas / trade-offs

- Utilizadores que dependiam (por sorte) do erro críptico para diagnosticar
  têm hoje texto diferente nos logs. Documentar mudança no changelog.
- `nbackup` remoto via Services Manager fica indisponível até o
  trabalho de `fbsvcmgr` (estimativa: 200–300 linhas + testes).
- Encriptação `gbak` continua bloqueada até o ticket de UI completa
  (3 campos: `cryptPlugin`, `keyholder`, `keyName`).

### Mitigações para roadmap

- Quando o trabalho de `fbsvcmgr` entrar: criar wrapper dedicado em
  `lib/infrastructure/external/process/firebird_fbsvcmgr_service.dart`,
  registar em `ToolVerificationService.verifyFirebirdCliTools`, e
  expor via flag de política em `FirebirdServiceManagerMode` (ou novo
  enum se o eixo de decisão for diferente).
- Quando o trio `-CRYPT/-KEYHOLDER/-KEYNAME` entrar: adicionar três
  campos no `FirebirdConfigDialog` (todos em secure storage),
  reativar `_gbakCryptCliArgs` para emitir os três juntos quando
  preenchidos, e estender `firebirdGbakUsesKeyNameEncryption` (já
  preservado em `lib/core/utils/firebird_runtime_version.dart`).

## Regra de revisão

Toda mudança que envolva nova flag CLI Firebird deve:

1. Citar página da doc oficial Firebird para a versão alvo.
2. Adicionar teste mockado que valida **presença** da flag esperada **e
   ausência** de flags inventadas.
3. Quando possível, executar smoke § 8.1 do plano contra binário real
   antes do merge.
4. Re-ler este ADR antes de adicionar qualquer `_arguments...Inject...`
   ou `_*Switch` que dependa de "convenção de comunidade".
