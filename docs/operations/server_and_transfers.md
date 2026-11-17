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

O arquivo final existente tambem exige comparacao de conteudo para ser reutilizado;
igualdade de tamanho sozinha nao comprova que seja o mesmo backup. Um envio novo
sem retomada ainda respeita a opcao de validacao forte configurada no destino.
O sidecar `.sha256` registra o hash local, mas nao substitui a verificacao remota.

Falha inconclusiva de integridade (por exemplo, hash indisponivel ou read-back
interrompido), retorno falso do envio e falha de renomeacao preservam o `.part`.
Divergencia confirmada na validacao provoca tentativa de excluir o parcial.
Ele nunca e promovido a arquivo final sem passar pela validacao exigida.

O transporte transmite um fluxo de bytes, nao arquivos independentes por bloco.
A retomada consulta `SIZE` e envia o restante com `REST <offset>` seguido de
`STOR`; o aceite inicial nao basta, e necessario receber a confirmacao final.
O nome parcial inclui a identidade da execucao/destino. A reutilizacao depende
de manter o mesmo nome nas tentativas; uma nova execucao com outro `runId` nao
descobre automaticamente parciais antigos. Sem identidade, o nome e aleatorio.

Cancelamento aborta controle e dados sem enviar `QUIT` concorrentemente. Se
`keepPartOnCancel` estiver desativado, outra sessao tenta apagar o parcial;
falhas de acesso/rede sao registradas e podem deixar o parcial no destino.
Timeout invalida a sessao para nao reutilizar respostas atrasadas. O download
de verificacao tem timeout de inatividade e confere o tamanho recebido.

Erros de conexao durante `SIZE` nao significam ausencia do arquivo. Respostas
malformadas ou encerramento pelo servidor (`421`) invalidam a sessao, impedindo
que uma resposta atrasada seja usada no comando seguinte. Falhas de transporte
durante HASH ou read-back encerram a tentativa; nao se repete `RETR` nem se
testam comandos alternativos na mesma conexao comprometida. Respostas negativas
normais para comandos de hash ainda permitem tentar outro metodo de validacao.
Se a integridade de um arquivo final existente ficar inconclusiva, a tentativa
para sem autorizar sua substituicao. A proxima tentativa abre nova conexao e
consulta novamente o tamanho remoto antes de escolher o offset de retomada.

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

Os logs FTP ocultam comandos de autenticacao e ecos das credenciais conhecidas.
Logs de comunicacao ocultam campos sensiveis em mapas e listas aninhados.
Consulte [seguranca dos logs](../security/logging-and-secrets.md) para os limites,
exportacao de registros antigos e cuidados antes de enviar um diagnostico.
