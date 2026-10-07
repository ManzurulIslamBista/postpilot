import '../entities/generated_file.dart';
import 'dart_names.dart';
import 'state_layer.dart';

/// One call of a group, reduced to what the state classes need: they forward to the repository (or data source) method
/// of the same name, so its parameters are passed through as written.
final class StateOperation {
  /// The method name on the repository.
  final String name;

  /// A PascalCase name unique over the whole layer (`ListUsers`, `UsersGetAll`): the class names are built from it.
  final String stem;
  final String title;

  /// `GET /users`, for the comments.
  final String request;

  /// The named-parameter block of the method (`{required String id, String? page}`), or an empty string.
  final String signature;

  /// How the method is called with those parameters (`id: id, page: page`).
  final String callArguments;
  final String resultType;

  /// A call that changes something on the server (anything but GET). Reads can be repeated with `refresh`.
  final bool isAction;

  const StateOperation({
    required this.name,
    required this.stem,
    required this.title,
    required this.request,
    required this.signature,
    required this.callArguments,
    required this.resultType,
    required this.isAction,
  });
}

/// The calls of one use-case group (a folder of the collection).
final class StateGroup {
  final String name;

  /// What the state classes call: `UsersRepository`, or `UsersRemoteDataSource` without the domain layer.
  final String sourceType;

  /// Complete `import '...';` lines for [sourceType] and every DTO the operations name.
  final List<String> imports;
  final List<StateOperation> operations;

  const StateGroup({required this.name, required this.sourceType, required this.imports, required this.operations});
}

/// Writes the presentation layer of a generated API layer in the chosen state-management style: per group a
/// `ChangeNotifier` view model (Provider), `AsyncNotifier`s with providers (Riverpod) or `Cubit`s (BLoC). Every call keeps
/// its own loading / data / error, the previous data stays while a call repeats, and a late answer of an older call
/// never replaces a newer one.
final class StateLayerGenerator {
  const StateLayerGenerator();

  static const callStatePath = 'lib/core/state/call_state.dart';

  /// Files every group of the layer shares. A project that already has one keeps its own.
  List<GeneratedFile> sharedFiles(StateLayerStyle style) => switch (style) {
        StateLayerStyle.provider || StateLayerStyle.bloc => const [GeneratedFile(callStatePath, _callState, shared: true)],
        _ => const [],
      };

  /// The file for [group]: its path depends on the style.
  GeneratedFile group(StateGroup group, {required StateLayerStyle style, required String feature, required String packageName}) {
    final snake = DartNames.snake(group.name);
    final base = 'lib/features/$feature/presentation';
    return switch (style) {
      StateLayerStyle.provider => GeneratedFile('$base/view_models/${snake}_view_model.dart', _provider(group, packageName)),
      StateLayerStyle.riverpod => GeneratedFile('$base/providers/${snake}_providers.dart', _riverpod(group)),
      StateLayerStyle.bloc => GeneratedFile('$base/cubits/${snake}_cubits.dart', _bloc(group, packageName)),
      StateLayerStyle.none => throw ArgumentError('There is no state layer to generate for StateLayerStyle.none'),
    };
  }

  /// A short line per style for the generation notes: what to add to pubspec and how to hook the classes up.
  String usageNote(StateLayerStyle style, StateGroup? sample) {
    final op = sample?.operations.firstOrNull;
    final view = sample == null ? 'Users' : DartNames.pascal(sample.name);
    final source = sample?.sourceType ?? 'UsersRepository';
    final call = op?.name ?? 'listUsers';
    return switch (style) {
      StateLayerStyle.none => '',
      StateLayerStyle.provider =>
        'State layer (Provider): run `${style.dependencyCommand}`, then ChangeNotifierProvider(create: (_) => ${view}ViewModel(GetIt.I<$source>())) '
            'and read context.watch<${view}ViewModel>().${call}State.',
      StateLayerStyle.riverpod =>
        'State layer (Riverpod): run `${style.dependencyCommand}`, wrap the app in ProviderScope, then ref.watch(${_lower(op?.stem ?? 'ListUsers')}Provider) '
            'and call ref.read(${_lower(op?.stem ?? 'ListUsers')}Provider.notifier).run().',
      StateLayerStyle.bloc =>
        'State layer (BLoC): run `${style.dependencyCommand}`, then BlocProvider(create: (_) => ${op?.stem ?? 'ListUsers'}Cubit(GetIt.I<$source>())..run()) '
            'and read context.watch<${op?.stem ?? 'ListUsers'}Cubit>().state.',
    };
  }

