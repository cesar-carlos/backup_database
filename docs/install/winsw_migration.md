# Servico Windows e migracao para WinSW

O instalador distribui WinSW 2.12.0 x64 como
`{app}\tools\BackupDatabaseService.exe`. O download oficial e o arquivo em cache
sao verificados pelo SHA-256 fixado no build; a instalacao verifica novamente o
hash. O XML fica ao lado do executavel e nao e sobrescrito nos updates seguintes.

## Preservacao do servico existente

O instalador captura o rollback, para o servico, copia os arquivos e converte a
configuracao NSSM. A troca usa `ChangeServiceConfig` somente para `ImagePath`:
nao executa delete/create, nao solicita nem exporta a senha e nao altera conta,
dependencias, nome de exibicao, descricao, modo de inicio, inicio atrasado ou
ACL do servico. O registro NSSM e o executavel antigo permanecem disponiveis
para recuperacao. A senha continua armazenada pelo Windows.

Sao traduzidos executavel, argumentos, diretorio de trabalho, ambiente extra,
caminhos de stdout/stderr, visibilidade de console e atraso de reinicio. Uma
politica SCM de recuperacao explicitamente configurada e mantida; quando nao
existe, a politica padrao de reinicio NSSM e convertida para recuperacao SCM.
As saidas intencionais 77 (instancia existente) e 78 (handoff do update) tornam-se
0 apenas quando `BACKUP_SERVICE_WRAPPER=winsw`. Erros fatais continuam distintos
de zero. No NSSM, os codigos antigos continuam validos.

O runner cria um console oculto no modo servico, preservando os pipes de log,
para receber o Ctrl+C enviado pelo WinSW. O handler Dart registra SIGINT uma
unica vez; SIGTERM nao e suportado no Windows. O timeout do wrapper permite
concluir o encerramento gracioso antes de recorrer a terminacao forcada.

Configuracoes sem conversao segura, como hooks, afinidade, substituicao completa
do ambiente ou politicas especiais de AppExit, bloqueiam a migracao antes da
troca. O erro identifica a chave. Nao ha descarte silencioso: o administrador
precisa traduzir essa personalizacao antes de tentar novamente.

O XML nao contem credenciais da conta. Seu acesso e restrito a SYSTEM,
Administradores e leitura para a conta customizada do servico. Variaveis de
ambiente personalizadas podem conter segredos e devem ser tratadas como tal.

## Falhas, update e rollback

A transacao da troca fica em
`%ProgramData%\BackupDatabase\staging\service-migration\journal.json`.
Falha na troca ou no start restaura a imagem e a politica SCM anteriores. Um
servico originalmente parado nao e iniciado pela migracao. Interrupcao forcada
deixa a transacao persistida; a proxima tentativa recupera o estado anterior e
retorna erro para permitir uma nova instalacao apos a recuperacao.

A recuperacao pendente e verificada antes de validar os novos executaveis:
um WinSW corrompido ou uma copia incompleta nao impede a tentativa de retornar
ao wrapper original. Falha ao persistir a conclusao tambem aciona rollback.
Mudancas externas na conta ou imagem do servico interrompem a recuperacao e
mantem o journal para intervencao, sem sobrescrever o registro alterado.

O rollback completo do setup tambem restaura os arquivos, banco, XML, imagem
do servico e politica SCM. Assim, uma falha posterior a migracao pode retornar
ao NSSM sem recriar o registro. O XML WinSW existente e preservado nos updates
seguintes. O auto update nao executa comandos NSSM sobre um servico WinSW.
Antes de parar processos ou substituir arquivos e dados no rollback, sao
validados a conta, a imagem e o hash do snapshot do servico. O auto update
exige a conta original no contexto; se o contexto indica WinSW e o executavel
esta ausente, falha sem recorrer a reconfiguracao NSSM e preserva o contexto.

Contas customizadas sao preservadas tambem no update iniciado pela UI. Para
auto update silencioso iniciado pelo servico WinSW, o token do processo deve
ter permissoes administrativas. Se nao tiver, use o instalador elevado; nao ha
prompt UAC na sessao 0 nem troca automatica da conta para LocalSystem.

## Validacao antes da publicacao

Execute `flutter test test/unit/installer/winsw_migration_test.dart` para testar
SCM simulado, contas customizadas, idempotencia, hash invalido, configuracoes
nao suportadas, falhas e recuperacao apos interrupcao. Os testes do rollback
completo continuam em `test/unit/installer/rollback_update_test.dart`.

Em VM Windows isolada e configurada, execute como Administrador
`test/scripts/windows_winsw_smoke.ps1 -AppExePath <executavel-release>`.
Ele instala um servico temporario proprio, verifica start/stop/restart e remove
esse registro ao terminar. Nao execute em servidor de producao.

A homologacao de migracao real deve incluir servico NSSM com conta de dominio,
dependencias, inicio atrasado e recuperacao customizada; compare conta e ACLs
antes/depois, reinicie a maquina, provoque falha de copia/start e confirme o
rollback. O binario Flutter precisa ser recompilado: builds antigos nao possuem
a traducao dos codigos 77/78 para WinSW.

Referencias: [WinSW 2.12.0](https://github.com/winsw/winsw/releases/tag/v2.12.0),
[configuracao XML](https://github.com/winsw/winsw/blob/v2.12.0/doc/xmlConfigFile.md).
