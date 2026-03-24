# Plano: Melhoria de Instancia Unica, Auto Start e Convivencia UI + Servico

Data base: 2026-03-24
Status: Planejado
Escopo: Windows desktop, bootstrap de UI, auto start, IPC local e modo servico
Objetivo: aumentar confiabilidade e desempenho do controle de instancia unica, padronizar a deteccao de auto start e garantir que o servico Windows nao conte como instancia de UI

## Objetivos de Negocio

- Tornar a decisao de "segunda instancia" deterministica e previsivel.
- Reduzir o custo de startup da UI quando nao existe outra UI em execucao.
- Nao mostrar popup para o usuario quando a tentativa duplicada vier do auto start do Windows.
- Garantir explicitamente que uma instancia em modo servico nao bloqueie a abertura normal da UI.
- Transformar o comportamento atual em contrato de arquitetura e contrato de testes, nao apenas em efeito colateral da implementacao.

## Resumo Executivo

Hoje a base ja contem os elementos corretos, mas eles estao acoplados de forma fraca:

- a autoridade real de exclusividade esta no mutex global em `lib/infrastructure/external/system/single_instance_service.dart:75`;
- a UI, mesmo depois de adquirir o mutex com sucesso, ainda faz uma segunda verificacao por IPC em `lib/main.dart:80`;
- a deteccao de "startup automatico" existe apenas para o caminho HKCU controlado pelo app em `lib/presentation/providers/system_settings_provider.dart:154`, mas nao para o caminho HKLM criado pelo instalador em `installer/setup.iss:70`;
- o modo servico ja usa mutex separado em `lib/presentation/boot/service_mode_initializer.dart:60`, portanto servico e UI ja podem coexistir, mas isso nao esta modelado como regra explicita;
- o scheduler da UI ja respeita a execucao do servico em `lib/presentation/boot/ui_scheduler_policy.dart:24`, mas isso nao participa do contrato de instancia unica.

O principal problema nao e "falta de mutex". O principal problema e que o bootstrap trata IPC como se fosse autoridade adicional, o que reduz confiabilidade e piora desempenho. O segundo problema e que a origem do launch nao esta normalizada.

## Comportamento Alvo

### Regras funcionais

1. `UI` e `Servico` sao papeis de processo diferentes.
2. `UI` usa apenas o mutex de UI.
3. `Servico` usa apenas o mutex de servico.
4. Uma instancia de servico em execucao nunca deve bloquear a abertura de uma nova UI.
5. Uma UI ja aberta deve bloquear apenas outra UI.
6. Se a segunda tentativa de abrir UI vier de `windows startup`, o processo deve encerrar silenciosamente, sem popup.
7. Se a segunda tentativa vier de abertura manual, o app pode avisar o usuario e tentar focar a janela existente.

### Matriz de cenarios esperados

- `UI manual` + nenhuma `UI` aberta + servico parado: abre normalmente.
- `UI manual` + `UI` ja aberta: nao abre segunda UI, tenta focar a janela existente e mostra aviso.
- `UI auto start` + `UI` ja aberta: nao abre segunda UI e encerra sem popup.
- `Servico` em execucao + usuario abre `UI`: abre normalmente.
- `UI` em execucao + `Servico` inicia: servico inicia normalmente.
- `Servico` em execucao + `UI` aberta: scheduler local da UI permanece desativado.

## Diagnostico do Codigo Atual

### 1. O bootstrap da UI mistura autoridade de mutex com heuristica de IPC

Evidencias:

- `lib/main.dart:65`
- `lib/main.dart:74`
- `lib/main.dart:80`
- `lib/presentation/boot/single_instance_checker.dart:58`
- `lib/presentation/boot/single_instance_checker.dart:69`

Analise:

- a UI primeiro adquire o lock via mutex;
- se o lock passar, ela ainda executa `checkIpcServerAndHandle()`;
- isso significa que um servidor local respondendo `PONG` em uma das portas configuradas pode impedir a abertura, mesmo quando o mutex diz que esta e a primeira UI.

Impacto:

- queda de confiabilidade por falso positivo;
- custo de startup desnecessario em toda abertura da UI;
- a decisao fica distribuida entre duas fontes de verdade.

Conclusao:

- o mutex deve ser a unica autoridade para exclusividade;
- o IPC deve existir apenas como mecanismo auxiliar apos a negacao do mutex.

### 2. O fallback do lock ainda e permissivo demais

Evidencias:

- `lib/core/config/single_instance_config.dart:35`
- `lib/infrastructure/external/system/single_instance_service.dart:100`
- `lib/infrastructure/external/system/single_instance_service.dart:132`
- `test/unit/infrastructure/external/system/single_instance_service_test.dart:9`
- `test/unit/infrastructure/external/system/single_instance_service_test.dart:28`

