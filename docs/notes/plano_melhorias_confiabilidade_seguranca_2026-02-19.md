# Plano de Melhorias de Confiabilidade e Segurança

Data: 2026-02-19
Projeto: `backup_database`

## Objetivo

Implementar melhorias priorizadas para:

- reduzir risco de vazamento de credenciais
- aumentar robustez dos fluxos de backup/upload/transferência
- fortalecer autenticação e transporte cliente-servidor
- melhorar aderência a Clean Architecture e testabilidade

## Escopo das melhorias (consolidadas)

- Segredos em repouso:
- migrar credenciais hoje persistidas em texto para `SecureCredentialService`
- Segredos em trânsito e logs:
- eliminar exposição de senha/token em logs, argumentos e connection strings
- Segurança do socket:
- evoluir autenticação para challenge-response anti-replay e TLS
- Confiabilidade:
- correções de lock de transferência por path canônico
- limpeza de temporários com política previsível em falhas
- correção de bugs funcionais de notificação
- Arquitetura:
- remover service locator de fluxo de aplicação (injeção por construtor)
- Qualidade:
- ampliar testes unitários/integrados para cenários críticos

## Fase 0 - Baseline e preparação

Checklist:

- [ ] Criar branch dedicada para hardening.
- [ ] Definir feature flag para mudanças de protocolo (`socket_auth_v2`, `socket_tls`).
- [ ] Mapear e classificar todos os campos sensíveis por módulo:
- [ ] `email password`
- [ ] `server connection password`
- [ ] `destination config` (FTP, Google Drive, Nextcloud, etc.)
- [ ] Validar baseline com:
- [ ] `flutter analyze`
- [ ] suíte unitária atual
- [ ] suíte de integração de socket/file transfer
- [ ] Registrar métricas base:
- [ ] taxa de falha de backup
- [ ] taxa de falha de upload
- [ ] tempo médio de execução

Critério de aceite:

- [ ] baseline de qualidade e risco documentado para comparação pós-hardening.

## Fase 1 - Segredos em repouso (SQLite -> Secure Storage)

Objetivo:

- remover credenciais sensíveis de persistência em texto puro.

Implementação:

- [ ] Introduzir `credentialKey` para entidades/repositórios que hoje persistem segredo diretamente.
- [ ] Ajustar `EmailConfigRepository` para:
- [ ] salvar senha no `SecureCredentialService`
- [ ] persistir apenas referência/chave no banco
- [ ] manter fallback de leitura legado por uma versão (migração gradual)
- [ ] Ajustar `ServerConnectionRepository` com mesma estratégia.
- [ ] Ajustar `BackupDestinationRepository` para externalizar segredos do campo `config`:
- [ ] FTP `password`
- [ ] Google Drive `accessToken` e `refreshToken`
- [ ] Nextcloud `appPassword`
- [ ] Criar migration idempotente:
- [ ] ler valor legado em texto
- [ ] gravar no `SecureCredentialService`
- [ ] limpar valor sensível do banco
- [ ] marcar registro como migrado
- [ ] Garantir compatibilidade com registros antigos durante rollout.

Arquivos alvo (referência):

- `lib/infrastructure/datasources/local/tables/email_configs_table.dart`
- `lib/infrastructure/repositories/email_config_repository.dart`
- `lib/infrastructure/datasources/local/tables/server_connections_table.dart`
- `lib/infrastructure/repositories/server_connection_repository.dart`
- `lib/infrastructure/datasources/local/tables/backup_destinations_table.dart`
- `lib/infrastructure/repositories/backup_destination_repository.dart`
- `lib/domain/entities/backup_destination.dart`

Testes:

- [ ] teste de migration com base legada populada.
- [ ] teste de leitura pós-migração sem texto puro no banco.
- [ ] teste de fallback para registros não migrados.
- [ ] teste de update/delete garantindo sincronização com secure storage.

Critério de aceite:

- [ ] nenhum segredo sensível permanece em texto claro nas tabelas alvo.
- [ ] leitura/escrita funcional para novos e antigos registros.

## Fase 2 - Hardening de logs e execução de processos

Objetivo:

- impedir vazamento de segredo em logs e argumentos processuais.

Implementação:

- [ ] Criar utilitário central de redaction (`SecretRedactor`) para:
- [ ] argumentos (`-P`, `--password`, `PWD=`, `PGPASSWORD=`)
- [ ] connection strings (`UID=`, `PWD=`, `password=`, `token=`)
- [ ] payloads de erro com tokens
- [ ] Aplicar redaction em `ProcessService` antes de logar comando/STDOUT/STDERR.
- [ ] Remover logs de connection string completa em fluxos Sybase/script.
- [ ] SQL Server:
- [ ] substituir `-P <senha>` por variável de ambiente suportada (`SQLCMDPASSWORD`) quando possível
- [ ] manter fallback seguro sem logar senha
- [ ] Garantir que erros retornados ao usuário não exponham segredo.

