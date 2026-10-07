/// The presentation layer written for each model of a generated Odoo client, in the three styles. `%Name%` marks what
/// the generator fills in: `%Class%` (the model class), `%model%` (`res.partner`), `%file%` (`res_partner`), `%lower%`
/// (`resPartner`). Every style does the same: load the first page, load more, refresh, filter, and create / update /
/// delete with the list kept in step. A late answer of an older load never replaces a newer list.
abstract final class OdooStateTemplates {
  static const provider = r'''// State of the %model% list for the UI (Provider). Needs: dart pub add provider
//
//   ChangeNotifierProvider(create: (_) => %Class%ListViewModel(%Class%Repository(client))..loadFirstPage(), child: ...)
//   context.watch<%Class%ListViewModel>()   // items, isLoading, isLoadingMore, hasMore, error
import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../core/odoo_domain.dart';
import '../models/%file%.dart';
import '../repositories/%file%_repository.dart';

/// The state of a screen that lists %model% records: loading, data, error, paging and the create / update / delete actions.
class %Class%ListViewModel extends ChangeNotifier {
  %Class%ListViewModel(this._repository, {this.pageSize = 20, Domain domain = Domain.all, String? order})
      : _domain = domain,
        _order = order;

  final %Class%Repository _repository;
  final int pageSize;
  Domain _domain;
  String? _order;
  bool _disposed = false;
  int _loads = 0;

  List<%Class%> items = const [];
  bool isLoading = false;
  bool isLoadingMore = false;
  bool hasMore = true;

  /// The last error of a load or an action; null after the next success.
  Object? error;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Loads the first page again. The old list stays on screen while it loads.
  Future<void> loadFirstPage() async {
    final load = ++_loads;
    isLoading = true;
    isLoadingMore = false;
    error = null;
    _notify();
    try {
      final page = await _repository.search(domain: _domain, limit: pageSize, order: _order);
      if (load != _loads) return;
      items = page.items;
      hasMore = page.hasMore;
    } catch (e) {
      if (load != _loads) return;
      error = e;
    }
    isLoading = false;
    _notify();
  }

  Future<void> refresh() => loadFirstPage();

  /// Loads the next page and appends it. Does nothing while a load runs or when there is no more.
  Future<void> loadMore() async {
    if (isLoading || isLoadingMore || !hasMore) return;
    final load = _loads;
    isLoadingMore = true;
    _notify();
    try {
      final page = await _repository.search(domain: _domain, limit: pageSize, offset: items.length, order: _order);
      if (load != _loads) return;
      items = [...items, ...page.items];
      hasMore = page.hasMore;
    } catch (e) {
      if (load != _loads) return;
      error = e;
    }
    isLoadingMore = false;
    _notify();
  }

  /// Searches with another [domain] and [order] from the first page on.
  Future<void> applyFilter({Domain domain = Domain.all, String? order}) {
    _domain = domain;
    _order = order;
    return loadFirstPage();
  }

  /// Creates the record and puts it at the top of the list. Returns it, or null after setting [error].
  Future<%Class%?> create(%Class% item, {Map<String, Object?> extra = const {}}) async {
    try {
      final created = await _repository.create(item, extra: extra);
      items = [created, ...items];
      error = null;
      _notify();
      return created;
    } catch (e) {
      error = e;
      _notify();
      return null;
    }
  }

  /// Writes [values] to the record and replaces it in the list. Returns the new record, or null after setting [error].
  Future<%Class%?> update(int id, Map<String, Object?> values) async {
    try {
      final updated = await _repository.update(id, values);
      items = [for (final item in items) item.id == id ? updated : item];
      error = null;
      _notify();
      return updated;
    } catch (e) {
      error = e;
      _notify();
      return null;
    }
  }

  /// Deletes the record and takes it out of the list. Returns false after setting [error].
  Future<bool> delete(int id) async {
    try {
      await _repository.delete(id);
      items = [for (final item in items) if (item.id != id) item];
      error = null;
      _notify();
      return true;
    } catch (e) {
      error = e;
      _notify();
      return false;
    }
  }
}
''';