Analise:

- o modo padrao de fallback ainda e `failOpen`;
- se `CreateMutexW` falhar com handle invalido, o app pode seguir sem garantia de exclusividade;
- pior: se ocorrer excecao no metodo, o fluxo cai em `catch` e retorna `true`, o que tambem abre em modo permissivo.

Impacto:

- a regra "uma UI por maquina" nao e forte em cenarios de erro;
- qualquer falha no caminho do mutex pode virar startup concorrente.

Conclusao:

- o comportamento de falha precisa ser revisto por papel do processo;
- no minimo, servico deve operar em politica `failSafe`;
- a excecao geral precisa respeitar a mesma politica.

### 3. A deteccao de auto start esta inconsistente entre HKCU e HKLM

Evidencias:

- `lib/main.dart:39`
- `lib/presentation/boot/single_instance_checker.dart:108`
- `lib/presentation/providers/system_settings_provider.dart:154`
- `lib/presentation/providers/system_settings_provider.dart:162`
- `installer/setup.iss:70`

Analise:

- o app considera auto start quando encontra `--startup-launch`;
- o caminho gerenciado pelo app em HKCU grava esse argumento;
- o caminho criado pelo instalador em HKLM grava apenas `--minimized`;
- portanto, um auto start vindo do instalador ainda pode ser tratado como abertura manual.

Impacto:

- popup indevido no login do Windows;
- comportamento diferente para duas origens que representam o mesmo evento de negocio.

Conclusao:

- a origem do launch precisa ser um contrato unico e explicito;
- `--minimized` nao pode continuar servindo como proxy de auto start.

### 4. A supressao do popup acontece tarde demais

Evidencias:

- `lib/presentation/boot/single_instance_checker.dart:79`
- `lib/presentation/boot/single_instance_checker.dart:108`

Analise:

- mesmo quando `_isStartupLaunch` e `true`, o metodo ainda tenta descobrir usuario da instancia existente antes de encerrar silenciosamente;
- isso adiciona custo de IPC no caso em que o comportamento desejado ja e conhecido.

Impacto:

- latencia desnecessaria em auto start duplicado;
- mais superficie para erro em um fluxo que deveria ser trivial.

Conclusao:

- launch de origem `windows startup` deve ser tratado o mais cedo possivel;
- se o lock de UI falhar e a origem for startup, o processo deve apenas logar e sair.

### 5. UI e servico ja estao separados, mas o contrato ainda e implicito

Evidencias:

- `lib/core/config/single_instance_config.dart:47`
- `lib/core/config/single_instance_config.dart:49`
- `lib/presentation/boot/service_mode_initializer.dart:60`
- `lib/core/utils/service_mode_detector.dart:62`
- `lib/core/utils/service_mode_detector.dart:80`
- `lib/presentation/boot/ui_scheduler_policy.dart:24`
- `test/unit/presentation/boot/ui_scheduler_policy_test.dart:34`

Analise:

- UI e servico usam mutexes diferentes;
- o servico e identificado por `Session 0`, `--run-as-service` ou `SERVICE_MODE`;
- a UI ainda abre quando o servico esta rodando;
- o scheduler local da UI e que passa a ser desativado quando o servico esta `installed + running`.

Impacto:

- o requisito do usuario ja esta parcialmente atendido no comportamento atual;
- porem ele depende de conhecimento difuso e nao esta protegido por teste especifico de coexistencia.

Conclusao:

- o plano deve preservar essa separacao;
- e necessario promover isso a regra explicita do bootstrap.

### 6. O protocolo IPC atual e generico e facil de colidir

Evidencias:

- `lib/core/config/single_instance_config.dart:78`
- `lib/core/config/single_instance_config.dart:79`
- `lib/infrastructure/external/system/ipc_service.dart:107`
- `lib/infrastructure/external/system/ipc_service.dart:317`
- `test/unit/infrastructure/external/system/ipc_service_test.dart:11`
- `test/unit/presentation/boot/single_instance_checker_test.dart:106`

Analise:

- o handshake usa apenas `PING` e `PONG`;
- a descoberta percorre porta base e portas alternativas;
- isso e suficiente para a propria base de codigo, mas fraco como prova de identidade.

Impacto:

- risco de falso positivo se outro processo responder ao mesmo protocolo;
- custo de descoberta em toda abertura da UI.

Conclusao:

- o protocolo deve ser endurecido;
- e melhor reduzir o uso do IPC a cenarios em que o mutex ja negou a abertura.

## Causas Raiz

- Nao existe um `LaunchContext` unico para modelar origem, papel e intencao do processo.
- O bootstrap depende de `bool` disperso em vez de um contrato semantico.
- O instalador e o app escrevem entradas de auto start diferentes.
- O IPC esta participando da decisao de exclusividade quando deveria apenas complementar UX.
- A coexistencia UI + servico esta correta por acaso arquitetural, nao por contrato formal.

