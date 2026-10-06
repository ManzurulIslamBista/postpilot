import 'dart:collection';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/variable_resolver.dart';
import '../../../environments/domain/entities/environment_entity.dart';
import '../../../environments/domain/entities/global_variable_entity.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../environments/domain/repositories/global_variable_repository.dart';
import '../../../defaults/domain/entities/inherited_defaults.dart';
import '../../../defaults/domain/usecases/resolve_request_defaults_usecase.dart';
import '../../../git_sync/domain/services/secret_fields.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../../request_builder/domain/repositories/request_scripts_repository.dart';
import '../../../request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import '../../../test_suggestions/domain/usecases/baseline_guard.dart';
import '../../data/models/scripts_json_codec.dart';
import '../entities/assertion_result.dart';
import '../entities/extractor_entity.dart';
import '../entities/script_run_result.dart';
import '../evaluator/assertion_evaluator.dart';
import '../evaluator/extractor_value_resolver.dart';
import '../evaluator/response_reader.dart';

final class RunRequestScriptsParams {
  final int requestId;

  /// The request's collection: its variables, with the active environment's
  /// and the globals', resolve `{{name}}` inside assertions and extractor paths.
  final int collectionId;
  final ApiResponseEntity response;

  /// The data row of a collection run, if any: the same top-priority scope the
  /// request itself was sent with.
  final Map<String, String> dataVariables;

  /// The folder the request was in when it was sent; where its inherited tests
  /// and folder variables come from. The stored request wins if it has moved since.
  final int? folderId;

  /// A collection run: a request that turned on "Enforce baseline in runs" gets a `Baseline: N breaking changes`
  /// result row. A send from the editor leaves it off, where the response shows its drift in a chip instead.
  final bool enforceBaseline;

  const RunRequestScriptsParams({
    required this.requestId,
    required this.collectionId,
    required this.response,
    this.dataVariables = const {},
    this.folderId,
    this.enforceBaseline = false,
  });
}

/// Post-send hook: evaluates the request's saved assertions (whose expected
/// values, paths and header names may use `{{key}}`) and writes its extractors
/// (whose paths may use `{{key}}` too) into environment/global variables so the
/// next request can chain on `{{key}}`. The tests of the collection and of the
/// folders above the request run first, outermost level first, then the
/// request's own; each result of an inherited one says where it comes from.
/// Never throws for missing or malformed scripts.
final class RunRequestScriptsUseCase implements UseCase<ScriptRunResult, RunRequestScriptsParams> {
  final RequestScriptsRepository _scriptsRepository;
  final BuildVariableResolverUseCase _buildVariableResolverUseCase;
  final EnvironmentRepository _environmentRepository;
  final GlobalVariableRepository _globalVariableRepository;
  final AssertionEvaluator _evaluator;
  final ResolveRequestDefaultsUseCase? _defaults;

  /// Holds a request to its recorded baseline when a run asks for it (see [RunRequestScriptsParams.enforceBaseline]).
  final BaselineGuard? _baseline;

  const RunRequestScriptsUseCase(
    this._scriptsRepository,
    this._buildVariableResolverUseCase,
    this._environmentRepository,
    this._globalVariableRepository, [
    this._evaluator = const AssertionEvaluator(),
    this._defaults,
    this._baseline,
  ]);

  @override
  Future<ScriptRunResult> call(RunRequestScriptsParams params) async {
    final result = await _evaluate(params);
    final row = params.enforceBaseline ? await _baseline?.rowFor(params.requestId, params.response) : null;
    if (row == null) return result;
    return ScriptRunResult(assertions: [...result.assertions, row], extracted: result.extracted);
  }

  Future<ScriptRunResult> _evaluate(RunRequestScriptsParams params) async {
    final scripts = await _scriptsRepository.get(params.requestId);
    final inherited = await _defaults?.forRequest(
      requestId: params.requestId,
      collectionId: params.collectionId,
      folderId: params.folderId,
    );
    final levels = inherited?.tests ?? const <InheritedTests>[];
    if (scripts == null && levels.isEmpty) return ScriptRunResult.empty;

    final resolver = await _buildVariableResolverUseCase(
      params.collectionId,
      dataVariables: params.dataVariables,
      folderId: params.folderId,
      inherited: inherited,
    );
    final assertions = <AssertionResult>[
      for (final level in levels)
        for (final result in _evaluator.evaluate(params.response, level.assertions, resolver))
          result.fromOrigin(level.origin.label),
      if (scripts != null)
        ..._evaluator.evaluate(params.response, ScriptsJsonCodec.decodeAssertions(scripts.assertionsJson), resolver),
    ];
    final reader = ResponseReader(params.response);
    final extracted = <ExtractionResult>[];
    for (final level in levels) {
      for (final extractor in level.extractors) {
        extracted.add((await _extract(reader, extractor, resolver)).fromOrigin(level.origin.label));
      }
    }
    if (scripts != null) {
      for (final extractor in ScriptsJsonCodec.decodeExtractors(scripts.extractorsJson)) {
        extracted.add(await _extract(reader, extractor, resolver));
      }
    }
    return ScriptRunResult(assertions: assertions, extracted: extracted);
  }

  Future<ExtractionResult> _extract(ResponseReader reader, ExtractorEntity raw, VariableResolver resolver) async {
    final extractor = raw.copyWith(path: resolver.resolve(raw.path));
    final key = extractor.variableKey.trim();
    final configError = extractor.keyError ?? extractor.pathError;
    if (configError != null) return ExtractionResult(key: key, scope: extractor.scope, error: configError);

    final value = ExtractorValueResolver.resolve(reader, extractor);
    if (value == null) return ExtractionResult(key: key, scope: extractor.scope, error: 'Not found in response');

    final error = switch (extractor.scope) {
      ExtractorScope.environment => await _writeEnvironment(key, value),
      ExtractorScope.global => await _writeGlobal(key, value),
    };
    return ExtractionResult(key: key, scope: extractor.scope, value: value, error: error);
  }

  Future<String?> _writeEnvironment(String key, String value) async {
    final active = await _environmentRepository.watchActive().first;
    if (active == null) return 'No active environment';

    final variables = await _environmentRepository.watchVariables(active.id).first;
    final existing = _rowTheResolverReads(variables.where((v) => v.key == key), (v) => v.enabled);
    await _environmentRepository.upsertVariable(EnvironmentVariableEntity(
      id: existing?.id ?? 0,
      environmentId: active.id,
      key: key,
      value: value,
      // A row the user made keeps its flag; a new one named like a credential (access_token) is
      // secret from the start, or the value would be pushed to Git in plain text.
      isSecret: existing?.isSecret ?? SecretFields.looksSecretKey(key),
      enabled: true,
    ));
    return null;
  }

  Future<String?> _writeGlobal(String key, String value) async {
    final variables = await _globalVariableRepository.watchAll().first;
    final existing = _rowTheResolverReads(variables.where((v) => v.key == key), (v) => v.enabled);
    await _globalVariableRepository.upsert(GlobalVariableEntity(
      id: existing?.id ?? 0,
      key: key,
      value: value,
      isSecret: existing?.isSecret ?? SecretFields.looksSecretKey(key),
      enabled: true,
    ));
    return null;
  }

  /// The resolver only reads enabled rows and, for a key held by several, the
  /// last one. Writing to that row, and enabling it when every match is
  /// disabled, is what makes the saved value visible to the next request.
  T? _rowTheResolverReads<T>(Iterable<T> matches, bool Function(T) isEnabled) =>
      matches.where(isEnabled).lastOrNull ?? matches.lastOrNull;
}
