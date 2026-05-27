import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:flutter/foundation.dart';

/// Mixin para `ChangeNotifier`s que podem disparar `notifyListeners()`
/// **depois** de o widget tree já ter chamado `dispose()` neste
/// provider.
///
/// Cenários onde isso acontece:
/// - Timer debounced que completa após a tela ser desmontada
///   (`NotificationProvider._historyReloadTimer`).
/// - `runAsync` do [AsyncStateMixin] que terminou mas o provider já
///   foi descartado pelo Provider tree.
/// - Stream subscription que emite após `dispose` mas antes do
///   `cancel` real completar (gap raro em `Stream.fromIterable`).
///
/// Sem este guard, qualquer um desses casos lançaria
/// `"A LogProvider was used after being disposed"`.
///
/// **Uso:**
/// ```dart
/// class FooProvider extends ChangeNotifier
///     with AsyncStateMixin, DisposeGuardMixin {
///   // ...
/// }
/// ```
///
/// O `notifyListeners()` vira no-op após `dispose()`; o `dispose()`
/// marca a flag e propaga `super.dispose()` normalmente.
///
/// **Por que mixin separado e não embutir em `AsyncStateMixin`?**
/// Nem todo provider precisa do guard — providers que não disparam
/// nada após `dispose()` (a maioria) não pagam o custo. E o `dispose`
/// override seria invasivo para quem já tem `dispose` próprio (ex.:
/// providers com `StreamSubscription.cancel`).
mixin DisposeGuardMixin on ChangeNotifier {
  bool _disposeGuardActive = false;

  /// Indica se `dispose()` já foi chamado neste provider.
  @protected
  bool get isDisposed => _disposeGuardActive;

  @override
  void notifyListeners() {
    if (_disposeGuardActive) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposeGuardActive = true;
    super.dispose();
  }
}