  static const riverpod = r'''// State of the %model% list for the UI (Riverpod). Needs: dart pub add flutter_riverpod
//
//   ProviderScope(overrides: [odooClientProvider.overrideWithValue(client)], child: ...)
//   ref.watch(%lower%ListProvider)                    // AsyncValue<%Class%ListState>
//   ref.read(%lower%ListProvider.notifier).loadMore()
//
// Riverpod 3 tries a provider again by itself when its first load throws (after 200 ms, 400 ms... up to ten times) before
// the AsyncValue shows the error. To show a failed first load at once: ProviderScope(retry: (count, error) => null, ...).
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData, AsyncLoading, AsyncNotifier, AsyncNotifierProvider, AsyncValue, Provider;

import '../core/odoo_domain.dart';
import '../models/%file%.dart';
import '../repositories/%file%_repository.dart';
import 'odoo_providers.dart';

final %lower%RepositoryProvider = Provider<%Class%Repository>((ref) => %Class%Repository(ref.watch(odooClientProvider)));

/// What a screen shows for the %model% list: the records loaded so far, whether there are more, and the error of the last action.
class %Class%ListState {
  const %Class%ListState({this.items = const [], this.hasMore = true, this.isLoadingMore = false, this.actionError});

  final List<%Class%> items;
  final bool hasMore;
  final bool isLoadingMore;

  /// What the last create / update / delete or "load more" threw; null after the next success.
  final Object? actionError;

  %Class%ListState copyWith({
    List<%Class%>? items,
    bool? hasMore,
    bool? isLoadingMore,
    Object? actionError,
    bool clearActionError = false,
  }) =>
      %Class%ListState(
        items: items ?? this.items,
        hasMore: hasMore ?? this.hasMore,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        actionError: clearActionError ? null : (actionError ?? this.actionError),
      );
}

/// Loads the first page when it is first read (loading / data / error is the AsyncValue), then pages, refreshes, filters
/// and changes records.
class %Class%ListNotifier extends AsyncNotifier<%Class%ListState> {
  static const pageSize = 20;

  Domain _domain = Domain.all;
  String? _order;
  int _loads = 0;

  %Class%Repository get _repository => ref.read(%lower%RepositoryProvider);

  @override
  Future<%Class%ListState> build() => _firstPage();

  Future<%Class%ListState> _firstPage() async {
    final page = await _repository.search(domain: _domain, limit: pageSize, order: _order);
    return %Class%ListState(items: page.items, hasMore: page.hasMore);
  }

  /// Loads the first page again. The old list stays on screen while it loads.
  Future<void> refresh() async {
    final load = ++_loads;
    // Setting the loading state keeps the previous value in it (Riverpod does that for a notifier), so the list stays on screen.
    state = const AsyncLoading();
    final result = await AsyncValue.guard(_firstPage);
    if (load == _loads) state = result;
  }

  /// Searches with another [domain] and [order] from the first page on.
  Future<void> applyFilter({Domain domain = Domain.all, String? order}) {
    _domain = domain;
    _order = order;
    return refresh();
  }

  /// Loads the next page and appends it. Does nothing while a load runs or when there is no more.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) return;
    final load = _loads;
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final page = await _repository.search(domain: _domain, limit: pageSize, offset: current.items.length, order: _order);
      if (load != _loads) return;
      _change((s) => s.copyWith(items: [...s.items, ...page.items], hasMore: page.hasMore, isLoadingMore: false));
    } catch (error) {
      if (load != _loads) return;
      _change((s) => s.copyWith(isLoadingMore: false, actionError: error));
    }
  }

  void _change(%Class%ListState Function(%Class%ListState current) change) {
    final current = state.value;
    if (current != null) state = AsyncData(change(current));
  }

  /// Creates the record and puts it at the top of the list. Returns it, or null after setting `actionError`.
  Future<%Class%?> create(%Class% item, {Map<String, Object?> extra = const {}}) async {
    try {
      final created = await _repository.create(item, extra: extra);
      _change((s) => s.copyWith(items: [created, ...s.items], clearActionError: true));
      return created;
    } catch (error) {
      _change((s) => s.copyWith(actionError: error));
      return null;
    }
  }

  /// Writes [values] to the record and replaces it in the list. Returns the new record, or null after setting `actionError`.
  /// (Not called `update`: an AsyncNotifier has a method of that name.)
  Future<%Class%?> updateRecord(int id, Map<String, Object?> values) async {
    try {
      final updated = await _repository.update(id, values);
      _change((s) => s.copyWith(items: [for (final item in s.items) item.id == id ? updated : item], clearActionError: true));
      return updated;
    } catch (error) {
      _change((s) => s.copyWith(actionError: error));
      return null;
    }
  }

  /// Deletes the record and takes it out of the list. Returns false after setting `actionError`.
  Future<bool> delete(int id) async {
    try {
      await _repository.delete(id);
      _change((s) => s.copyWith(items: [for (final item in s.items) if (item.id != id) item], clearActionError: true));
      return true;
    } catch (error) {
      _change((s) => s.copyWith(actionError: error));
      return false;
    }
  }
}

final %lower%ListProvider = AsyncNotifierProvider<%Class%ListNotifier, %Class%ListState>(%Class%ListNotifier.new);
''';

