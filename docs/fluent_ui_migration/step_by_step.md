# Passo a Passo da Migração para Fluent UI

Este documento detalha cada passo da migração, com exemplos de código e verificações.

## Fase 1: Preparação e Setup

### Passo 1.1: Criar Branch

```bash
git checkout -b feature/fluent-ui-migration
```

✅ Branch criada

### Passo 1.2: Criar Estrutura de Documentação

```bash
mkdir docs/fluent_ui_migration
```

✅ Pasta criada

### Passo 1.3: Adicionar Dependência

Adicionar `fluent_ui: ^4.13.0` ao `pubspec.yaml` após `result_dart`.

**Arquivo:** `pubspec.yaml`

```yaml
# Result Pattern (Error Handling)
result_dart: ^2.1.1

# Fluent UI
fluent_ui: ^4.13.0
# Controle de Janelas
```

### Passo 1.4: Instalar Dependências

```bash
flutter pub get
```

### Passo 1.5: Criar FluentThemeData

Criar métodos `lightFluentTheme` e `darkFluentTheme` em `lib/core/theme/app_theme.dart`.

**Estrutura:**

- Manter `AppColors` existente
- Criar `FluentThemeData` baseado nas cores atuais
- Mapear `AppColors.primary` para `accentColor`

## Fase 2: Migração do Core (Tema e Navegação)

### Passo 2.1: Atualizar ThemeProvider

**Arquivo:** `lib/core/theme/theme_provider.dart`

- Manter lógica de `isDarkMode`
- Não precisa mudar muito, apenas garantir compatibilidade

### Passo 2.2: Migrar main.dart

**Arquivo:** `lib/main.dart`

**Mudanças:**

- Importar `package:fluent_ui/fluent_ui.dart`
- Substituir `MaterialApp.router` por `FluentApp.router`
- Manter `MultiProvider` e todos os providers
- Usar `FluentThemeData` ao invés de `ThemeData`

**Antes:**

```dart
import 'package:flutter/material.dart';

MaterialApp.router(
  theme: AppTheme.lightTheme,
  darkTheme: AppTheme.darkTheme,
  routerConfig: appRouter,
)
```

**Depois:**

```dart
import 'package:fluent_ui/fluent_ui.dart';

FluentApp.router(
  theme: AppTheme.lightFluentTheme,
  darkTheme: AppTheme.darkFluentTheme,
  routerConfig: appRouter,
)
```

### Passo 2.3: Migrar MainLayout

**Arquivo:** `lib/presentation/pages/main_layout.dart`

**Mudanças:**

- Substituir `Scaffold` por `NavigationView`
- `NavigationView` já inclui navegação lateral, não precisa de `NavigationRail` separado
- Usar `pane` do `NavigationView` para navegação

**Estrutura:**

```dart
NavigationView(
  pane: NavigationPane(
    selected: _selectedIndex,
    onChanged: (index) => _onDestinationSelected(index),
    items: _navigationItems.map(...).toList(),
  ),
  content: NavigationBody(
    index: _selectedIndex,
    children: [
      // Páginas aqui
    ],
  ),
)
```

### Passo 2.4: Migrar SideNavigation

**Arquivo:** `lib/presentation/widgets/navigation/side_navigation.dart`

- Remover `NavigationRail`
- Integrar com `NavigationView` do MainLayout
- Pode ser removido se `NavigationView` substituir completamente

## Fase 3: Migração de Widgets Comuns

### Passo 3.1: AppCard

**Arquivo:** `lib/presentation/widgets/common/app_card.dart`

**Mudanças:**

- Importar `package:fluent_ui/fluent_ui.dart`
- Substituir `Card` do Material por `Card` do Fluent UI
- Ajustar propriedades (Fluent UI usa propriedades diferentes)

**Antes:**

```dart
Card(
  margin: margin,
  child: Padding(...),
)
```

**Depois:**

```dart
Card(
  padding: padding ?? const EdgeInsets.all(16),
  child: child,
)
```

### Passo 3.2: AppButton

**Arquivo:** `lib/presentation/widgets/common/app_button.dart`

**Mudanças:**

- Substituir `ElevatedButton` por `Button`
- Substituir `OutlinedButton` por `Button` com estilo outlined
- Manter lógica de `isLoading` e `isPrimary`

**Antes:**

```dart
ElevatedButton(
  onPressed: onPressed,
  child: Text(label),
)
```

**Depois:**

```dart
Button(
  onPressed: onPressed,
  child: Text(label),
)
```

### Passo 3.3: AppTextField

**Arquivo:** `lib/presentation/widgets/common/app_text_field.dart`

**Mudanças:**

- Substituir `TextFormField` por `TextBox`
- Manter validação e formatters
- Ajustar propriedades (Fluent UI usa `header` ao invés de `labelText`)

