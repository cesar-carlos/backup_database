# ADR-016: Audit de licenciamento — secret handling, anti-rollback de CRL e UX de status

- Status: accepted
- Data: 2026-05-28
- Decisores: time backup_database
- Contexto relacionado: auditoria de licenciamento 2026-05-28
  (transcript do chat de auditoria; ver `.cursor/agent-transcripts/`)

## Contexto

A primeira auditoria do fluxo de licenciamento (Ed25519 v2) identificou
14 issues entre crítico e baixo. Os mais graves:

1. **Chave privada Ed25519** e **senha admin** estavam em claro no
   `.env` versionado, que é declarado como Flutter asset
   (`pubspec.yaml: assets: - .env`) — qualquer release shipping para
   cliente expunha os bytes da chave privada e a senha em texto plano.
   Atacante extraía com `unzip flutter_assets/` e emitia licenças
   válidas para qualquer `deviceKey`, com qualquer combinação de
   features. Burlava todo o esquema offline de assinatura.

2. `LicenseValidationService.getCurrentLicense` tratava licença
   expirada/revogada como `Failure`, então a UI só conseguia exibir
   "Sem licença" — usuário com licença válida-mas-expirada não via
   indicação para renovar (código `_buildLicenseStatus` para `isExpired`
   era código morto).

3. `SignedRevocationListService` não tinha proteção contra **rollback**
   de CRL: atacante podia servir uma CRL antiga (válida + assinada,
   `expiresAt` no futuro) sem o `deviceKey` que tinha sido revogado
   depois, "ressuscitando" a licença.

4. `LicensePolicyService._runFeatureCache` era global no singleton e
   zerado a cada `setRunContext` — duas runs concorrentes (UI local +
   socket remoto, ou múltiplos schedules) clobberavam o cache uma da
   outra.

5. `DeviceKeyService.getDeviceKey()` dispara 2-3 `wmic`+registro+volume
   info por chamada (1-3s a frio) e era invocado N vezes em paralelo
   no boot — sem cache.

6. `LicenseRepository.upsertByDeviceKey` fazia read+write sem
   transação — race em callers concorrentes batia em unique constraint.

7. Senha admin do gerador era comparada em **texto plano**
   (`entered == plain`) sem lockout — brute-force interativo possível.

A decisão precisa endereçar os 14 pontos da auditoria mantendo
retrocompatibilidade com licenças já emitidas (Ed25519 v2).

## Decisão

Aplicamos todas as melhorias da auditoria em uma única rodada,
preservando o payload Ed25519 v2 (sem bump de versão de licença):

### Segredos no asset bundled

- `EnvironmentLoader.forbiddenInBundledAssetKeys` lista as chaves que
  são proibidas de ter valor no asset (`BACKUP_DATABASE_LICENSE_PRIVATE_KEY`,
  `LICENSE_ADMIN_PASSWORD_HASH`, `LICENSE_ADMIN_PASSWORD`, `FTP_IT_PASS`).
- `loadIfNeeded` chama `_scrubLeakedSecretsFromCurrentEnv` quando a
  fonte primária é o asset bundled, **apagando** valores indevidos em
  `dotenv.env` e logando `error`.
- `_overlayBundledAsset` (fallback) ignora chaves forbidden mesmo se
  estiverem preenchidas no asset.
- `EnvironmentLoadOutcome.leakedBundledSecretKeys` expõe o incidente
  para o bootstrap registrar.
- Teste de CI (`test/unit/core/config/bundled_env_secret_leak_test.dart`)
  falha se algum valor proibido aparecer em `.env`/`.env.example` do
  repo.

### Política vs leitura para UI

- `ILicenseValidationService.getCurrentLicense()` aplica a política
  completa (rejeita expirada/revogada/ausente) — usado pelo
  `LicensePolicyService` e checagens de feature.
