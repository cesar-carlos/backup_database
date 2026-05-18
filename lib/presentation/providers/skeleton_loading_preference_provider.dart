import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:flutter/foundation.dart';

class SkeletonLoadingPreferenceProvider extends ChangeNotifier {
  SkeletonLoadingPreferenceProvider({
    required IUserPreferencesRepository userPreferencesRepository,
  }) : _userPreferencesRepository = userPreferencesRepository;

  final IUserPreferencesRepository _userPreferencesRepository;

  bool _shimmerLoadingEffectsEnabled = true;

  bool get shimmerLoadingEffectsEnabled => _shimmerLoadingEffectsEnabled;

  Future<void> initialize() async {
    _shimmerLoadingEffectsEnabled = await _userPreferencesRepository
        .getSkeletonLoadingEnabled();
    notifyListeners();
  }

  Future<void> setShimmerLoadingEffectsEnabled(bool value) async {
    _shimmerLoadingEffectsEnabled = value;
    notifyListeners();
    await _userPreferencesRepository.setSkeletonLoadingEnabled(value);
  }
}
