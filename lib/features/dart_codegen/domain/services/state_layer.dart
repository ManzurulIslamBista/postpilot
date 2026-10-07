/// The state-management style of the generated presentation layer, for the API layer (one class set per use-case
/// group) and for the Odoo client (one per model).
enum StateLayerStyle {
  none('None', 'No state classes: call the repositories from your own view models'),
  provider('Provider', 'ChangeNotifier view models (package: provider)'),
  riverpod('Riverpod', 'Notifier / AsyncNotifier and providers, no code generation (package: flutter_riverpod)'),
  bloc('BLoC', 'Cubits with sealed states (package: flutter_bloc)');

  final String label;
  final String description;
  const StateLayerStyle(this.label, this.description);

  /// The command that adds the package the generated files import. No version number is written on purpose: the
  /// project's own constraints and `pub` decide it.
  String? get dependencyCommand => switch (this) {
        StateLayerStyle.none => null,
        StateLayerStyle.provider => 'dart pub add provider',
        StateLayerStyle.riverpod => 'dart pub add flutter_riverpod',
        StateLayerStyle.bloc => 'dart pub add flutter_bloc',
      };

  /// Names a generated file takes from the state package (it imports them with `show`). A model class must not be
  /// called any of them.
  Set<String> get importedNames => switch (this) {
        StateLayerStyle.none => const {},
        StateLayerStyle.provider => const {'ChangeNotifier'},
        StateLayerStyle.riverpod => const {'AsyncNotifier', 'AsyncNotifierProvider', 'AsyncValue', 'AsyncData', 'AsyncLoading', 'Provider'},
        StateLayerStyle.bloc => const {'Cubit'},
      };

  /// The call-state types the shared `call_state.dart` declares (Provider and BLoC use them; Riverpod has `AsyncValue`).
  static const callStateNames = {'CallState', 'CallIdle', 'CallLoading', 'CallSuccess', 'CallFailure'};

  /// The names every model class of a layer with this style must avoid.
  Set<String> get reservedNames => this == StateLayerStyle.none ? const {} : {...importedNames, ...callStateNames};
}
