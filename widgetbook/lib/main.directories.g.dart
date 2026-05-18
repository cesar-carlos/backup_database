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
import 'package:widgetbook_workspace/app_text_field.dart'
    as _widgetbook_workspace_app_text_field;
import 'package:widgetbook_workspace/database_config_data_grid.dart'
    as _widgetbook_workspace_database_config_data_grid;
import 'package:widgetbook_workspace/empty_state.dart'
    as _widgetbook_workspace_empty_state;
import 'package:widgetbook_workspace/message_modal.dart'
    as _widgetbook_workspace_message_modal;
import 'package:widgetbook_workspace/password_field.dart'
    as _widgetbook_workspace_password_field;

final directories = <_widgetbook.WidgetbookNode>[
  _widgetbook.WidgetbookFolder(
    name: 'presentation',
    children: [
      _widgetbook.WidgetbookFolder(
        name: 'widgets',
        children: [
          _widgetbook.WidgetbookFolder(
            name: 'common',
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
            ],
          ),
        ],
      ),
    ],
  ),
];
