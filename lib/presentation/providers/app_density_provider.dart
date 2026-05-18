import 'package:backup_database/core/theme/tokens/app_density.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:flutter/widgets.dart';

class InheritedAppDensity extends InheritedWidget {
  const InheritedAppDensity({
    required this.density,
    required super.child,
    super.key,
  });

  final AppDensity density;

  static AppDensity resolve(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<InheritedAppDensity>();
    return scope?.density ?? AppDensity.comfortable;
  }

  @override
  bool updateShouldNotify(InheritedAppDensity oldWidget) {
    return oldWidget.density != density;
  }
}

class AppDensityProvider extends ChangeNotifier {
  AppDensityProvider({
    required IUserPreferencesRepository userPreferencesRepository,
  }) : _userPreferences = userPreferencesRepository;

  final IUserPreferencesRepository _userPreferences;

  AppDensity _density = AppDensity.comfortable;
  bool _isInitialized = false;

  AppDensity get density => _density;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      final stored = await _userPreferences.getUiDensity();
      _density = _parseStored(stored);
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao carregar densidade da UI', e, s);
      _density = AppDensity.comfortable;
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> setDensity(AppDensity value) async {
    _density = value;
    notifyListeners();

    try {
      await _userPreferences.setUiDensity(value.name);
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao salvar densidade da UI', e, s);
    }
  }

  static AppDensity _parseStored(String? value) {
    switch (value) {
      case 'compact':
        return AppDensity.compact;
      case 'spacious':
        return AppDensity.spacious;
      case 'comfortable':
        return AppDensity.comfortable;
      default:
        return AppDensity.comfortable;
    }
  }
}
