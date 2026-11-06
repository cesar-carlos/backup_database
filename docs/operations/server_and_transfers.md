# Operacao do servidor e transferencias

Referencia do comportamento implementado. Testes automatizados usam arquivos
temporarios e transportes simulados; nao substituem homologacao na maquina instalada.

## Abertura, bandeja e encerramento

- A instancia unica no Windows usa controle compartilhado entre sessoes.
  A abertura automatica duplicada encerra silenciosamente, inclusive no Terminal Server.
- Em release, falha ao adquirir o controle de instancia nao permite `fail_open`.
- Uma abertura manual tenta restaurar a janela existente. O Windows Service e
  headless: nao pode apresentar janela na sessao interativa.
- Fechar/minimizar para a bandeja exige que ela esteja disponivel; as transicoes
  sao serializadas para evitar janela invisivel sem forma de restauracao.
- Sair encerra agendamentos, conexoes, banco e bandeja antes de liberar o controle
  de instancia. Ha limites de tempo para etapas de limpeza bloqueadas.

## Temporarios e retencao

A limpeza do servidor consulta historicos em todos os estados, pois uma quebra
durante o envio pode deixar o backup marcado como concluido. A idade padrao e
24 horas. Referencias recentes e backups ativos impedem a exclusao.

A limpeza protege raizes configuradas, diretorios por tipo, destinos locais,
links e caminhos fora das pastas temporarias. Ela revalida idade e atividade
antes de apagar. Arquivos sem historico ou fora das pastas configuradas nao sao
varridos automaticamente. Alterar/remover um agendamento pode exigir revisao
manual dos arquivos antigos.

## FTP/FTPS

O envio usa `.part` e so renomeia depois da validacao. Retomada usa `REST` +
`STOR`; reaproveitar um parcial exige verificacao de conteudo, mesmo quando
seu tamanho ja coincide. Sem hash remoto, isso exige download de verificacao.

Cancelamento aborta controle e dados sem enviar `QUIT` concorrentemente. Se
`keepPartOnCancel` estiver desativado, outra sessao tenta apagar o parcial;
falhas de acesso/rede sao registradas e podem deixar o parcial no destino.
Timeout invalida a sessao para nao reutilizar respostas atrasadas. O download
de verificacao tem timeout de inatividade e confere o tamanho recebido.

## Google Drive

Arquivos acima de 5 MiB usam upload resumavel em blocos de 1 MiB. Um ID gerado
antes do envio e reutilizado nas tentativas da mesma chamada; uma resposta
perdida pode ser recuperada por consulta ao ID, sem criar outra copia.

Tamanho e MD5 devem corresponder ao original. Metadados ausentes provocam nova
consulta; ausencia persistente retorna falha, sem confirmar sucesso. Arquivo
com divergencia confirmada tem exclusao tentada e nao e reenviado automaticamente.

Cada tentativa usa transporte proprio, encerrado ao terminar, cancelar ou ficar
dois minutos sem progresso. Permissao negada nao e repetida; limites de requisicoes
e falhas transitorias podem ser repetidos. Cancelar apos o servidor concluir pode
deixar um arquivo remoto completo. O ID e a sessao nao sao persistidos entre
reinicios do aplicativo: nao ha promessa de retomada apos reiniciar o processo.

## Atualizacao e diagnostico

Veja [auto update](../install/auto_update_setup.md) e
[testes de atualizacao](../install/testing_auto_update.md). Para investigacao,
registre modo de execucao, versao, etapa e mensagem de erro; nao publique tokens,
senhas ou o conteudo completo do `.env`.