- Novo `ILicenseValidationService.getStoredLicense()` devolve a
  licença persistida bruta — usado pelo `LicenseProvider.loadLicense`
  para que a UI consiga renderizar "Licença expirada em X" / "Ainda
  não em vigor" em vez de cair para "Sem licença".

### Anti-rollback de CRL

- `RevocationListIssuedAtStore` (interface + implementação em arquivo)
  persiste o maior `issuedAt` já aceito.
- `SignedRevocationListService` rejeita CRLs com `issuedAt`
  estritamente menor que o último aceito e loga warning.
- `ensureLastAcceptedIssuedAtLoaded()` hidrata o marcador no boot
  (`core_module.dart`).

### Helper compartilhado de revogação

- `RevocationCheckHelper.isRevokedSafe(checker, deviceKey)` é usado
  tanto por `LicenseValidationService.getCurrentLicense` quanto por
  `LicenseGenerationService.createLicenseFromKey`. Fail-open
  observável (log warning quando null; log error quando lança); antes
  o cadastro usava `?? false` silencioso, divergindo da validação.

### Cache por `runId` em `LicensePolicyService`

- Substituímos `Map<String, bool> _runFeatureCache` global por
  `Map<String, Map<String, bool>> _runFeatureCacheByRunId`.
- `setRunContext(runId)` faz `putIfAbsent` (preserva cache do mesmo
  runId reentrante); `clearRunContext()` só remove o slot do run
  atual. Runs concorrentes ficam isolados.

### `DeviceKeyService.getDeviceKey` memoizado

- Cache via `Future` único — chamadas concorrentes compartilham o
  mesmo trabalho (race-free). Erro **não** é cacheado (permite retry).
- `CachedLicenseValidationService` deixa de chamar `getDeviceKey` em
  cada `getCurrentLicense` — agora o cache é por instância de service
  (1 device por processo).

### `upsertByDeviceKey` em transação

- `LicenseRepository.upsertByDeviceKey` envolve read+write em
  `_database.transaction(...)`, eliminando a janela de race contra a
  unique constraint `(device_key)`.

### `notBefore` persistido

- `LicensesTable.not_before` (schema v36, migração simples adicionando
  coluna nullable).
- `License.notBefore` + `License.isNotYetValid` + `License.isValid`
  agora consideram a janela "not yet valid".
- Antes era validado apenas no decode (descartado depois); reabrir o
  app antes da janela não bloqueava — agora bloqueia.

### `License == ` por `licenseKey`

- Equality determinística por `(licenseKey, deviceKey)`, não por `id`
  (que era `Uuid.v4()` na construção e mudava entre leituras).

### Hash + lockout da senha admin

- `AdminPasswordVerifier` (PBKDF2-SHA256, salt aleatório, constant-time
  compare).
- Formato: `pbkdf2-sha256$<iters>$<salt>$<hash>` em
  `LICENSE_ADMIN_PASSWORD_HASH`.
- Lockout após 3 falhas por 30s (default, configurável).
- `scripts/hash_admin_password.dart` para gerar o hash localmente; o
  hash vive APENAS em `C:\ProgramData\BackupDatabase\config\.env`
  (fora do bundle).

### `validateLicense` removida

- `ILicenseValidationService.validateLicense` não tinha caller em
  produção; ficava como código zumbi divergindo do `createLicenseFromKey`.
  Removida.

## Consequências

### Positivas

- Chave privada não é mais distribuída no bundle. Mesmo que alguém
  re-comite o valor no `.env`, o guard de runtime apaga em memória e
  o teste de CI quebra na PR.
- UX de licenciamento: usuário vê status real ("expirada em X",
  "ativa a partir de Y") e age sobre ele.
- Anti-rollback de CRL impede reuso malicioso de listas antigas.
- Runs concorrentes (UI + socket) ficam corretos e mais rápidos
  (cache não é mais clobberado).
- Boot mais rápido em máquinas com WMI lento (1 invocação em vez de
  3-4).
