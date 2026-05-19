// dart format width=80
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_import, prefer_relative_imports, directives_ordering

// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AppGenerator
// **************************************************************************

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:widgetbook/widgetbook.dart' as _widgetbook;
import 'package:widgetbook_workspace/app_button.dart'
    as _widgetbook_workspace_app_button;
import 'package:widgetbook_workspace/app_data_grid.dart'
    as _widgetbook_workspace_app_data_grid;
import 'package:widgetbook_workspace/app_dialog_shell.dart'
    as _widgetbook_workspace_app_dialog_shell;
import 'package:widgetbook_workspace/app_page_scaffold.dart'
    as _widgetbook_workspace_app_page_scaffold;
import 'package:widgetbook_workspace/app_page_state.dart'
    as _widgetbook_workspace_app_page_state;
import 'package:widgetbook_workspace/app_section_card.dart'
    as _widgetbook_workspace_app_section_card;
import 'package:widgetbook_workspace/app_status_chip.dart'
    as _widgetbook_workspace_app_status_chip;
import 'package:widgetbook_workspace/app_text_field.dart'
    as _widgetbook_workspace_app_text_field;
import 'package:widgetbook_workspace/database_config_data_grid.dart'
    as _widgetbook_workspace_database_config_data_grid;
import 'package:widgetbook_workspace/destination_grid.dart'
    as _widgetbook_workspace_destination_grid;
import 'package:widgetbook_workspace/empty_state.dart'
    as _widgetbook_workspace_empty_state;
import 'package:widgetbook_workspace/message_modal.dart'
    as _widgetbook_workspace_message_modal;
import 'package:widgetbook_workspace/password_field.dart'
    as _widgetbook_workspace_password_field;
import 'package:widgetbook_workspace/schedule_grid.dart'
    as _widgetbook_workspace_schedule_grid;
import 'package:widgetbook_workspace/section_header_with_status_badges.dart'
    as _widgetbook_workspace_section_header_with_status_badges;

