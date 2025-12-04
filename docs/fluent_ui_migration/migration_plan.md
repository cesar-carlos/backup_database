# Plano de Migração para Fluent UI

## Objetivo

Migrar todo o projeto de Material Design para Fluent UI, mantendo todas as funcionalidades e melhorando a experiência visual nativa do Windows, seguindo todas as regras de Clean Architecture e convenções do projeto.

## Estrutura da Migração

### Fase 1: Preparação e Setup

1. ✅ Criar nova branch `feature/fluent-ui-migration`
2. ✅ Criar pasta `docs/fluent_ui_migration/` para documentação da migração
3. ✅ Criar arquivo `docs/fluent_ui_migration/migration_plan.md` com plano completo detalhado
4. ✅ Criar arquivo `docs/fluent_ui_migration/step_by_step.md` com passo a passo detalhado de cada fase
5. Adicionar dependência `fluent_ui: ^4.13.0` ao `pubspec.yaml` (após outras dependências padrão)
6. Executar `flutter pub get`
7. Criar `FluentThemeData` em `lib/core/theme/app_theme.dart` mantendo estrutura atual e cores de `AppColors`

### Fase 2: Migração do Core (Tema e Navegação)

8. Atualizar `ThemeProvider` em `lib/core/theme/theme_provider.dart` para retornar `FluentThemeData` ao invés de `ThemeData`
9. Migrar `main.dart` de `MaterialApp.router` para `FluentApp.router` (importar `package:fluent_ui/fluent_ui.dart`)
10. Manter `MultiProvider` e todos os providers (não mudar estrutura de state management)
11. Migrar `MainLayout` em `lib/presentation/pages/main_layout.dart` para usar `NavigationView` do Fluent UI
12. Migrar `SideNavigation` em `lib/presentation/widgets/navigation/side_navigation.dart` para usar `NavigationView` (remover `NavigationRail`)

### Fase 3: Migração de Widgets Comuns

13. Migrar `AppCard` em `lib/presentation/widgets/common/app_card.dart` para usar `Card` do Fluent UI
14. Migrar `AppButton` em `lib/presentation/widgets/common/app_button.dart` para usar `Button` do Fluent UI
15. Migrar `AppTextField` em `lib/presentation/widgets/common/app_text_field.dart` para usar `TextBox` do Fluent UI
16. Migrar `AppDropdown` em `lib/presentation/widgets/common/app_dropdown.dart` para usar `ComboBox` do Fluent UI
17. Migrar `LoadingIndicator` em `lib/presentation/widgets/common/loading_indicator.dart` para usar `ProgressRing` do Fluent UI
18. Migrar `MessageModal` em `lib/presentation/widgets/common/message_modal.dart` para usar `ContentDialog` do Fluent UI
19. Migrar `ErrorModal` em `lib/presentation/widgets/common/error_modal.dart` para usar `ContentDialog` do Fluent UI
20. Migrar `EmptyState` em `lib/presentation/widgets/common/empty_state.dart` para usar componentes Fluent UI

### Fase 4: Migração de Páginas

#### 4.1 Páginas Simples

21. Migrar `SettingsPage` em `lib/presentation/pages/settings_page.dart`
22. Migrar `NotificationsPage` em `lib/presentation/pages/notifications_page.dart`

#### 4.2 Páginas de Listagem

23. Migrar `DestinationsPage` em `lib/presentation/pages/destinations_page.dart`
24. Migrar `SchedulesPage` em `lib/presentation/pages/schedules_page.dart`
25. Migrar `LogsPage` em `lib/presentation/pages/logs_page.dart`

#### 4.3 Páginas de Configuração

26. Migrar `SqlServerConfigPage` em `lib/presentation/pages/sql_server_config_page.dart`
27. Migrar `SybaseConfigPage` em `lib/presentation/pages/sybase_config_page.dart`
28. Migrar `DatabaseConfigPage` em `lib/presentation/pages/database_config_page.dart`

#### 4.4 Páginas Complexas

29. Migrar `DashboardPage` em `lib/presentation/pages/dashboard_page.dart`

### Fase 5: Migração de Dialogs e Modals

30. Migrar `DestinationDialog` em `lib/presentation/widgets/destinations/destination_dialog.dart`
31. Migrar `ScheduleDialog` em `lib/presentation/widgets/schedules/schedule_dialog.dart`
32. Migrar `SqlServerConfigDialog` em `lib/presentation/widgets/sql_server/sql_server_config_dialog.dart`
33. Migrar `SybaseConfigDialog` em `lib/presentation/widgets/sybase/sybase_config_dialog.dart`
34. Migrar `BackupProgressDialog` em `lib/presentation/widgets/backup/backup_progress_dialog.dart`

### Fase 6: Migração de Widgets Específicos

35. Migrar widgets de Dashboard (`StatsCard`, `RecentBackupsList`, etc.)
36. Migrar `DestinationListItem` em `lib/presentation/widgets/destinations/destination_list_item.dart`
37. Migrar `ScheduleListItem` em `lib/presentation/widgets/schedules/schedule_list_item.dart`
38. Migrar widgets de SQL Server (`SqlServerConfigListItem`, `SqlServerConfigList`)
39. Migrar widgets de Sybase (`SybaseConfigListItem`, `SybaseConfigList`)

### Fase 7: Ajustes Finais

40. Substituir Material Icons por Fluent Icons em todo o projeto
41. Ajustar cores e espaçamentos para seguir design Fluent UI
42. Testar todas as funcionalidades
43. Ajustar responsividade e layout
44. Validar tema claro e escuro

## Telas que Serão Migradas

