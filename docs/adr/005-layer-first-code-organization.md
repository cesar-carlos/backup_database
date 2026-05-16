# ADR-005: Manter organizacao do codigo por camada (layer-first)

- Status: accepted
- Data: 2026-05-15
- Decisores: time do produto (app desktop backup_database)
- Contexto relacionado:
  `docs/notes/plano_refatoracao_e_melhorias_2026-04-19.md` (secao 3.2.1,
  roadmap M4 / M7)

## Contexto

A literatura e templates 2026 tendem a recomendar **feature-first**
(pastas por funcionalidade) para aplicacoes que crescem com muitas
features ortogonais. O repositorio hoje segue **layer-first**:
`lib/domain`, `lib/application`, `lib/infrastructure`, `lib/presentation`,
`lib/core`, alinhado a Clean Architecture documentada nas regras do
projeto.

Sem decisao registrada, debates de PR podem oscilar entre migrar tudo
para feature-first (alto custo de churn em imports) versus manter o
layout atual.

## Decisao

**Manter a organizacao por camadas (layer-first)** como padrao oficial
do codigo de producao (`lib/`). Nao iniciar migracao massiva para
feature-first neste ciclo de vida do produto.

Reavaliar somente se surgirem **3+ dominios de produto claramente
ortogonais** (ex.: modulo de licenciamento, analytics, auditoria) com
times maiores e necessidade de isolamento por pacote, conforme gatilhos
ja descritos no plano de refatoracao (M7).

## Consequencias

### Positivas

- Zero churn de imports e paths de ferramentas (analyzer, testes,
  geradores) por uma reorganizacao grande.
- Continuidade com `clean_architecture.mdc` e limites de dependencia ja
  internalizados pelo time.
- Onboarding continua linear para quem ja conhece Clean Architecture.

### Negativas

- Navegar uma "feature" ponta-a-ponta exige saltar entre pastas de
  camada em vez de abrir um unico diretorio de feature.
- Novos membros acostumados apenas com feature-first precisam do mapa
  mental layer-first.

### Neutras

- E possivel evoluir **subpastas por feature dentro de presentation**
  (ja existe `widgets/sql_server/`, etc.) sem mudar o contrato global
  layer-first.

## Alternativas consideradas

### Opcao A: Migracao completa para feature-first

- Descricao: mover `lib/domain`, `lib/application`, etc. para arvores
  por feature (`lib/features/backup/...`).
- Por que nao foi escolhida: custo de migracao alto para este produto
  (single feature principal de backup), ROI moderado; risco de
  regressao em imports e CI.

### Opcao B: Hibrido formal (dominio layer-first, UI feature-first)

- Descricao: manter domain/application em camadas; apenas presentation
  em feature-first.
- Por que nao foi escolhida agora: ainda implica convencao dupla e
  fronteira a documentar; pode ser revisitada em ADR futuro se a UI
  explodir em modulos independentes.

## Notas de implementacao

- Novos modulos devem continuar respeitando **limites de camada** antes
  de discutir local da pasta dentro da camada.
- Se um dia M7 for acionado, criar **novo ADR** (`superseded by` ou
  `supersedes ADR-005`) em vez de editar este registro aceito.
