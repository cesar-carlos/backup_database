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

## Observacao sobre `docs/install/`

`install/path_setup.md` e `install/requirements.md` sao atalhos para
preservar links relativos do guia de instalacao. A fonte de verdade e
`docs/path_setup.md` e `docs/requirements.md`.