- Race em cadastros simultâneos de licença não retorna erro espúrio.
- Senha admin não vaza nem permite brute-force.

### Negativas

- Migração v36 do schema (Drift) é mais um passo no upgrade — backup
  do DB antes de release recomendado.
- Operação precisa popular o `.env` externo com o hash da senha admin
  para usar o gerador embutido em dev (one-time, documentado).
- A chave privada atual deve ser considerada **comprometida** (estava
  no git history). Ação operacional: rotacionar + emitir novas
  licenças para clientes ativos.

### Neutras

- Payload da licença v2 não muda; licenças existentes continuam
  válidas após o upgrade.
- `notBefore` é coluna nullable — não há backfill obrigatório.

## Notas de implementação

Documentação detalhada dos helpers em
`.cursor/rules/architectural_patterns.mdc §10`, incluindo:

- §10.1 `forbiddenInBundledAssetKeys` guard;
- §10.2 `getCurrentLicense` vs `getStoredLicense`;
- §10.3 `RevocationCheckHelper.isRevokedSafe`;
- §10.4 `RevocationListIssuedAtStore` (anti-rollback);
- §10.5 `AdminPasswordVerifier` (hash + lockout);
- §10.6 `DeviceKeyService` memoization;
- §10.7 cache por `runId` em `LicensePolicyService`;
- §10.8 transação no `upsertByDeviceKey`;
- §10.9 `License == ` por `licenseKey`;
- §10.10 multi-key verification (rotação graceful);
- §10.11 checklist final (licensing).

Onboarding rápido em `docs/onboarding/licenciamento.md`. Procedimento
de rotação concreto na seção "…rotacionar a chave Ed25519".

### Adendo (mesma rodada, kr): suporte a rotação graceful

A decisão original mantinha o decoder com uma única chave hard-coded
(`LicenseConstants.keyIdDefault`), o que tornava a rotação operacionalmente
impossível sem invalidar todas as licenças já emitidas. Em uma sub-task
da mesma auditoria, o decoder foi refatorado para aceitar um mapa
`publicKeysByKeyId` e o `LicenseGenerationService` ganhou
`activeKeyId` (lido de `BACKUP_DATABASE_LICENSE_ACTIVE_KEY_ID`). O
payload v2 já tinha o campo `keyId` mas nunca era variado — agora é.

- Migração: licenças antigas (`keyId="ed25519-1"`) continuam aceitas
  enquanto a chave antiga estiver no mapa.
- Script: `scripts/generate_license_keypair.dart`.
- Backward-compat: `BACKUP_DATABASE_LICENSE_PUBLIC_KEY` (single)
  continua sendo aceita e mapeada implicitamente para `ed25519-1`.

## Alternativas consideradas

### Opção A: bump para Ed25519 v3 com canonical JSON (RFC 8785)

- Tornaria a assinatura imune a mudanças futuras de ordering do
  `jsonEncode` do Dart.
- Não foi escolhida porque exigia bump de versão + retroincompatibilidade
  com licenças v2 já emitidas, e nenhuma evidência de quebra com o
  SDK atual.

### Opção B: mover gerador admin para um binário separado

- Retiraria 100% do código de geração do bundle cliente, anulando o
  vetor de "release com private key vazada por engano".
- Não foi escolhida nesta rodada porque a defesa em camadas atual
  (private key vazia no asset + guard de runtime + teste de CI +
  hash da senha admin) cobre o caso real. Pode ser feito em uma
  rodada futura se a complexidade do diálogo de geração crescer.

### Opção C: fail-CLOSED no checker de revogação

- Mais seguro contra atacante que sabote o arquivo CRL.
- Não foi escolhida porque indisponibilidade transitória da CRL
  (arquivo em download, permissões temporárias) bloquearia todos os
  backups do cliente — pior UX que o risco residual. Fail-open
  observável é o trade-off documentado.