## Arquitetura Alvo

### 1. Introduzir `LaunchContext`

Criar um objeto unico de bootstrap, por exemplo em `core/bootstrap` ou `presentation/boot`, com campos como:

- `processRole`: `ui` | `service`
- `launchOrigin`: `manual` | `windowsStartup` | `serviceControlManager` | `scheduledExecution` | `unknown`
- `appMode`: `server` | `client`
- `startMinimized`
- `scheduleId`
- `suppressSecondInstanceWarning`

Objetivo:

- remover leitura ad hoc de `Platform.executableArguments` em varios pontos;
- centralizar a regra de interpretacao de args, env e origem do processo.

### 2. Normalizar a origem do launch

Diretriz:

- substituir a semantica solta de `--startup-launch` por um contrato mais claro, por exemplo `--launch-origin=windows-startup`;
- manter compatibilidade temporaria lendo `--startup-launch` como alias legado;
- atualizar todos os produtores de startup para usar o mesmo marcador.

Produtores a alinhar:

- `lib/presentation/providers/system_settings_provider.dart`
- `installer/setup.iss`
- eventualmente qualquer script futuro de Task Scheduler

### 3. Tornar o mutex a unica autoridade de exclusividade

Fluxo alvo da UI:

1. montar `LaunchContext`;
2. detectar se o processo e `service` ou `ui`;
3. se for `service`, usar apenas `serviceMutex`;
4. se for `ui`, usar apenas `uiMutex`;
5. se o mutex permitir, continuar startup sem `checkIpcServerAndHandle()`;
6. se o mutex negar:
   - `windowsStartup`: encerrar silenciosamente;
   - `manual`: tentar notificar a UI existente e decidir se mostra popup.

Beneficios:

- elimina falso positivo de IPC em primeira abertura;
- reduz latencia de startup;
- deixa a decisao tecnicamente defensavel.

### 4. Manter servico fora do escopo de instancia da UI

Diretriz:

- a coexistencia `1 UI + 1 Servico` por maquina passa a ser regra explicita;
- o servico nao deve participar da decisao de "segunda UI";
- a UI nao deve participar da decisao de "segundo servico".

Complemento:

- a unica interacao entre UI e servico continua sendo politica operacional, como `UiSchedulerPolicy`, nunca bloqueio de instancia.

### 5. Endurecer o IPC

Curto prazo:

- trocar `PING/PONG` puro por um handshake com identidade do app, por exemplo `BACKUP_DATABASE_IPC_V1:<appId>`;
- incluir resposta com `instanceRole`, `username`, `pid` e `protocolVersion`.

Medio prazo:

- avaliar migracao de TCP localhost para Named Pipe do Windows, caso a base continue desktop-only;
- se o TCP for mantido, reduzir fan-out e depender de endpoint conhecido ou cache persistido.

### 6. Melhorar observabilidade

Toda decisao de bootstrap deve registrar:

- `processRole`
- `launchOrigin`
- `appMode`
- resultado do mutex
- motivo de encerramento silencioso
- se houve tentativa de foco da janela existente

## Melhorias Complementares de Confiabilidade e Desempenho

### Quick Wins

#### 1. Encerrar mais cedo no caso `windowsStartup` duplicado

Situacao atual:

- `SingleInstanceChecker.handleSecondInstance()` ainda tenta resolver `existingUser` antes de checar se o launch veio de startup automatico.

Diretriz:

- quando o lock de UI falhar e `launchOrigin == windowsStartup`, encerrar imediatamente;
- nao buscar `existingUser`;
- nao fazer retentativas de `notifyExistingInstance`;
- apenas registrar log tecnico do motivo do encerramento.

Beneficio:

- reduz latencia no login do Windows;
- reduz dependencia de IPC em um fluxo que nao precisa de UX interativa.

#### 2. Reaproveitar o resultado de deteccao de modo servico

Situacao atual:

- `ServiceModeDetector.isServiceMode()` aparece no bootstrap principal e tambem em pontos posteriores de inicializacao.

Diretriz:

- o valor detectado deve entrar no `LaunchBootstrapContext` e ser reutilizado;
- o restante do bootstrap nao deve continuar chamando o detector diretamente sem necessidade.

Beneficio:

- reduz trabalho repetido;
- reduz ruído de logs;
- deixa o fluxo mais deterministico.

#### 3. Centralizar leitura de argumentos de bootstrap

Situacao atual:

- argumentos sao lidos em `main.dart`, `AppInitializer.getLaunchConfig()` e `ServiceModeDetector`.

Diretriz:

- toda leitura de `Platform.executableArguments` relevante para bootstrap deve sair do resolver de contexto;
- as etapas posteriores devem consumir o contexto ja resolvido, em vez de reler argumentos crus.

Beneficio:

- menor acoplamento;
- menos parse duplicado;
- menor risco de divergencia semantica entre componentes.

### Endurecimento de Falhas

#### 4. Fazer o caminho de excecao de `checkAndLock()` respeitar a politica de fallback

Situacao atual:

- o caminho de excecao geral em `SingleInstanceService.checkAndLock()` retorna startup permitido.

Diretriz:

- a excecao deve usar a mesma politica configurada para falha de `CreateMutexW`;
- se a politica for `failSafe`, a excecao tambem deve bloquear startup;
- idealmente o servico deve operar com politica mais conservadora do que a UI.

Beneficio:

- coerencia de contrato;
- maior previsibilidade em falha real de sistema.

#### 5. Diferenciar politica de fallback por papel do processo

Proposta:

- `service`: `failSafe` por default;
- `ui`: configuravel, com transicao controlada se for necessario preservar comportamento legado.

Beneficio:

- evita concorrencia invisivel de servico;
- preserva opcao de rollout gradual para a UI.

### Higiene de Bootstrap

#### 6. Remover o probe preventivo de IPC do caminho feliz

Esta melhora ja esta prevista no `PR-2`, mas merece destaque como ganho de desempenho:

- hoje toda abertura de UI pode fazer sweep de portas;
- no desenho alvo, o IPC passa a existir apenas como apoio apos negacao do mutex.

Beneficio:

- reduz tempo medio de startup;
- reduz conexoes locais desnecessarias;
- elimina uma classe inteira de falso positivo.

#### 7. Estabelecer orcamento de latencia de startup

Proposta:

- registrar duracoes de:
  - resolucao do contexto de bootstrap
  - aquisicao de mutex
  - subida do IPC server
  - inicializacao da janela

Beneficio:

- permite confirmar regressao ou ganho real apos cada PR;
- evita que melhorias de confiabilidade causem degradacao invisivel.

### IPC

#### 8. Tornar o handshake identificavel

Diretriz:

- sair de `PING/PONG` puro;
- responder com algo que identifique app, versao de protocolo e papel da instancia.

Beneficio:

- reduz falso positivo;
- melhora diagnostico de compatibilidade entre versoes.

#### 9. Revisar estrategia de descoberta por portas

Diretriz:

- manter cache de porta ativa apenas como otimizacao de segunda instancia;
- reduzir o fan-out de tentativas;
- reconsiderar TTL de cache quando o fluxo `mutex-first` ja estiver implantado.

Beneficio:

- menor carga local;
- descoberta mais previsivel.

### Testabilidade e Contratos

#### 10. Transformar comportamento atual em testes de convivencia

Devem existir testes cobrindo explicitamente:

- `UI` abre com servico em execucao;
- `Servico` inicia com UI aberta;
- `windowsStartup` duplicado encerra sem popup;
- launch manual duplicado continua mostrando aviso;
- falso `PONG` nao bloqueia a primeira UI quando o mutex permitiu startup.

#### 11. Aumentar granularidade dos logs de decisao

Diretriz:

- diferenciar nos logs:
  - `mutex_denied_ui_duplicate`
  - `mutex_denied_service_duplicate`
  - `duplicate_launch_suppressed_windows_startup`
  - `duplicate_launch_manual_warning_shown`
  - `existing_instance_focus_succeeded`
  - `existing_instance_focus_failed`

Beneficio:

- facilita diagnostico de suporte;
- melhora capacidade de validar rollout em campo.

## Fluxo Alvo de Bootstrap

### UI

1. Resolver `LaunchContext`.
2. Se `processRole == service`, sair deste fluxo e ir para `ServiceModeInitializer`.
3. Tentar adquirir `uiMutex`.
4. Se adquirir:
   - iniciar UI;
   - iniciar IPC apenas para suportar foco de janela;
   - nao fazer probe preventivo em portas.
5. Se nao adquirir:
   - se `launchOrigin == windowsStartup`, logar e encerrar;
   - senao, tentar notificar a UI existente;
   - mostrar aviso apenas para launch manual.

### Servico

1. Resolver `LaunchContext`.
2. Adquirir `serviceMutex`.
3. Se adquirir, iniciar modo servico.
4. Se nao adquirir, encerrar sem afetar UI.
5. Nunca iniciar IPC de UI.

## Plano de Implementacao por PR

## PR-1 - Contrato de bootstrap e origem do launch

Objetivo:

- introduzir `LaunchContext`;
- normalizar `LaunchOrigin`;
- alinhar HKCU e HKLM para o mesmo marcador de auto start.

Arquivos candidatos:

- `lib/main.dart`
- `lib/presentation/boot/app_initializer.dart`
- `lib/presentation/boot/single_instance_checker.dart`
- `lib/core/config/single_instance_config.dart`
- `lib/core/utils/service_mode_detector.dart`
- `lib/presentation/providers/system_settings_provider.dart`
- `installer/setup.iss`

Entregas:

- novo parser centralizado de contexto de launch;
- compatibilidade com `--startup-launch` durante a transicao;
- novo marcador unico para startup automatico;
- `SingleInstanceChecker` deixa de depender de `bool isStartupLaunch` isolado.

Testes:

- parser reconhece `windowsStartup`;
- parser reconhece `serviceControlManager`;
- startup vindo do instalador e startup vindo da configuracao do app produzem o mesmo `LaunchOrigin`;
- launch manual continua distinto.

### Escopo fechado do PR-1

Este PR nao altera ainda a autoridade do mutex nem remove o probe preventivo de IPC. O foco aqui e somente:

- parar de tratar auto start como caso especial disperso;
- introduzir um contrato semantico para origem do processo;
- alinhar os dois produtores atuais de startup;
- preparar o bootstrap para o `PR-2` sem mudar ainda a regra de exclusividade.

Resultado esperado do PR-1:

- o app sabe distinguir `manual`, `windowsStartup` e `serviceControlManager`;
- a decisao de mostrar popup deixa de depender de `bool` isolado;
- HKCU e HKLM passam a representar o mesmo tipo de launch.

### Decisoes de desenho do PR-1

#### 1. Introduzir `LaunchOrigin`

Proposta:

- criar enum com pelo menos:
  - `manual`
  - `windowsStartup`
  - `serviceControlManager`
  - `scheduledExecution`
  - `unknown`

Uso no PR-1:

- `windowsStartup` substitui o papel semantico de `isStartupLaunch`;
- `serviceControlManager` representa o que hoje e inferido por `ServiceModeDetector`.

#### 2. Introduzir `LaunchBootstrapContext`

Para manter o escopo do PR-1 pequeno, o ideal e nao tentar resolver todo o `LaunchContext` final ainda. A recomendacao e criar um contexto inicial de bootstrap, contendo apenas o que e necessario antes do Flutter binding:

- `launchOrigin`
- `isServiceMode`
- `rawArgs`
- `rawEnvironment`
- `startMinimizedFromArgs`

Motivo:

- `appMode` hoje depende de `.env` e `.install_mode`, e isso pode continuar fora do PR-1;
- o que precisamos imediatamente para corrigir popup e auto start e apenas a origem do launch e o papel do processo.

#### 3. Adotar um marcador unico de origem

Proposta de contrato:

- novo prefixo: `--launch-origin=`
- valor para startup do Windows: `--launch-origin=windows-startup`
- valor para SCM/NSSM: nao precisa necessariamente ser passado como argumento se `ServiceModeDetector` ja classificar corretamente, mas o resolver deve produzir `serviceControlManager`

Compatibilidade legada:

- `--startup-launch` continua aceito por um ciclo como alias de `windowsStartup`

#### 4. `--minimized` deixa de representar origem

Regra:

- `--minimized` continua existindo apenas como hint de UX;
- qualquer decisao de popup ou comportamento de segunda instancia passa a depender de `LaunchOrigin`, nao de minimizacao.

### Proposta de implementacao por arquivo

#### Novo arquivo: `lib/presentation/boot/launch_bootstrap_context.dart`

Responsabilidade:

- definir `LaunchOrigin`;
- definir `LaunchBootstrapContext`;
- expor um resolver central, por exemplo `LaunchBootstrapContextResolver.resolve()`.

API sugerida:

```dart
enum LaunchOrigin {
  manual,
  windowsStartup,
  serviceControlManager,
  scheduledExecution,
  unknown,
}

class LaunchBootstrapContext {
  const LaunchBootstrapContext({
    required this.launchOrigin,
    required this.isServiceMode,
    required this.rawArgs,
    required this.rawEnvironment,
    required this.startMinimizedFromArgs,
  });
}
```

Responsabilidades do resolver:

- ler `Platform.executableArguments`;
- ler `Platform.environment`;
- mapear `--launch-origin=windows-startup`;
- mapear alias legado `--startup-launch`;
- consultar `ServiceModeDetector.isServiceMode()`;
- derivar `startMinimizedFromArgs`.

#### `lib/core/config/single_instance_config.dart`

Adicionar constantes de contrato:

- `launchOriginArgumentPrefix`
- `windowsStartupLaunchOriginValue`
- `legacyStartupLaunchArgument`

Recomendacao:

- manter `startupLaunchArgument` como alias legado por compatibilidade, ou renomear com comentario de deprecacao controlada no plano de migracao do `PR-5`.