**Antes:**

```dart
TextFormField(
  controller: controller,
  decoration: InputDecoration(
    labelText: label,
    hintText: hint,
  ),
)
```

**Depois:**

```dart
TextBox(
  controller: controller,
  header: label,
  placeholder: hint,
)
```

### Passo 3.4: AppDropdown

**Arquivo:** `lib/presentation/widgets/common/app_dropdown.dart`

**Mudanças:**

- Substituir `DropdownButtonFormField` por `ComboBox`
- Ajustar propriedades

### Passo 3.5: LoadingIndicator

**Arquivo:** `lib/presentation/widgets/common/loading_indicator.dart`

**Mudanças:**

- Substituir `CircularProgressIndicator` por `ProgressRing`

### Passo 3.6: MessageModal e ErrorModal

**Arquivos:**

- `lib/presentation/widgets/common/message_modal.dart`
- `lib/presentation/widgets/common/error_modal.dart`

**Mudanças:**

- Substituir `AlertDialog` por `ContentDialog`
- Manter métodos estáticos (`show`, `showSuccess`, etc.)
- Ajustar estrutura (Fluent UI usa `actions` diferente)

**Antes:**

```dart
AlertDialog(
  title: Text(title),
  content: Text(message),
  actions: [
    ElevatedButton(...),
  ],
)
```

**Depois:**

```dart
ContentDialog(
  title: Text(title),
  content: Text(message),
  actions: [
    Button(
      child: Text('OK'),
      onPressed: () => Navigator.of(context).pop(),
    ),
  ],
)
```

### Passo 3.7: EmptyState

**Arquivo:** `lib/presentation/widgets/common/empty_state.dart`

**Mudanças:**

- Usar `InfoLabel` e `Icon` do Fluent UI
- Ajustar layout

## Fase 4: Migração de Páginas ✅ CONCLUÍDA

### Passo 4.1: SettingsPage ✅

**Arquivo:** `lib/presentation/pages/settings_page.dart`

**Mudanças:**

- Substituir `Scaffold` por `ScaffoldPage`
- Substituir `SwitchListTile` por `ToggleSwitch` + `InfoLabel`
- Manter `Provider` e toda lógica de negócio

**Antes:**

```dart
SwitchListTile(
  title: Text('Tema Escuro'),
  value: themeProvider.isDarkMode,
  onChanged: (value) => themeProvider.setDarkMode(value),
)
```

**Depois:**

```dart
InfoLabel(
  label: 'Tema Escuro',
  child: ToggleSwitch(
    checked: themeProvider.isDarkMode,
    onChanged: (value) => themeProvider.setDarkMode(value),
  ),
)
```

### Passo 4.2: NotificationsPage ✅

**Arquivo:** `lib/presentation/pages/notifications_page.dart`

**Mudanças:**

- Substituir widgets Material por Fluent UI
- Manter lógica de negócio

### Passo 4.3: DestinationsPage ✅

**Arquivo:** `lib/presentation/pages/destinations_page.dart`

**Mudanças:**

- Substituir `Scaffold` por `ScaffoldPage`
- Substituir `ListTile` por `ListTile` do Fluent UI ou `InfoLabel`
- Manter `Provider` e lógica

### Passo 4.4: SchedulesPage ✅

**Arquivo:** `lib/presentation/pages/schedules_page.dart`

**Mudanças:**

- Similar ao DestinationsPage
- Manter dialogs e lógica

### Passo 4.5: LogsPage ✅

**Arquivo:** `lib/presentation/pages/logs_page.dart`

**Mudanças:**

- Substituir widgets Material
- Manter filtros e lógica

### Passo 4.6: SqlServerConfigPage ✅ e SybaseConfigPage ✅

**Arquivos:**

- `lib/presentation/pages/sql_server_config_page.dart`
- `lib/presentation/pages/sybase_config_page.dart`

**Mudanças:**

- Similar às outras páginas de listagem
- Manter dialogs de configuração

### Passo 4.7: DatabaseConfigPage ✅

**Arquivo:** `lib/presentation/pages/database_config_page.dart`

**Mudanças:**

- Página wrapper, ajustar conforme necessário

### Passo 4.8: DashboardPage ✅

**Arquivo:** `lib/presentation/pages/dashboard_page.dart`

**Mudanças:**

- Substituir todos os widgets Material
- Manter `Consumer` e lógica de `DashboardProvider`
- Migrar widgets específicos (StatsCard, RecentBackupsList, etc.)

## Fase 5: Migração de Dialogs ✅ CONCLUÍDA

### Passo 5.1: DestinationDialog ✅

**Arquivo:** `lib/presentation/widgets/destinations/destination_dialog.dart`

**Mudanças:**

