# Notes

Esta pasta guarda material datado: planos fechados, auditorias e runbooks de
smoke manual. Nem todo arquivo aqui descreve o comportamento atual do produto;
muitos servem como trilha de decisao e evidencia historica.

## O que ainda e operacional

| Documento | Uso |
| --- | --- |
| `execucao_remota_status_atual_2026-05-27.md` | Source-of-truth do que esta entregue em execucao remota (substitui o plano original como referencia ativa) |
| `execucao_remota_backlog_2026-05-27.md` | Apenas itens em aberto (escopo PR-6); cada acao com DoD |
| `smoke_firebird_operacional.md` | Runbook manual para validar Firebird em ambiente real |
| `smoke_windows_mica_m14.md` | Runbook manual para validar Mica/accent no Windows |

## O que e historico

| Documento | Status |
| --- | --- |
| `auditoria_qualidade_2026-04-18.md` | Relatorio fechado de auditoria |
| `plano_cliente_recursos_servidor_execucao_remota_2026-02-21.md` | Plano historico; substituido na pratica por `execucao_remota_status_atual_2026-05-27.md` + `execucao_remota_backlog_2026-05-27.md` (mantem cabecalho atualizado com marcacoes [x] dos entregues) |
| `plano_refatoracao_e_melhorias_2026-04-19.md` | Plano concluido; hoje serve como contexto e rastreio |
| `plano_suporte_firebird_2026-04-19.md` | Plano concluido do MVP Firebird; manter para contexto |

## Como usar esta pasta

- Se voce precisa saber "como o produto funciona hoje", comece fora de
  `notes/`.
- Se voce precisa entender por que algo foi decidido, como foi entregue ou qual
  era o plano original, use os documentos datados daqui.