#### `lib/main.dart`

Mudancas esperadas no PR-1:

- parar de calcular `isStartupLaunch` diretamente;
- resolver `LaunchBootstrapContext` logo no inicio;
- logar `launchOrigin`, `isServiceMode` e `startMinimizedFromArgs`;
- injetar o contexto no `SingleInstanceChecker`;
- manter por enquanto a estrutura geral do bootstrap.

Importante:

- `ServiceModeDetector.isServiceMode()` nao deve passar a ser chamado em varios lugares sem cache;
- o contexto precisa reaproveitar o resultado ja detectado para evitar trabalho duplicado.

#### `lib/presentation/boot/single_instance_checker.dart`

Mudancas esperadas:

- trocar `bool isStartupLaunch` por `LaunchOrigin launchOrigin`;
- concentrar a regra de supressao do popup em algo como:
  - `launchOrigin == LaunchOrigin.windowsStartup`
- manter intacta a logica de foco/notificacao neste PR, exceto pela troca da fonte de decisao.

Resultado:

- a classe para de depender de um `bool` sem semantica;
- o comportamento fica pronto para suportar novas origens sem proliferar flags.

#### `lib/core/utils/service_mode_detector.dart`

Mudancas esperadas:

- nenhuma quebra estrutural;
- no maximo, expor melhor o significado do match para o resolver de bootstrap;
- preservar o cache interno atual para nao repetir custo de deteccao.

Recomendacao:

- evitar refatoracao excessiva aqui no PR-1;
- a meta e consumo centralizado, nao reescrever o detector.

#### `lib/presentation/providers/system_settings_provider.dart`

Mudancas esperadas:

- atualizar o comando escrito em `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`;
- substituir `--startup-launch` por `--launch-origin=windows-startup`;
- manter `--minimized` somente quando a configuracao `start_minimized` estiver ativa.

Comando alvo:

- sem minimizacao: `"exe" --launch-origin=windows-startup`
- com minimizacao: `"exe" --minimized --launch-origin=windows-startup`

#### `installer/setup.iss`

Mudancas esperadas:

- atualizar a entrada `HKLM\Software\Microsoft\Windows\CurrentVersion\Run`;
- hoje ela escreve apenas `--minimized`;
- o PR-1 deve passar a escrever o mesmo marcador de origem usado em HKCU.

Comando alvo:

- `"{app}\backup_database.exe" --minimized --launch-origin=windows-startup`

Observacao:

- esse alinhamento e obrigatorio para eliminar popup indevido no login do Windows.

#### `lib/presentation/boot/app_initializer.dart`

Mudancas esperadas:

- nenhuma alteracao funcional obrigatoria no PR-1;
- opcionalmente, aceitar o contexto resolvido de fora em vez de reler argumentos soltos no futuro;
- por enquanto, manter o uso atual para evitar ampliar escopo.

### Sequencia recomendada de implementacao do PR-1

1. Criar `LaunchOrigin` e `LaunchBootstrapContext`.
2. Cobrir o resolver com testes unitarios independentes.
3. Refatorar `main.dart` para usar o resolver.
4. Refatorar `SingleInstanceChecker` para depender de `LaunchOrigin`.
5. Atualizar `SystemSettingsProvider` para escrever o novo argumento.
6. Atualizar `installer/setup.iss` para escrever o mesmo argumento.
7. Ajustar testes existentes e adicionar casos de compatibilidade legada.

### Testes do PR-1

#### Novos testes sugeridos

- `test/unit/presentation/boot/launch_bootstrap_context_resolver_test.dart`
- casos:
  - `should return windowsStartup when args contain --launch-origin=windows-startup`
  - `should return windowsStartup when args contain legacy --startup-launch`
  - `should return manual when no startup marker is present`
  - `should return serviceControlManager when service mode is detected`
  - `should set startMinimizedFromArgs when args contain --minimized`

#### Testes existentes a adaptar

- `test/unit/presentation/boot/single_instance_checker_test.dart`
  - trocar `isStartupLaunch: true` por `launchOrigin: LaunchOrigin.windowsStartup`
- `test/unit/presentation/providers/system_settings_provider_test.dart`
  - atualizar assertions do comando de registro para o novo marcador

#### Validacoes manuais do PR-1

- instalar com a task `startup` habilitada e verificar a entrada HKLM `Run`;
- habilitar `Iniciar com o Windows` dentro do app e verificar a entrada HKCU `Run`;
- confirmar que ambas as entradas carregam o mesmo `launch-origin`;
- abrir a app manualmente com uma UI ja rodando e confirmar que o comportamento visual nao mudou neste PR.

### Criterios de pronto do PR-1