Arquivos alvo:

- `lib/infrastructure/external/process/process_service.dart`
- `lib/infrastructure/external/process/sql_script_execution_service.dart`
- `lib/infrastructure/external/process/sql_server_backup_service.dart`
- `lib/infrastructure/external/process/sybase_backup_service.dart`
- `lib/core/utils/logger_service.dart` (se necessário para helpers)

Testes:

- [ ] teste unitário para redaction de argumentos.
- [ ] teste unitário para redaction de connection string.
- [ ] teste unitário garantindo ausência de segredo em mensagens de erro.

Critério de aceite:

- [ ] logs não contêm senha/token em cenários nominal e de erro.

## Fase 3 - Segurança de transporte e autenticação do socket

Objetivo:

- reduzir risco de MITM e replay em autenticação cliente-servidor.

Implementação:

- [ ] Evoluir protocolo de autenticação:
- [ ] server envia nonce/challenge
- [ ] client responde assinatura/HMAC com segredo derivado
- [ ] challenge com expiração curta e uso único
- [ ] invalidar replay por nonce já utilizado
- [ ] Introduzir versionamento de protocolo para compatibilidade (`auth_v1` -> `auth_v2`).
- [ ] Implementar TLS no socket:
- [ ] servidor com certificado configurável
- [ ] cliente validando certificado/CA
- [ ] modo compatibilidade temporário sem TLS via feature flag
- [ ] Fortalecer hash de senha armazenada (migração para algoritmo com work factor adequado).

Arquivos alvo:

- `lib/infrastructure/socket/client/tcp_socket_client.dart`
- `lib/infrastructure/socket/server/tcp_socket_server.dart`
- `lib/infrastructure/socket/server/server_authentication.dart`
- `lib/infrastructure/protocol/auth_messages.dart`
- `lib/core/security/password_hasher.dart`

Testes:

- [ ] integração auth v2 sucesso/falha.
- [ ] integração replay attack (reutilização do mesmo payload deve falhar).
- [ ] integração com TLS habilitado.
- [ ] integração de fallback controlado (somente enquanto flag ativa).

Critério de aceite:

- [ ] autenticação rejeita replay.
- [ ] comunicação protegida em TLS no modo padrão.

## Fase 4 - Confiabilidade de file transfer e locking

Objetivo:

- evitar colisão e inconsistência de lock por variação de path.

Implementação:

- [ ] Normalizar/canonicalizar path antes de adquirir/liberar lock.
- [ ] Trocar `hashCode` por hash determinístico (`sha256`) no nome do lock file.
- [ ] Garantir uso do mesmo path normalizado em:
- [ ] `tryAcquireLock`
- [ ] `releaseLock`
- [ ] `isLocked`
- [ ] Revisar TTL de lock e estratégia de limpeza para cenários de desconexão abrupta.

Arquivos alvo:

- `lib/infrastructure/socket/server/file_transfer_message_handler.dart`
- `lib/infrastructure/file_transfer_lock_service.dart`

Testes:

- [ ] teste com paths equivalentes (absoluto/relativo) gerando o mesmo lock.
- [ ] teste de concorrência com múltiplos clientes no mesmo arquivo.
- [ ] teste de expiração e limpeza de locks órfãos.

Critério de aceite:

- [ ] lock consistente por arquivo real, sem colisão espúria.

## Fase 5 - Confiabilidade do scheduler e limpeza de temporários

Objetivo:

- manter estado consistente mesmo em erros parciais.

Implementação:

- [ ] Revisar ciclo de vida de arquivo temporário no `SchedulerService`:
- [ ] definir política clara de retenção em erro de upload
- [ ] mover limpeza para `finally` quando política exigir limpeza sempre
- [ ] usar variável segura para path temporário (`String?`) e guardas de null
- [ ] Remover logs de debug transitórios e redundantes no fluxo final.
- [ ] Revisar fechamento de progress state para evitar UI bloqueada em término/erro.

Arquivos alvo:

- `lib/application/services/scheduler_service.dart`
- `lib/application/providers/scheduler_provider.dart`
- `lib/presentation/widgets/backup/backup_progress_dialog.dart`
- `lib/presentation/widgets/backup/global_backup_progress_listener.dart`

Testes:

- [ ] teste de falha de upload confirmando política de limpeza adotada.
- [ ] teste de cancelamento no meio da execução com estado final coerente.
- [ ] widget/integration test para garantir que modal de progresso não fica órfão.

Critério de aceite:

- [ ] sem arquivos temporários órfãos fora da política definida.
- [ ] UI de progresso encerra corretamente em sucesso e falha.

