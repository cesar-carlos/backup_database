import 'package:backup_database/domain/entities/schedule.dart';
import 'package:fluent_ui/fluent_ui.dart';

class WidgetTexts {
  const WidgetTexts._({
    required this.cancel,
    required this.save,
    required this.create,
    required this.retry,
    required this.selectPrefix,
    required this.ok,
    required this.success,
    required this.information,
    required this.attention,
    required this.error,
    required this.deletionBlockedByDependencies,
    required this.goToSchedules,
    required this.active,
    required this.inactive,
    required this.nextRunLabel,
    required this.lastRunLabel,
    required this.scheduleLabel,
    required this.typeLabel,
    required this.statusLabel,
  });

  final String cancel;
  final String save;
  final String create;
  final String retry;
  final String selectPrefix;
  final String ok;
  final String success;
  final String information;
  final String attention;
  final String error;
  final String deletionBlockedByDependencies;
  final String goToSchedules;
  final String active;
  final String inactive;
  final String nextRunLabel;
  final String lastRunLabel;
  final String scheduleLabel;
  final String typeLabel;
  final String statusLabel;

  factory WidgetTexts.fromContext(BuildContext context) {
    return WidgetTexts.fromLocale(Localizations.localeOf(context));
  }

  factory WidgetTexts.fromLocale(Locale locale) {
    final language = locale.languageCode.toLowerCase();
    if (language == 'pt') {
      return const WidgetTexts._(
        cancel: 'Cancelar',
        save: 'Salvar',
        create: 'Criar',
        retry: 'Tentar novamente',
        selectPrefix: 'Selecione',
        ok: 'OK',
        success: 'Sucesso',
        information: 'Informação',
        attention: 'Atenção',
        error: 'Erro',
        deletionBlockedByDependencies: 'Exclusão bloqueada por dependências',
        goToSchedules: 'Ir para Agendamentos',
        active: 'Ativo',
        inactive: 'Desativado',
        nextRunLabel: 'Próxima execução',
        lastRunLabel: 'Última execução',
        scheduleLabel: 'Agendamento',
        typeLabel: 'Tipo',
        statusLabel: 'Status',
      );
    }

    return const WidgetTexts._(
      cancel: 'Cancel',
      save: 'Save',
      create: 'Create',
      retry: 'Try again',
      selectPrefix: 'Select',
      ok: 'OK',
      success: 'Success',
      information: 'Information',
      attention: 'Attention',
      error: 'Error',
      deletionBlockedByDependencies: 'Deletion blocked by dependencies',
      goToSchedules: 'Go to Schedules',
      active: 'Active',
      inactive: 'Disabled',
      nextRunLabel: 'Next run',
      lastRunLabel: 'Last run',
      scheduleLabel: 'Schedule',
      typeLabel: 'Type',
      statusLabel: 'Status',
    );
  }

  String select(String label) => '$selectPrefix $label';

  String scheduleTypeName(ScheduleType type) {
    switch (type) {
      case ScheduleType.daily:
        return _daily;
      case ScheduleType.weekly:
        return _weekly;
      case ScheduleType.monthly:
        return _monthly;
      case ScheduleType.interval:
        return _interval;
    }
  }

  String get _daily => _isPt ? 'Diário' : 'Daily';
  String get _weekly => _isPt ? 'Semanal' : 'Weekly';
  String get _monthly => _isPt ? 'Mensal' : 'Monthly';
  String get _interval => _isPt ? 'Intervalo' : 'Interval';

  bool get _isPt => cancel == 'Cancelar';
}