final directories = <_widgetbook.WidgetbookNode>[
  _widgetbook.WidgetbookFolder(
    name: 'presentation',
    children: [
      _widgetbook.WidgetbookFolder(
        name: 'widgets',
        children: [
          _widgetbook.WidgetbookFolder(
            name: 'atoms',
            children: [
              _widgetbook.WidgetbookComponent(
                name: 'AppButton',
                useCases: [
                  _widgetbook.WidgetbookUseCase(
                    name: 'Default',
                    builder: _widgetbook_workspace_app_button
                        .buildAppButtonDefaultUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'Disabled',
                    builder: _widgetbook_workspace_app_button
                        .buildAppButtonDisabledUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'Icon',
                    builder: _widgetbook_workspace_app_button
                        .buildAppButtonIconUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'Loading',
                    builder: _widgetbook_workspace_app_button
                        .buildAppButtonLoadingUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'Primary',
                    builder: _widgetbook_workspace_app_button
                        .buildAppButtonPrimaryUseCase,
                  ),
                ],
              ),
              _widgetbook.WidgetbookComponent(
                name: 'AppStatusChip',
                useCases: [
                  _widgetbook.WidgetbookUseCase(
                    name: 'Accent tag',
                    builder: _widgetbook_workspace_app_status_chip
                        .buildAppStatusChipAccentUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'Semantic tones',
                    builder: _widgetbook_workspace_app_status_chip
                        .buildAppStatusChipSemanticUseCase,
                  ),
                ],
              ),
              _widgetbook.WidgetbookComponent(
                name: 'AppTextField',
                useCases: [
                  _widgetbook.WidgetbookUseCase(
                    name: 'Default',
                    builder: _widgetbook_workspace_app_text_field
                        .buildAppTextFieldDefaultUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'Disabled',
                    builder: _widgetbook_workspace_app_text_field
                        .buildAppTextFieldDisabledUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'Error',
                    builder: _widgetbook_workspace_app_text_field
                        .buildAppTextFieldErrorUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'Focused',
                    builder: _widgetbook_workspace_app_text_field
                        .buildAppTextFieldFocusedUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'Knobs',
                    builder: _widgetbook_workspace_app_text_field
                        .buildAppTextFieldKnobsUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'Prefix suffix',
                    builder: _widgetbook_workspace_app_text_field
                        .buildAppTextFieldPrefixSuffixUseCase,
                  ),
                ],
              ),
              _widgetbook.WidgetbookComponent(
                name: 'EmptyState',
                useCases: [
                  _widgetbook.WidgetbookUseCase(
                    name: 'Message only',
                    builder: _widgetbook_workspace_empty_state
                        .buildEmptyStateMessageOnlyUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'With action',
                    builder: _widgetbook_workspace_empty_state
                        .buildEmptyStateWithActionUseCase,
                  ),
                ],
              ),
            ],
          ),
          _widgetbook.WidgetbookFolder(
            name: 'destinations',
            children: [
              _widgetbook.WidgetbookComponent(
                name: 'DestinationGrid',
                useCases: [
                  _widgetbook.WidgetbookUseCase(
                    name: 'Default',
                    builder: _widgetbook_workspace_destination_grid
                        .buildDestinationGridUseCase,
                  ),
                ],
              ),
            ],
          ),
          _widgetbook.WidgetbookFolder(
            name: 'molecules',
            children: [
              _widgetbook.WidgetbookComponent(
                name: 'PasswordField',
                useCases: [
                  _widgetbook.WidgetbookUseCase(
                    name: 'Default',
                    builder: _widgetbook_workspace_password_field
                        .buildPasswordFieldDefaultUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'Disabled',
                    builder: _widgetbook_workspace_password_field
                        .buildPasswordFieldDisabledUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'Validation error',
                    builder: _widgetbook_workspace_password_field
                        .buildPasswordFieldValidationUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'With value',
                    builder: _widgetbook_workspace_password_field
                        .buildPasswordFieldWithValueUseCase,
                  ),
                ],
              ),
              _widgetbook.WidgetbookComponent(
                name: 'SectionHeaderWithStatusBadges',
                useCases: [
                  _widgetbook.WidgetbookUseCase(
                    name: 'With active and inactive',
                    builder:
                        _widgetbook_workspace_section_header_with_status_badges
                            .buildSectionHeaderWithStatusBadgesDefaultUseCase,
                  ),
                ],
              ),
            ],
          ),
          _widgetbook.WidgetbookFolder(
            name: 'organisms',
            children: [
              _widgetbook.WidgetbookComponent(
                name: 'AppDataGrid',
                useCases: [
                  _widgetbook.WidgetbookUseCase(
                    name: 'Default',
                    builder: _widgetbook_workspace_app_data_grid
                        .buildAppDataGridDefaultUseCase,
                  ),
                ],
              ),
              _widgetbook.WidgetbookComponent(
                name: 'AppDialogShell',
                useCases: [
                  _widgetbook.WidgetbookUseCase(
                    name: 'Default',
                    builder: _widgetbook_workspace_app_dialog_shell
                        .buildAppDialogShellDefaultUseCase,
                  ),
                ],
              ),
              _widgetbook.WidgetbookComponent(
                name: 'AppPageScaffold',
                useCases: [
                  _widgetbook.WidgetbookUseCase(
                    name: 'Default',
                    builder: _widgetbook_workspace_app_page_scaffold
                        .buildAppPageScaffoldDefaultUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'With header message',
                    builder: _widgetbook_workspace_app_page_scaffold
                        .buildAppPageScaffoldWithBannerUseCase,
                  ),
                ],
              ),
              _widgetbook.WidgetbookComponent(
                name: 'AppPageState',
                useCases: [
                  _widgetbook.WidgetbookUseCase(
                    name: 'Empty',
                    builder: _widgetbook_workspace_app_page_state
                        .buildAppPageStateEmptyUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'Error',
                    builder: _widgetbook_workspace_app_page_state
                        .buildAppPageStateErrorUseCase,
                  ),
                ],
              ),
              _widgetbook.WidgetbookComponent(
                name: 'AppSectionCard',
                useCases: [
                  _widgetbook.WidgetbookUseCase(
                    name: 'Default',
                    builder: _widgetbook_workspace_app_section_card
                        .buildAppSectionCardDefaultUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'With banner and footer',
                    builder: _widgetbook_workspace_app_section_card
                        .buildAppSectionCardFullUseCase,
                  ),
                ],
              ),
              _widgetbook.WidgetbookComponent(
                name: 'DatabaseConfigDataGrid',
                useCases: [
                  _widgetbook.WidgetbookUseCase(
                    name: 'Empty',
                    builder: _widgetbook_workspace_database_config_data_grid
                        .buildDatabaseConfigDataGridEmptyUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'Empty with add',
                    builder: _widgetbook_workspace_database_config_data_grid
                        .buildDatabaseConfigDataGridEmptyWithAddUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'With last test column',
                    builder: _widgetbook_workspace_database_config_data_grid
                        .buildDatabaseConfigDataGridWithTestColumnUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'With rows',
                    builder: _widgetbook_workspace_database_config_data_grid
                        .buildDatabaseConfigDataGridWithRowsUseCase,
                  ),
                ],
              ),
              _widgetbook.WidgetbookComponent(
                name: 'MessageModal',
                useCases: [
                  _widgetbook.WidgetbookUseCase(
                    name: 'Custom button',
                    builder: _widgetbook_workspace_message_modal
                        .buildMessageModalCustomButtonUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'Error',
                    builder: _widgetbook_workspace_message_modal
                        .buildMessageModalErrorUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'Info',
                    builder: _widgetbook_workspace_message_modal
                        .buildMessageModalInfoUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'Success',
                    builder: _widgetbook_workspace_message_modal
                        .buildMessageModalSuccessUseCase,
                  ),
                  _widgetbook.WidgetbookUseCase(
                    name: 'Warning',
                    builder: _widgetbook_workspace_message_modal
                        .buildMessageModalWarningUseCase,
                  ),
                ],
              ),
            ],
          ),
          _widgetbook.WidgetbookFolder(
            name: 'schedules',
            children: [
              _widgetbook.WidgetbookComponent(
                name: 'ScheduleGrid',
                useCases: [
                  _widgetbook.WidgetbookUseCase(
                    name: 'Default',
                    builder: _widgetbook_workspace_schedule_grid
                        .buildScheduleGridUseCase,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  ),
];