- Substituir `AlertDialog` por `ContentDialog`
- Manter lógica de OAuth e validação
- Ajustar formulários internos

### Passo 5.2: ScheduleDialog ✅

**Arquivo:** `lib/presentation/widgets/schedules/schedule_dialog.dart`

**Mudanças:**

- Substituir `AlertDialog` e `TabBar` por componentes Fluent UI
- Usar `TabView` do Fluent UI

### Passo 5.3: ConfigDialogs ✅

**Arquivos:**

- `lib/presentation/widgets/sql_server/sql_server_config_dialog.dart`
- `lib/presentation/widgets/sybase/sybase_config_dialog.dart`

**Mudanças:**

- Substituir `AlertDialog` por `ContentDialog`
- Manter formulários e validação

### Passo 5.4: BackupProgressDialog ✅

**Arquivo:** `lib/presentation/widgets/backup/backup_progress_dialog.dart`

**Mudanças:**

- Substituir `AlertDialog` por `ContentDialog`
- Substituir `CircularProgressIndicator` por `ProgressRing`
- Manter lógica de progresso

## Fase 6: Migração de Widgets Específicos

### Passo 6.1: Widgets de Dashboard

**Arquivos:**

- `lib/presentation/widgets/dashboard/stats_card.dart`
- `lib/presentation/widgets/dashboard/recent_backups_list.dart`
- `lib/presentation/widgets/dashboard/schedule_status_card.dart`

**Mudanças:**

- Substituir widgets Material por Fluent UI
- Manter lógica e dados

### Passo 6.2: ListItems

**Arquivos:**

- `lib/presentation/widgets/destinations/destination_list_item.dart`
- `lib/presentation/widgets/schedules/schedule_list_item.dart`
- `lib/presentation/widgets/sql_server/sql_server_config_list_item.dart`
- `lib/presentation/widgets/sybase/sybase_config_list_item.dart`

**Mudanças:**

- Substituir `ListTile` por `ListTile` do Fluent UI
- Ajustar layout e ações

### Passo 6.3: Lists

**Arquivos:**

- `lib/presentation/widgets/sql_server/sql_server_config_list.dart`
- `lib/presentation/widgets/sybase/sybase_config_list.dart`

**Mudanças:**

- Ajustar listas para usar widgets Fluent UI

## Fase 7: Ajustes Finais

### Passo 7.1: Substituir Ícones

**Comando:**

```bash
# Encontrar todos os usos de Material Icons
grep -r "Icons\." lib/presentation/
```

**Substituições comuns:**

- `Icons.add` → `FluentIcons.add`
- `Icons.edit` → `FluentIcons.edit`
- `Icons.delete` → `FluentIcons.delete`
- `Icons.refresh` → `FluentIcons.arrow_sync`
- `Icons.settings` → `FluentIcons.settings`
- `Icons.dashboard` → `FluentIcons.view_dashboard`

### Passo 7.2: Ajustar Cores

**Arquivo:** `lib/core/theme/app_colors.dart`

- Manter cores existentes
- Ajustar apenas se necessário para seguir guidelines Fluent UI

### Passo 7.3: Ajustar Espaçamentos

- Revisar padding e margin em todos os widgets
- Fluent UI geralmente usa espaçamentos menores
- Usar constantes do Fluent UI quando disponível

### Passo 7.4: Testes

- Compilar o projeto
- Testar navegação
- Testar todas as funcionalidades
- Validar tema claro e escuro
- Verificar que não há erros de compilação

### Passo 7.5: Verificações Finais

- [ ] Não há imports de `package:flutter/material.dart` na presentation
- [ ] Ordem de imports está correta
- [ ] Widgets usam `const` quando possível
- [ ] Não há violação de Clean Architecture
- [ ] Providers não foram modificados
- [ ] Error handling continua usando `result_dart`
- [ ] Validação continua usando `zard`
- [ ] Navegação continua usando `go_router`

## Comandos Úteis

### Encontrar todos os usos de Material

```bash
grep -r "package:flutter/material.dart" lib/presentation/
```

### Encontrar todos os usos de Icons

```bash
grep -r "Icons\." lib/presentation/
```

### Verificar imports incorretos

```bash
grep -r "package:infrastructure" lib/presentation/
```

### Compilar e verificar erros

```bash
flutter analyze
flutter build windows
```

## Notas Importantes

1. **Sempre manter a lógica de negócio**: Apenas widgets devem ser modificados, não a lógica
2. **Testar após cada fase**: Não esperar até o final para testar
3. **Manter compatibilidade**: Garantir que todas as funcionalidades continuam funcionando
4. **Seguir regras do projeto**: Clean Architecture, convenções, dependências padrão
5. **Documentar problemas**: Se encontrar algum problema, documentar em comentários (apenas se necessário)