## Fase 6 - Correções funcionais e aderência arquitetural

Objetivo:

- elevar previsibilidade, testabilidade e aderência às regras de arquitetura.

Implementação:

- [ ] Corrigir `sendTestEmail` para usar destinatário informado.
- [ ] Remover uso de `service_locator` dentro de `NotificationService`:
- [ ] injetar `ILicenseValidationService` por construtor
- [ ] atualizar DI no módulo correspondente
- [ ] Revisar serviços para dependências explícitas e sem acoplamento oculto.

Arquivos alvo:

- `lib/application/services/notification_service.dart`
- `lib/core/di/application_module.dart` (ou módulo correspondente)

Testes:

- [ ] unit test cobrindo uso do `recipient` em `sendTestEmail`.
- [ ] unit test do `NotificationService` com mock de licença injetado.

Critério de aceite:

- [ ] serviço totalmente testável sem resolver dependência via locator em runtime.

## Fase 7 - Testes, qualidade e rollout controlado

Objetivo:

- liberar em produção com risco controlado.

Checklist:

- [ ] Cobertura de testes adicionais:
- [ ] repositórios com migração de credenciais
- [ ] redaction de logs
- [ ] auth v2/TLS
- [ ] lock canônico
- [ ] scheduler cleanup policy
- [ ] Rodar pipeline completa:
- [ ] `dart format`
- [ ] `dart fix --apply` (quando aplicável)
- [ ] `flutter analyze`
- [ ] testes unitários e integração
- [ ] Rollout em etapas:
- [ ] ambiente interno
- [ ] piloto com clientes selecionados
- [ ] produção geral
- [ ] Plano de rollback:
- [ ] manter compatibilidade de protocolo por janela limitada
- [ ] manter fallback de leitura legado de credenciais por 1 versão
- [ ] monitoramento pós-release:
- [ ] erros de autenticação
- [ ] falhas de upload
- [ ] falhas de migração de credenciais

Critério de aceite:

- [ ] sem regressões críticas nos fluxos de backup local, remoto e agendado.

## Ordem recomendada de execução

1. Fase 0
2. Fase 2
3. Fase 1
4. Fase 4
5. Fase 5
6. Fase 6
7. Fase 3
8. Fase 7

Observação:

- A Fase 3 (TLS/auth v2) é mais disruptiva e deve entrar depois do hardening local e da estabilização de credenciais/logs.


## Adendo de compatibilidade com plano de notificacoes multi-config

Referencia: `docs/notes/componente_notificacoes_multi_config_email.md`

Sem conflito de objetivo, mas existem pontos de coordenacao obrigatorios:

- Ordem de execucao:
- a iniciativa de notificacoes multi-config deve entrar como `Prioridade Imediata` antes da Fase 2 deste plano
- apos concluir multi-config, retomar este plano a partir da Fase 2

- Migracoes de banco:
- reservar `schemaVersion 19` para multi-config de notificacoes
- iniciar migracoes de seguranca de credenciais a partir de `schemaVersion 20`
- nao criar duas migracoes diferentes alterando `email_configs_table` na mesma versao

- Sobreposicoes que devem ser deduplicadas:
- `sendTestEmail` usando recipient informado (citado na Fase 6 e no plano multi-config)
- remocao de `service_locator` em `NotificationService` (citado na Fase 6 e no plano multi-config)

Regra de implementacao:

- quando um item sobreposto for entregue no plano multi-config, marcar o item equivalente deste plano como concluido por referencia cruzada (sem reimplementar).

## Conformidade com .cursor/rules (validacao adicional)

Regras consideradas:

- `clean_architecture.mdc`: Application nao pode importar Infrastructure/Presentation
- `project_specifics.mdc`: DI via `get_it` e dependencia por construtor (DIP)
- `flutter_widgets.mdc`: widgets pequenos/componentizados (meta < 150 linhas), uso de `const`
- `testing.mdc`: testes unitarios/widget com padrao AAA

Ajustes obrigatorios para aderencia:

- [ ] Em `NotificationService` (camada Application), depender de abstracao (`IEmailService` em Domain/Application contract), nunca de implementacao concreta de Infrastructure.
- [ ] Garantir que implementacoes concretas de email fiquem somente em Infrastructure e sejam registradas no `get_it`.
- [ ] Em refatoracoes de UI, limitar widgets/componentes grandes e extrair subwidgets privados/reutilizaveis conforme regra de composicao.
- [ ] Incluir `const` sempre que aplicavel nos novos widgets para reduzir rebuilds.
- [ ] Testes novos devem seguir AAA e estrutura espelhando pastas de `lib/`.

Conclusao:

- plano permanece valido; com os ajustes acima fica estritamente aderente ao conjunto de rules.
