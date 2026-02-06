# Fluxo Cliente/Servidor e Copia Local (analise)

## Objetivo

Descrever o fluxo completo de backup remoto no modo cliente, onde o servidor gera o backup e o cliente recebe o arquivo na pasta temp. Em seguida o cliente copia para o destino final (local/ftp/google/etc). Este documento foca no problema reportado: arquivos 0 KB no destino local e arquivo travado (lock) na pasta temp ate fechar o app.

## Fluxo Servidor -> Cliente (resumo)

1. Servidor executa o backup e gera o arquivo.
   - Arquivo principal: `lib/application/services/scheduler_service.dart`
2. Servidor copia o backup para a area de staging (transferBasePath/remote/<scheduleId>/arquivo).
   - `TransferStagingService.copyToStaging`
   - O path relativo e enviado ao cliente via socket.
3. Cliente recebe o `backupPath` e inicia download para a pasta temp.
   - `RemoteFileTransferProvider.transferCompletedBackupToClient`
   - Chama `ConnectionManager.requestFile` para baixar o arquivo.
4. O download grava em `<arquivo>.part`, e no final renomeia para o nome final.
   - `ConnectionManager._completeFileTransfer`

## Fluxo Cliente -> Destino Final (local)

1. O cliente chama `SendFileToDestinationService.sendFile`.
2. Para destino local, chama `LocalDestinationService.upload`.
3. Essa copia usa `copyToWithBugFix`, que:
   - Abre o arquivo de origem via `RandomAccessFile`
   - Le e escreve em um arquivo temporario `<destino>.tmp`
   - Valida tamanho e renomeia para o destino final

## Observacao importante

O problema reportado acontece DEPOIS do download. O arquivo na pasta temp esta correto, mas:

- O arquivo no destino final vira 0 KB
- O arquivo da pasta temp fica travado e nao pode ser apagado/renomeado enquanto o app estiver aberto

## Detalhamento do problema (o que vemos na pratica)

- Modo cliente conectado ao servidor.
- Backup remoto executa e conclui no servidor.
- Download para a pasta temp do cliente conclui com sucesso.
- O arquivo na pasta temp tem tamanho correto.
- Ao copiar para o destino local, o arquivo no destino final fica com 0 KB.
- O arquivo na pasta temp fica bloqueado (lock). Nao permite apagar ou renomear.
- O lock so some depois de fechar o aplicativo do cliente.

## Como reproduzir (passo a passo)

1. No cliente, configure um destino local com `tempPath` e um caminho final diferente.
2. Conecte o cliente ao servidor.
3. Execute um backup remoto pela lista de agendamentos.
4. Aguarde o download completo do arquivo na pasta temp.
5. Observe o arquivo no destino final: tamanho 0 KB.
6. Tente apagar/renomear o arquivo na pasta temp: operacao falha por lock.

## Resultado esperado vs resultado atual

Resultado esperado:

- Arquivo copiado do temp para o destino final com tamanho correto.
- Depois de copiar, o arquivo temp pode ser apagado.

Resultado atual:

- Arquivo no destino final com 0 KB.
- Arquivo temp permanece bloqueado ate encerrar o app.

## Evidencias observadas

- O arquivo recebido na pasta temp esta correto (tamanho completo).
- O problema acontece apenas na etapa de copia local.
- O lock indica handle aberto em algum ponto do fluxo do cliente.

## Pontos do codigo relevantes

- Download e escrita em disco:
  - `lib/infrastructure/socket/client/connection_manager.dart`
  - O download usa `IOSink` e grava em `<output>.part`
  - No final, renomeia para o arquivo final
- Copia local:
  - `lib/infrastructure/external/destinations/local_destination_service.dart`
  - Le o tamanho do arquivo de origem ANTES de copiar

## Hipotese principal (mais provavel)

O arquivo de origem ainda esta aberto (lock) no momento em que o cliente inicia a copia para o destino local.
No Windows, um arquivo aberto para escrita pode:

- Ficar travado para renomear/apagar
- Retornar tamanho 0 no `length()` em alguns casos

Se `LocalDestinationService` ler o tamanho do arquivo enquanto o handle ainda esta aberto:

- `fileSize` pode ser 0
- A copia cria um arquivo 0 KB no destino
- O arquivo do temp continua travado

Isso explica exatamente os sintomas:

- Temp OK (completo), mas ainda aberto
- Destino local 0 KB
- Somente fecha o lock quando o app termina

## Outros fatores que podem agravar

- `ConnectionManager` fecha o `IOSink`, mas:
  - Em caso de erro, o cleanup nao espera o `close()` concluir
  - O fluxo nao espera um "arquivo liberado" antes de iniciar a copia
- Em `transferCompletedBackupToClient`, apenas um delay fixo (300ms)
  - Pode ser insuficiente para liberar o handle no Windows

## Solucoes possiveis (recomendadas)

### 1) Esperar liberacao do arquivo antes de copiar

Antes de enviar para o destino local, tentar abrir o arquivo em modo leitura e fechar (loop com tentativas):

- Se abrir, o arquivo esta liberado
- Se falhar, aguardar e tentar novamente

### 2) Validar tamanho do arquivo local antes de copiar

No fluxo cliente -> destino local:

- Se `length() == 0`, abortar e tentar novamente depois
- Nao iniciar copia se o tamanho for 0

### 3) Validar tamanho esperado (metadata)

No download, o metadata do servidor informa o tamanho do arquivo. Armazenar esse valor e validar:

- Se o tamanho baixado for menor que o esperado, falhar e nao copiar

### 4) Garantir fechamento do handle do download

Em `ConnectionManager`:

- Garantir que `IOSink.close()` seja aguardado no cleanup
- Em caso de erro, nunca deixar o handle aberto

## Resultado esperado com as correcoes

- O arquivo temp nao fica travado
- A copia local so inicia quando o arquivo esta liberado
- O destino final nao recebe arquivo 0 KB
- O arquivo temp pode ser removido apos upload

## Arquivos relacionados (para referencia rapida)

- `lib/application/providers/remote_file_transfer_provider.dart`
- `lib/infrastructure/socket/client/connection_manager.dart`
- `lib/infrastructure/external/destinations/local_destination_service.dart`
- `lib/application/services/send_file_to_destination_service.dart`
- `lib/application/services/scheduler_service.dart`