  static const bloc = r'''// State of the %model% list for the UI (BLoC). Needs: dart pub add flutter_bloc
//
//   BlocProvider(create: (_) => %Class%ListCubit(%Class%Repository(client))..load(), child: ...)
//   BlocBuilder<%Class%ListCubit, %Class%ListState>(builder: (context, state) => switch (state) { ... })
import 'package:flutter_bloc/flutter_bloc.dart' show Cubit;

import '../core/odoo_domain.dart';
import '../models/%file%.dart';
import '../repositories/%file%_repository.dart';

/// What the %model% list screen can be in. Sealed, so a `switch` has to handle every case.
sealed class %Class%ListState {
  const %Class%ListState();
}

/// Nothing has been loaded yet.
final class %Class%ListInitial extends %Class%ListState {
  const %Class%ListInitial();
}

/// A load is running; [items] is the list from before, if any.
final class %Class%ListLoading extends %Class%ListState {
  const %Class%ListLoading([this.items = const []]);

  final List<%Class%> items;
}

final class %Class%ListLoaded extends %Class%ListState {
  const %Class%ListLoaded(this.items, {this.hasMore = true, this.isLoadingMore = false, this.actionError});

  final List<%Class%> items;
  final bool hasMore;
  final bool isLoadingMore;

  /// What the last create / update / delete or "load more" threw; null after the next success.
  final Object? actionError;

  %Class%ListLoaded copyWith({
    List<%Class%>? items,
    bool? hasMore,
    bool? isLoadingMore,
    Object? actionError,
    bool clearActionError = false,
  }) =>
      %Class%ListLoaded(
        items ?? this.items,
        hasMore: hasMore ?? this.hasMore,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        actionError: clearActionError ? null : (actionError ?? this.actionError),
      );
}

/// The first load failed; [items] is the list from before, if any.
final class %Class%ListFailure extends %Class%ListState {
  const %Class%ListFailure(this.error, [this.items = const []]);

  final Object error;
  final List<%Class%> items;
}

class %Class%ListCubit extends Cubit<%Class%ListState> {
  %Class%ListCubit(this._repository, {this.pageSize = 20, Domain domain = Domain.all, String? order})
      : _domain = domain,
        _order = order,
        super(const %Class%ListInitial());

  final %Class%Repository _repository;
  final int pageSize;
  Domain _domain;
  String? _order;
  int _loads = 0;

  List<%Class%> get _items => switch (state) {
        %Class%ListLoading(:final items) || %Class%ListFailure(:final items) || %Class%ListLoaded(:final items) => items,
        _ => const [],
      };

  /// Loads the first page. The old list stays in the loading state while it runs.
  Future<void> load() async {
    if (isClosed) return;
    final id = ++_loads;
    emit(%Class%ListLoading(_items));
    try {
      final page = await _repository.search(domain: _domain, limit: pageSize, order: _order);
      if (id == _loads && !isClosed) emit(%Class%ListLoaded(page.items, hasMore: page.hasMore));
    } catch (error) {
      if (id == _loads && !isClosed) emit(%Class%ListFailure(error, _items));
    }
  }

  Future<void> refresh() => load();

  /// Searches with another [domain] and [order] from the first page on.
  Future<void> applyFilter({Domain domain = Domain.all, String? order}) {
    _domain = domain;
    _order = order;
    return load();
  }

  /// Loads the next page and appends it. Does nothing while a load runs or when there is no more.
  Future<void> loadMore() async {
    final current = state;
    if (isClosed || current is! %Class%ListLoaded || current.isLoadingMore || !current.hasMore) return;
    final id = _loads;
    emit(current.copyWith(isLoadingMore: true));
    try {
      final page = await _repository.search(domain: _domain, limit: pageSize, offset: current.items.length, order: _order);
      final latest = state;
      if (id != _loads || isClosed || latest is! %Class%ListLoaded) return;
      emit(latest.copyWith(items: [...latest.items, ...page.items], hasMore: page.hasMore, isLoadingMore: false));
    } catch (error) {
      final latest = state;
      if (id != _loads || isClosed || latest is! %Class%ListLoaded) return;
      emit(latest.copyWith(isLoadingMore: false, actionError: error));
    }
  }

  void _publish(List<%Class%> items) {
    if (isClosed) return;
    final current = state;
    emit(current is %Class%ListLoaded ? current.copyWith(items: items, clearActionError: true) : %Class%ListLoaded(items));
  }

  void _fail(Object error) {
    if (isClosed) return;
    final current = state;
    emit(current is %Class%ListLoaded ? current.copyWith(actionError: error) : %Class%ListLoaded(_items, actionError: error));
  }

  /// Creates the record and puts it at the top of the list. Returns it, or null after emitting the error in `actionError`.
  Future<%Class%?> create(%Class% item, {Map<String, Object?> extra = const {}}) async {
    try {
      final created = await _repository.create(item, extra: extra);
      _publish([created, ..._items]);
      return created;
    } catch (error) {
      _fail(error);
      return null;
    }
  }

  /// Writes [values] to the record and replaces it in the list. Returns the new record, or null after emitting the error.
  Future<%Class%?> update(int id, Map<String, Object?> values) async {
    try {
      final updated = await _repository.update(id, values);
      _publish([for (final item in _items) item.id == id ? updated : item]);
      return updated;
    } catch (error) {
      _fail(error);
      return null;
    }
  }

  /// Deletes the record and takes it out of the list. Returns false after emitting the error.
  Future<bool> delete(int id) async {
    try {
      await _repository.delete(id);
      _publish([for (final item in _items) if (item.id != id) item]);
      return true;
    } catch (error) {
      _fail(error);
      return false;
    }
  }
}
''';

  static const riverpodProviders = r'''import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;

import '../core/odoo_client.dart';

/// The one client the repository providers use. It has no default on purpose: the API key must not be written into
/// source code. Override it where the app starts, with a client built from your own settings:
///
///     ProviderScope(
///       overrides: [odooClientProvider.overrideWithValue(client)],
///       child: const MyApp(),
///     )
final odooClientProvider = Provider<OdooClient>(
  (ref) => throw UnimplementedError('Override odooClientProvider with an OdooClient built from your base URL, database and API key.'),
);
''';

  static String render(String template, Map<String, String> tokens) {
    var text = template;
    tokens.forEach((name, value) => text = text.replaceAll('%$name%', value));
    return text;
  }
}
