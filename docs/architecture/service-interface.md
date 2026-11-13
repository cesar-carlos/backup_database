# Interface administrativa e executor Windows

Com um serviço registrado (inclusive parado), a abertura manual usa o modo
administrativo. Falha ao consultar o SCM também escolhe esse modo: indisponibilidade
não autoriza um segundo executor. O modo permanece fixo até encerrar o processo.

O serviço conserva o mutex global e o named pipe originais, mantendo a
compatibilidade com tarefas agendadas e a exclusão entre sessões Terminal Server.
A interface administrativa usa um mutex e pipe por ID de sessão. Uma segunda
abertura na mesma sessão restaura sua janela; outras sessões podem administrar o
mesmo executor. A abertura automática com serviço registrado sai silenciosamente.

A interface não inicia scheduler, fila, TCP, reconciliação de execuções nem limpeza
de temporários. Executar, cancelar e recalcular agendamento são comandos no pipe
global, com a validação de executável dos peers já aplicada pelo transporte.
O scheduler do serviço continua serializando backups locais, manuais e remotos.
Não há execução local nem repetição automática em falha/timeout de IPC: a execução
pode continuar mesmo sem resposta. Consultar Logs antes de repetir o comando.

Comandos administrativos de execução carregam um UUID de tentativa e a geração
do executor obtida antes do envio. A repetição de uma tentativa na mesma interface
recupera a resposta anterior (ou aguarda a execução em andamento). O serviço guarda
até 4096 comprovantes por geração e recusa novos comandos ao atingir o limite,
sem remover comprovantes que permitiriam executar novamente uma tentativa antiga.
O UUID também é o `runId` do histórico. Cancelamentos validam esse identificador,
não somente o agendamento, para não atingir outro backup da mesma configuração.

Ao reiniciar o serviço, comandos com geração antiga são recusados. Uma tentativa
sem confirmação permanece bloqueada nessa interface: consultar o histórico antes
de reabrir a interface para solicitar uma nova execução. Os comprovantes ficam em
memória; esta proteção não equivale a deduplicação persistente de novas solicitações
feitas após reabrir a interface. O mutex do executor permanece adquirido até a
saída do processo, inclusive durante falha ou timeout de encerramento.

Fechar a interface libera somente seus recursos e seu mutex. Não cancela o backup
nem para o serviço. Configurações e logs continuam no armazenamento de máquina;
preferências lidas apenas no boot do serviço exigem reiniciá-lo. A interface mostra
um aviso de modo administrativo e aguarda a conclusão de comandos; não espelha
percentuais de progresso nem a lista de conexões TCP do serviço.

As conexões compartilham SQLite em WAL, com espera de até cinco segundos pelo
escritor. O executor tenta copiar a DACL do banco para os arquivos WAL/SHM sem
adicionar usuários. Se esse ajuste falhar, registra um aviso e mantém os backups
funcionando; o acesso da interface pode exigir corrigir as permissões existentes.

O auto update é coordenado pelo serviço. A interface administrativa bloqueia a
instalação própria, pois consultar um snapshot de serviço ocioso não impede que um
novo backup comece logo após a consulta.

Sem serviço registrado, mantém-se a execução independente com mutex global.
Ao instalar o serviço a partir desse modo, o fluxo existente de fechar e iniciar
o serviço continua necessário uma vez. Na próxima abertura a UI será administrativa.

Regressões: `service_scheduler_proxy_test.dart`, `app_bootstrap_test.dart`,
`single_instance_service_test.dart`, `instance_coexistence_contract_test.dart` e
suítes existentes de IPC, scheduler e abertura de segunda instância.
