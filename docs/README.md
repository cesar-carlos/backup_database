# Documentacao

Este diretorio mistura documentacao operacional, onboarding tecnico,
analises por banco e registros historicos. Use este indice para evitar ler
material datado como se fosse regra atual do produto.

## Comece por aqui

| Objetivo | Documento |
| --- | --- |
| Instalar e configurar a aplicacao | `install/installation_guide.md` |
| Confirmar requisitos por ambiente e banco | `requirements.md` |
| Ajustar PATH das ferramentas externas | `path_setup.md` |
| Entender a arquitetura atual | `onboarding/architecture_overview.md` |
| Navegar pelas decisoes arquiteturais | `adr/README.md` |

## Mapa das pastas

| Pasta/arquivo | Papel |
| --- | --- |
| `install/` | Guias operacionais de instalacao, release e auto update |
| `onboarding/` | Documentacao curta para quem vai mexer no codigo |
| `adr/` | Decisoes arquiteturais aceitas e seu contexto |
| `email/` | Fluxo de notificacoes SMTP e OAuth |
| `ftp-server/` | Hardening e operacao de servidor FTP |
| `analise_implementacao_*.md` | Estado real da implementacao por banco |
| `notes/` | Planos, auditorias e runbooks datados; veja `notes/README.md` |

## Regra pratica

- Documento sem data no nome: tende a ser referencia operacional viva.
- Documento com data no nome: trate como snapshot historico, plano ou
  evidencia, nao como contrato atual do produto.

## Observacao sobre `docs/install/`

Os arquivos `install/path_setup.md` e `install/requirements.md` sao atalhos
curtos para preservar links relativos do guia de instalacao dentro do
repositorio. A fonte de verdade continua sendo `docs/path_setup.md` e
`docs/requirements.md`.
