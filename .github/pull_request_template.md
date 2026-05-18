## Summary

<!-- 1–3 bullets: o que mudou e por que. -->

## Test plan

- [ ] `flutter test` (ou subset relevante) passou localmente
- [ ] `flutter analyze` sem novos issues introduzidos pelo PR

## Accessibility (M12 / ADR-012)

Marque o que se aplica; se N/A, explique em uma linha no comentario do PR.

- [ ] **UI**: mudanca nao introduz overflow obvio com texto maior (se tocou em layout, rode testes de `textScaler` existentes ou adicione cobertura)
- [ ] **Contraste**: textos novos/alterados usam tema (`AppSemanticColors` / tipografia do tema), sem cores literais soltas para texto sobre fundo
- [ ] **Alvos**: acoes clicaveis novas respeitam `AppTargetSize` onde couber (minimo confortavel 48px para controles densos)
- [ ] **Semantica**: botoes so-icone tem `Semantics`/`Tooltip` com rotulo; icones puramente decorativos ao lado de texto nao duplicam leitura (`ExcludeSemantics` quando aplicavel)
- [ ] **Teclado**: fluxo tocado continua navegavel por Tab e acionavel (Enter/Esc em modais)

## SGBD / arquitetura (PR-E e refactors)

Se o PR toca em config, backup ou DI de SGBD, inclua o benchmark abaixo.

Regenerar tabela (snapshot atual de `lib/`):

```bash
dart run tools/sgbd_loc_report.dart --markdown
```

Diff vs branch base (linhas alteradas por camada):

```bash
git fetch origin
git diff --stat origin/main...HEAD -- \
  lib/domain lib/application lib/infrastructure lib/presentation
```

Por SGBD (opcional):

```bash
git diff --stat origin/main...HEAD -- 'lib/**/*sql_server*' 'lib/**/*postgres*' 'lib/**/*sybase*' 'lib/**/*firebird*'
```

<!-- Cole aqui a tabela markdown gerada e, se houver baseline, linhas eliminadas vs main. -->

## Risk / rollout

<!-- Opcional: migracao, compatibilidade, feature flags. -->