  static String _lower(String pascal) => pascal.isEmpty ? pascal : '${pascal[0].toLowerCase()}${pascal.substring(1)}';

  static String _docText(String text) => text.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ');

  /// `T?`, except for `dynamic`, which already allows null.
  static String _nullable(String type) => type == 'dynamic' ? type : '$type?';

  static const _changeNotifierMembers = {
    'dispose', 'addListener', 'removeListener', 'notifyListeners', 'hasListeners', 'toString', 'hashCode', 'runtimeType', 'noSuchMethod',
  };

  // --- Provider ----------------------------------------------------------------------

  String _provider(StateGroup g, String pkg) {
    final view = '${DartNames.pascal(g.name)}ViewModel';
    final first = g.operations.firstOrNull;
    final b = StringBuffer()
      ..writeln('// State of the "${_docText(g.name)}" calls for the UI (Provider). Needs: ${StateLayerStyle.provider.dependencyCommand}')
      ..writeln('//')
      ..writeln('//   ChangeNotifierProvider(create: (_) => $view(GetIt.I<${g.sourceType}>()), child: ...)')
      ..writeln('//   context.watch<$view>().${first == null ? 'someCall' : '${first.name}State'}   // CallIdle / CallLoading / CallSuccess / CallFailure')
      ..writeln("import 'package:flutter/foundation.dart' show ChangeNotifier;")
      ..writeln("import 'package:$pkg/core/state/call_state.dart';")
      ..writeAll(g.imports.map((i) => '$i\n'))
      ..writeln()
      ..writeln('/// One [CallState] per call of "${_docText(g.name)}", so a screen shows the spinner, the data or the error of each call on its own.')
      ..writeln('class $view extends ChangeNotifier {')
      ..writeln('  $view(this._source);')
      ..writeln()
      ..writeln('  final ${g.sourceType} _source;')
      ..writeln('  final Map<String, int> _runs = {};')
      ..writeln('  bool _disposed = false;')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  void dispose() {')
      ..writeln('    _disposed = true;')
      ..writeln('    super.dispose();')
      ..writeln('  }')
      ..writeln()
      ..writeln('  void _notify() {')
      ..writeln('    if (!_disposed) notifyListeners();')
      ..writeln('  }')
      ..writeln()
      ..writeln('  /// Publishes loading (keeping the last data), then data or the error. An older call that answers late is dropped.')
      ..writeln('  Future<void> _run<T>(String key, CallState<T> Function() read, void Function(CallState<T>) write, Future<T> Function() call) async {')
      ..writeln('    final id = _runs[key] = (_runs[key] ?? 0) + 1;')
      ..writeln('    write(CallLoading<T>(read().data));')
      ..writeln('    _notify();')
      ..writeln('    try {')
      ..writeln('      final data = await call();')
      ..writeln('      if (_runs[key] != id) return;')
      ..writeln('      write(CallSuccess<T>(data));')
      ..writeln('    } catch (error, stackTrace) {')
      ..writeln('      if (_runs[key] != id) return;')
      ..writeln('      write(CallFailure<T>(error, read().data, stackTrace));')
      ..writeln('    }')
      ..writeln('    _notify();')
      ..writeln('  }');
    final usedMethods = <String>{};
    for (final op in g.operations) {
      var method = _changeNotifierMembers.contains(op.name) ? '${op.name}Call' : op.name;
      while (!usedMethods.add(method)) {
        method = '${method}2';
      }
      final state = '${method}State';
      final type = op.resultType;
      b
        ..writeln()
        ..writeln('  /// ${_docText(op.title)}: `${_docText(op.request)}`')
        ..writeln('  CallState<$type> $state = const CallIdle();');
      if (!op.isAction) b.writeln('  Future<void> Function()? _repeat${DartNames.pascal(method)};');
      b
        ..writeln()
        ..writeln('  /// Runs "${_docText(op.title)}"${op.isAction ? ', an action that changes data on the server' : ''}.')
        ..writeln('  Future<void> $method(${op.signature}) {');
      if (!op.isAction) b.writeln('    _repeat${DartNames.pascal(method)} = () => this.$method(${op.callArguments});');
      b
        ..writeln("    return _run<$type>('$method', () => this.$state, (s) => this.$state = s, () => _source.${op.name}(${op.callArguments}));")
        ..writeln('  }');
      if (!op.isAction) {
        b
          ..writeln()
          ..writeln('  /// Repeats the last [$method] call with the same arguments; does nothing before the first call.')
          ..writeln('  Future<void> refresh${DartNames.pascal(method)}() => _repeat${DartNames.pascal(method)}?.call() ?? Future<void>.value();');
      }
    }
    b.writeln('}');
    return b.toString();
  }

  // --- Riverpod ----------------------------------------------------------------------

  String _riverpod(StateGroup g) {
    final source = DartNames.camel(g.sourceType);
    final sourceProvider = '${source}Provider';
    final first = g.operations.firstOrNull;
    final used = <String>{sourceProvider};
    final b = StringBuffer()
      ..writeln('// State of the "${_docText(g.name)}" calls for the UI (Riverpod). Needs: ${StateLayerStyle.riverpod.dependencyCommand}')
      ..writeln('//')
      ..writeln('//   ref.watch(${first == null ? 'someCallProvider' : '${_lower(first.stem)}Provider'})   // AsyncValue: loading / data / error')
      ..writeln('//   ref.read(${first == null ? 'someCallProvider' : '${_lower(first.stem)}Provider'}.notifier).run(...)')
      ..writeln("import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncLoading, AsyncNotifier, AsyncNotifierProvider, AsyncValue, Provider;")
      ..writeln("import 'package:get_it/get_it.dart' show GetIt;")
      ..writeAll(g.imports.map((i) => '$i\n'))
      ..writeln()
      ..writeln('/// The ${g.sourceType} the notifiers below call. It comes from GetIt (see the feature\'s injection file); in a test, '
          'replace it with `ProviderScope(overrides: [$sourceProvider.overrideWithValue(fake)])`.')
      ..writeln('final $sourceProvider = Provider<${g.sourceType}>((ref) => GetIt.I<${g.sourceType}>());');
    for (final op in g.operations) {
      var provider = '${_lower(op.stem)}Provider';
      while (!used.add(provider)) {
        provider = '${provider.substring(0, provider.length - 'Provider'.length)}CallProvider';
      }
      final notifier = '${op.stem}Notifier';
      final type = op.resultType;
      final state = _nullable(type);
      b
        ..writeln()
        ..writeln('/// ${_docText(op.title)}: `${_docText(op.request)}`. The state is null until [$notifier.run] has been called;')
        ..writeln('/// the previous result stays in it while the call repeats.')
        ..writeln('class $notifier extends AsyncNotifier<$state> {')
        ..writeln('  int _runs = 0;');
      if (!op.isAction) b.writeln('  Future<void> Function()? _repeat;');
      b
        ..writeln()
        ..writeln('  @override')
        ..writeln('  Future<$state> build() async => null;')
        ..writeln()
        ..writeln('  Future<void> run(${op.signature}) {');
      if (!op.isAction) b.writeln('    _repeat = () => this.run(${op.callArguments});');
      b
        ..writeln('    return _run(() => this.ref.read($sourceProvider).${op.name}(${op.callArguments}));')
        ..writeln('  }');
      if (!op.isAction) {
        b
          ..writeln()
          ..writeln('  /// Repeats the last [run] with the same arguments; does nothing before the first call.')
          ..writeln('  Future<void> refresh() => _repeat?.call() ?? Future<void>.value();');
      }
      b
        ..writeln()
        ..writeln('  Future<void> _run(Future<$type> Function() call) async {')
        ..writeln('    final id = ++_runs;')
        ..writeln('    // Setting the loading state keeps the previous value in it (Riverpod does that for a notifier).')
        ..writeln('    state = const AsyncLoading();')
        ..writeln('    final result = await AsyncValue.guard<$state>(call);')
        ..writeln('    if (id == _runs) state = result;')
        ..writeln('  }')
        ..writeln('}')
        ..writeln()
        ..writeln('final $provider = AsyncNotifierProvider<$notifier, $state>($notifier.new);');
    }
    return b.toString();
  }

  // --- BLoC --------------------------------------------------------------------------

  String _bloc(StateGroup g, String pkg) {
    final first = g.operations.firstOrNull;
    final b = StringBuffer()
      ..writeln('// State of the "${_docText(g.name)}" calls for the UI (BLoC). Needs: ${StateLayerStyle.bloc.dependencyCommand}')
      ..writeln('//')
      ..writeln('//   BlocProvider(create: (_) => ${first == null ? 'SomeCall' : first.stem}Cubit(GetIt.I<${g.sourceType}>())..run(), child: ...)')
      ..writeln('//   context.watch<${first == null ? 'SomeCall' : first.stem}Cubit>().state   // CallIdle / CallLoading / CallSuccess / CallFailure')
      ..writeln("import 'package:flutter_bloc/flutter_bloc.dart' show Cubit;")
      ..writeln("import 'package:$pkg/core/state/call_state.dart';")
      ..writeAll(g.imports.map((i) => '$i\n'));
    for (final op in g.operations) {
      final cubit = '${op.stem}Cubit';
      final type = op.resultType;
      b
        ..writeln()
        ..writeln('/// ${_docText(op.title)}: `${_docText(op.request)}`. The state is a sealed [CallState]; the last data stays while the call repeats.')
        ..writeln('class $cubit extends Cubit<CallState<$type>> {')
        ..writeln('  $cubit(this._source) : super(const CallIdle());')
        ..writeln()
        ..writeln('  final ${g.sourceType} _source;')
        ..writeln('  int _runs = 0;');
      if (!op.isAction) b.writeln('  Future<void> Function()? _repeat;');
      b
        ..writeln()
        ..writeln('  Future<void> run(${op.signature}) {');
      if (!op.isAction) b.writeln('    _repeat = () => this.run(${op.callArguments});');
      b
        ..writeln('    return _run(() => _source.${op.name}(${op.callArguments}));')
        ..writeln('  }');
      if (!op.isAction) {
        b
          ..writeln()
          ..writeln('  /// Repeats the last [run] with the same arguments; does nothing before the first call.')
          ..writeln('  Future<void> refresh() => _repeat?.call() ?? Future<void>.value();');
      }
      b
        ..writeln()
        ..writeln('  Future<void> _run(Future<$type> Function() call) async {')
        ..writeln('    if (isClosed) return;')
        ..writeln('    final id = ++_runs;')
        ..writeln('    emit(CallLoading<$type>(state.data));')
        ..writeln('    try {')
        ..writeln('      final data = await call();')
        ..writeln('      if (id == _runs && !isClosed) emit(CallSuccess<$type>(data));')
        ..writeln('    } catch (error, stackTrace) {')
        ..writeln('      if (id == _runs && !isClosed) emit(CallFailure<$type>(error, state.data, stackTrace));')
        ..writeln('    }')
        ..writeln('  }')
        ..writeln('}');
    }
    return b.toString();
  }

  static const _callState = '''/// What a screen shows for one call. Provider view models and BLoC cubits publish these; the class is sealed, so a
/// `switch` has to handle every case:
///
///     switch (state) {
///       CallIdle() => const SizedBox.shrink(),
///       CallLoading(:final data) => ...,
///       CallSuccess(:final data) => ...,
///       CallFailure(:final error) => ...,
///     }
sealed class CallState<T> {
  const CallState();

  /// The last successful result. It is kept while the call repeats and after a repeat failed, so the screen does not blank out.
  T? get data;

  /// What the last call threw, or null.
  Object? get error => null;

  bool get isLoading => this is CallLoading<T>;
}

/// Nothing has been asked yet.
final class CallIdle<T> extends CallState<T> {
  const CallIdle();

  @override
  T? get data => null;
}

/// A call is running; [data] is the result of the one before, if any.
final class CallLoading<T> extends CallState<T> {
  const CallLoading([this.data]);

  @override
  final T? data;
}

final class CallSuccess<T> extends CallState<T> {
  const CallSuccess(this.data);

  @override
  final T data;
}

/// The call threw [error]; [data] is the last good result, if any.
final class CallFailure<T> extends CallState<T> {
  const CallFailure(this.error, [this.data, this.stackTrace]);

  @override
  final Object error;

  @override
  final T? data;
  final StackTrace? stackTrace;
}
''';
}