- existe um unico ponto de resolucao da origem do launch;
- `SingleInstanceChecker` nao depende mais de `bool isStartupLaunch`;
- HKCU e HKLM usam o mesmo marcador de startup;
- `--startup-launch` continua aceito por compatibilidade;
- nenhum comportamento de UI muda para launch manual;
- testes unitarios novos e adaptados passam.

### Fora do escopo do PR-1

- remover `checkIpcServerAndHandle()`;
- mudar a politica de fallback do mutex;
- endurecer o protocolo `PING/PONG`;
- trocar TCP por Named Pipe;
- reestruturar toda a modelagem de `LaunchConfig` em `AppInitializer`.

### Riscos especificos do PR-1

- se o resolver chamar `ServiceModeDetector` de forma errada, pode duplicar logs e trabalho;
- se HKLM e HKCU ficarem divergentes durante rollout, o popup indevido continua em parte das maquinas;
- se o parser novo nao mantiver compatibilidade com `--startup-launch`, instalacoes antigas podem regredir.

## PR-2 - Mutex-first e remocao do probe preventivo de IPC

Objetivo:

- remover a etapa `checkIpcServerAndHandle()` do fluxo de primeira instancia;
- tornar o mutex a unica autoridade.

Arquivos candidatos:

- `lib/main.dart`
- `lib/presentation/boot/single_instance_checker.dart`
- `lib/infrastructure/external/system/single_instance_service.dart`
- `lib/infrastructure/external/system/single_instance_ipc_client.dart`
- `lib/infrastructure/external/system/ipc_service.dart`

Entregas:

- fluxo de startup simplificado;
- IPC usado apenas quando o mutex negar abertura;
- correcoes na politica de fallback para respeitar `failSafe` inclusive em excecao.
- encerramento antecipado para `windowsStartup` duplicado, sem lookup de usuario.

Testes:

- primeira UI com mutex valido nao faz probe preventivo de IPC;
- `PONG` de processo estranho nao bloqueia abertura quando o mutex permitiu;
- excecao em `checkAndLock()` respeita politica configurada;
- servico continua usando mutex proprio.
- launch `windowsStartup` duplicado nao busca `existingUser` nem mostra popup.

## PR-3 - Regra explicita de convivencia entre UI e servico

Objetivo:

- consolidar o contrato `1 UI + 1 Servico`;
- garantir que servico nunca conte como instancia da UI.

Arquivos candidatos:

- `lib/main.dart`
- `lib/presentation/boot/service_mode_initializer.dart`
- `lib/presentation/boot/ui_scheduler_policy.dart`
- `lib/core/config/single_instance_config.dart`
- testes de bootstrap

Entregas:

- regra codificada por papel do processo;
- logs de bootstrap com `processRole`;
- cobertura de testes para coexistencia.
- definicao explicita de politica de fallback por papel, se aprovada no rollout.

Testes:

- UI abre normalmente com servico rodando;
- servico inicia normalmente com UI aberta;
- UI nao inicia scheduler local quando servico esta `installed + running`;
- servico nao tenta abrir recursos de UI.

## PR-4 - Endurecimento e desempenho do IPC

Objetivo:

- reduzir custo residual do IPC;
- diminuir risco de colisao de protocolo.

Arquivos candidatos:

- `lib/infrastructure/external/system/ipc_service.dart`
- `lib/core/config/single_instance_config.dart`
- `lib/domain/services/i_single_instance_ipc_client.dart`
- testes unitarios de IPC

Entregas:

- handshake com identidade do app;
- resposta contendo metadados de instancia;
- cleanup de timeouts e portas alternativas com base em uso real;
- avaliacao de Named Pipe como etapa opcional.
- logs mais granulares para descoberta e foco da instancia existente.

Testes:

- resposta invalida nao e tratada como instancia valida;
- app responde apenas ao protocolo esperado;
- envio de `SHOW_WINDOW` continua funcional;
- degradacao de tempo de descoberta fica limitada ao fluxo de segunda instancia.

## Backlog de Quick Wins

Estes itens podem ser absorvidos nos PRs acima sem abrir um PR separado:

- [ ] curto-circuito de `windowsStartup` duplicado antes de `getExistingInstanceUser()`
- [ ] reaproveitar `isServiceMode` do contexto em vez de redetectar no bootstrap
- [ ] unificar leitura de `Platform.executableArguments` no resolver de contexto
- [ ] adicionar logs de decisao com motivos tecnicos padronizados
- [ ] cobrir explicitamente coexistencia `1 UI + 1 Servico`
- [ ] cobrir caminho de excecao de `checkAndLock()` com `failSafe`

## Backlog de Risco Estrutural

Estes itens tem impacto maior e devem seguir a ordem dos PRs:

- [ ] retirar o IPC do caminho feliz de primeira abertura
- [ ] endurecer o handshake do protocolo local
- [ ] revisar `failOpen` como default da UI
- [ ] separar politica de fallback entre UI e servico
- [ ] medir latencia do bootstrap por etapa

## PR-5 - Migracao e rollout controlado

Objetivo:

- acomodar instalacoes existentes sem quebrar comportamento;
- evitar popup indevido durante transicao.

Entregas:

- leitura de alias legado `--startup-launch`;
- reescrita das entradas de startup no primeiro fluxo administrativo possivel;
- logs claros de modo legado vs modo novo;
- checklist operacional para instalacoes ja existentes.

Testes:

- entrada antiga ainda funciona sem popup indevido apos migracao;
- entrada nova produz comportamento consistente em HKCU e HKLM.

## Checklist Tecnico por Tema

### Bootstrap

- [ ] criar `LaunchContext`
- [ ] remover checagens duplicadas de origem do launch
- [ ] registrar logs com contexto consolidado

### Instancia unica

- [ ] manter mutex como fonte unica de verdade
- [ ] rever `failOpen` como default
- [ ] fazer `catch` de `checkAndLock()` respeitar a politica configurada

### Auto start

- [ ] padronizar argumento de origem
- [ ] atualizar HKCU `Run`
- [ ] atualizar HKLM `Run`
- [ ] manter compatibilidade retroativa temporaria

### UI + Servico

- [ ] declarar em codigo que servico nao bloqueia UI
- [ ] cobrir coexistencia com testes
- [ ] manter a decisao de scheduler separada da decisao de instancia

### IPC

- [ ] remover probe preventivo do caminho feliz
- [ ] endurecer handshake
- [ ] revisar cache de porta e timeouts

## Criterios de Aceite

- Ao abrir manualmente a UI com outra UI ja em execucao, o usuario recebe o comportamento atual de foco e aviso.
- Ao abrir a UI por auto start com outra UI ja em execucao, o processo encerra sem popup.
- Ao abrir a UI enquanto o servico esta rodando, a UI inicia normalmente.
- Ao iniciar o servico com a UI aberta, o servico inicia normalmente.
- A primeira abertura da UI nao depende mais de probe preventivo de IPC.
- A regra de instancia unica continua funcionando entre usuarios diferentes do Windows.
- O custo de startup da UI reduz no caminho feliz por remocao do sweep de portas.

## Riscos e Cuidados

- Mudar a interpretacao de argumentos sem compatibilidade quebra instalacoes existentes.
- Trocar a politica de fallback do mutex sem observabilidade pode causar bloqueio de startup dificil de diagnosticar.
- Alterar o protocolo IPC sem fase de compatibilidade pode quebrar foco de janela durante rollout misto.
- Se houver automacoes externas chamando o exe com `--minimized` e assumindo popup suprimido, elas terao de ser revisadas porque `--minimized` deixara de representar origem do launch.

## Recomendacoes de Implementacao

- Implementar primeiro o contrato de contexto e a normalizacao de auto start.
- Em seguida remover o probe preventivo de IPC.
- So depois endurecer protocolo e fallback.
- Tratar Named Pipe como opcao de fase 2, nao como prerequisito para consertar a confiabilidade atual.

## Lacunas de Teste Atuais

- Existe teste para "nao mostrar popup em startup launch" em `test/unit/presentation/boot/single_instance_checker_test.dart:129`, mas ele depende de injetar `isStartupLaunch` manualmente.
- Existe teste para fallback `failSafe` e `failOpen` em `test/unit/infrastructure/external/system/single_instance_service_test.dart:9` e `:28`, mas nao existe teste para caminho de excecao geral.
- Existe teste para `UiSchedulerPolicy` com servico rodando em `test/unit/presentation/boot/ui_scheduler_policy_test.dart:34`, mas nao existe teste de bootstrap garantindo explicitamente que servico nao bloqueia a UI.
- Existe teste de `IpcService` respondendo `PONG` em `test/unit/infrastructure/external/system/ipc_service_test.dart:11`, mas nao existe teste cobrindo falso positivo de IPC quando o mutex ja permitiu startup.

## Sequencia Recomendada

1. PR-1
2. PR-2
3. PR-3
4. PR-4
5. PR-5

## Decisao Recomendada

A melhoria mais importante nao e trocar de tecnologia de IPC. A melhoria mais importante e reorganizar a autoridade do bootstrap:

- `mutex` decide exclusividade;
- `launchOrigin` decide se mostra popup;
- `processRole` decide o escopo do lock;
- `IPC` entra apenas para foco e UX de segunda instancia.

Com essa separacao, a base fica mais confiavel, mais rapida no caminho feliz e alinhada com o requisito de que servico Windows nao deve contar como instancia de UI.