### Páginas Principais (10)

1. `MainLayout` - Layout principal com navegação
2. `DashboardPage` - Dashboard com estatísticas
3. `DestinationsPage` - Gerenciamento de destinos
4. `SchedulesPage` - Gerenciamento de agendamentos
5. `LogsPage` - Visualização de logs
6. `NotificationsPage` - Notificações
7. `SettingsPage` - Configurações
8. `SqlServerConfigPage` - Configuração SQL Server
9. `SybaseConfigPage` - Configuração Sybase
10. `DatabaseConfigPage` - Página wrapper de configuração

### Dialogs e Modals (7)

1. `DestinationDialog` - Dialog de destino (com OAuth)
2. `ScheduleDialog` - Dialog de agendamento
3. `SqlServerConfigDialog` - Dialog de configuração SQL Server
4. `SybaseConfigDialog` - Dialog de configuração Sybase
5. `BackupProgressDialog` - Dialog de progresso
6. `MessageModal` - Modal de mensagens
7. `ErrorModal` - Modal de erros

### Widgets Customizados (16+)

1. `AppCard` - Card customizado
2. `AppButton` - Botão customizado
3. `AppTextField` - Campo de texto customizado
4. `AppDropdown` - Dropdown customizado
5. `LoadingIndicator` - Indicador de carregamento
6. `EmptyState` - Estado vazio
7. `ErrorWidget` - Widget de erro
8. `StatsCard` - Card de estatísticas
9. `RecentBackupsList` - Lista de backups recentes
10. `ScheduleStatusCard` - Card de status de agendamento
11. `DestinationListItem` - Item de lista de destino
12. `ScheduleListItem` - Item de lista de agendamento
13. `SqlServerConfigListItem` - Item de lista SQL Server
14. `SqlServerConfigList` - Lista SQL Server
15. `SybaseConfigListItem` - Item de lista Sybase
16. `SybaseConfigList` - Lista Sybase

## Mapeamento Material → Fluent UI

### Componentes Principais

- `MaterialApp` → `FluentApp`
- `Scaffold` → `ScaffoldPage` ou `NavigationView`
- `ThemeData` → `FluentThemeData`
- `NavigationRail` → `NavigationView`
- `Card` → `Card` (Fluent UI)
- `ElevatedButton` → `Button` (Fluent UI)
- `OutlinedButton` → `Button` com estilo outlined
- `TextFormField` → `TextBox`
- `DropdownButtonFormField` → `ComboBox`
- `SwitchListTile` → `ToggleSwitch` + `InfoLabel`
- `ListTile` → `ListTile` (Fluent UI) ou `InfoLabel`
- `CircularProgressIndicator` → `ProgressRing`
- `LinearProgressIndicator` → `ProgressBar`
- `AlertDialog` → `ContentDialog`
- `IconButton` → `IconButton` (Fluent UI)
- `AppBar` → `CommandBar` ou header do `NavigationView`

### Ícones

- Material Icons (`Icons.*`) → Fluent Icons (`FluentIcons.*`)

## Regras Críticas do Projeto

### 1. Clean Architecture (CRÍTICO)

- ❌ **NUNCA modificar** Domain, Application ou Infrastructure layers
- ✅ **APENAS Presentation layer** será modificada (`lib/presentation/`)
- ✅ **Core layer** pode ser modificado apenas para tema (`lib/core/theme/`)
- ✅ **Manter regras de dependência**: Presentation → Application → Domain
- ✅ **Providers** em `application/providers/` NÃO devem ser modificados
- ✅ **NUNCA importar** de `infrastructure` na presentation
- ✅ **Usar barrel files** (`core.dart`, `domain.dart`, `application.dart`, `presentation.dart`)

### 2. Dependências Padrão (Manter Todas - NÃO MUDAR)

- ✅ **go_router**: Continuar usando
- ✅ **provider**: Continuar usando (ChangeNotifierProvider, Consumer, etc.)
- ✅ **get_it**: Continuar usando para DI
- ✅ **result_dart**: Continuar usando para error handling
- ✅ **dio**: Continuar usando
- ✅ **brasil_fields**: Manter compatibilidade com `TextBox` via `TextInputFormatter`
- ✅ **zard**: Continuar usando para validação
- ✅ **uuid**: Continuar usando

### 3. Convenções de Código

**Nomenclatura:**
- Arquivos: snake_case
- Classes: PascalCase
- Variáveis/Métodos: camelCase
- Constantes: camelCase com `const` ou `static const`

**Imports (Ordem Obrigatória):**
1. Flutter/Dart
2. Pacotes externos
3. Core/Shared
4. Domain/Application
5. Relativos

**Widgets:**
- Usar `const` construtor quando possível
- Usar `super.key` em widgets
- NUNCA retornar Widget de função
- Extrair widgets grandes (>100 linhas)

**Documentação:**
- ❌ NÃO criar documentação automaticamente
- ❌ NÃO adicionar comentários desnecessários
- ✅ Código autoexplicativo

## Estratégia de Testes

Após cada fase:
- Compilar o projeto
- Testar navegação básica
- Validar funcionalidades críticas
- Verificar tema claro e escuro

## Verificações Pós-Migração

Após cada fase, verificar:
- [ ] Não há imports de `package:flutter/material.dart` na presentation
- [ ] Ordem de imports está correta
- [ ] Widgets usam `const` quando possível
- [ ] Não há violação de regras de Clean Architecture
- [ ] Providers não foram modificados
- [ ] Error handling continua usando `result_dart`
- [ ] Validação continua usando `zard`
- [ ] Navegação continua usando `go_router`

