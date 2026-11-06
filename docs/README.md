# Documentacao

Use este indice. Documento com data no nome e snapshot historico, nao
contrato do produto. Contrato vivo de servidor/protocolo:
`onboarding/execucao_remota.md`.

## Comece por aqui

| Objetivo | Documento |
| --- | --- |
| Instalar e configurar a aplicacao | `install/installation_guide.md` |
| Confirmar requisitos por ambiente e banco | `requirements.md` |
| Ajustar PATH das ferramentas externas | `path_setup.md` |
| Entender a arquitetura atual | `onboarding/architecture_overview.md` |
| Protocolo socket e modo servidor | `onboarding/execucao_remota.md` |
| Navegar pelas decisoes arquiteturais | `adr/README.md` |
| Operar bandeja, retencao e transferencias | [Operacao do servidor](operations/server_and_transfers.md) |
| Configurar o auto update | [Auto update](install/auto_update_setup.md) |
| Gerar e publicar instalador | [Release](install/release_guide.md) |

## Mapa das pastas

| Pasta/arquivo | Papel |
| --- | --- |
| `install/` | Guias operacionais de instalacao, release e auto update |
| `onboarding/` | Documentacao curta para quem vai mexer no codigo |
| `adr/` | Decisoes arquiteturais aceitas (nao editar as accepted) |
| `email/` | Fluxo de notificacoes SMTP e OAuth |
| `ftp-server/` | Hardening e operacao de servidor FTP destino |
| `analise_implementacao_*.md` | Comportamento real das CLIs por banco |
| `notes/` | Runbooks manuais ainda operacionais |
| `notes/archive/` | Planos, auditorias e snapshots datados |

## Regra pratica

- Sem data no nome: referencia operacional viva (exceto ADRs, que sao
  imutaveis depois de accepted).
- Com data no nome: historico. Em `notes/` os caminhos originais de
  planos citados por ADRs sao stubs; o texto completo esta em
  `notes/archive/`.

## Fontes de verdade

Requisitos e PATH ficam somente em `requirements.md` e `path_setup.md`.
O build do instalador e descrito em [installer/README.md](../installer/README.md);
publicacao e assinatura ficam no guia de release. Os atalhos redundantes
`installer/QUICK_START.md`, `install/requirements.md` e `install/path_setup.md`
foram removidos. Os stubs de historico citados por ADRs permanecem para
preservar essas referencias.
