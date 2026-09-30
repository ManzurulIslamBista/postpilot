import 'dart:collection';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/variable_resolver.dart';
import '../../../environments/domain/entities/environment_entity.dart';
import '../../../environments/domain/entities/global_variable_entity.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../environments/domain/repositories/global_variable_repository.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../../request_builder/domain/repositories/request_scripts_repository.dart';
import '../../../request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import '../../data/models/scripts_json_codec.dart';
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

  const RunRequestScriptsParams({
    required this.requestId,
    required this.collectionId,
    required this.response,
    this.dataVariables = const {},
  });
}

/// Post-send hook: evaluates the request's saved assertions (whose expected
/// values, paths and header names may use `{{key}}`) and writes its extractors
/// (whose paths may use `{{key}}` too) into environment/global variables so the
/// next request can chain on `{{key}}`. Never throws for missing or malformed
/// scripts.
final class RunRequestScriptsUseCase implements UseCase<ScriptRunResult, RunRequestScriptsParams> {
  final RequestScriptsRepository _scriptsRepository;
  final BuildVariableResolverUseCase _buildVariableResolverUseCase;
  final EnvironmentRepository _environmentRepository;
  final GlobalVariableRepository _globalVariableRepository;
  final AssertionEvaluator _evaluator;

  const RunRequestScriptsUseCase(
    this._scriptsRepository,
    this._buildVariableResolverUseCase,
    this._environmentRepository,
    this._globalVariableRepository, [
    this._evaluator = const AssertionEvaluator(),
  ]);

  @override
  Future<ScriptRunResult> call(RunRequestScriptsParams params) async {
    final scripts = await _scriptsRepository.get(params.requestId);
    if (scripts == null) return ScriptRunResult.empty;

    final resolver = await _buildVariableResolverUseCase(params.collectionId, dataVariables: params.dataVariables);
    final assertions = _evaluator.evaluate(
      params.response,
      ScriptsJsonCodec.decodeAssertions(scripts.assertionsJson),
      resolver,
    );
    final reader = ResponseReader(params.response);
    final extracted = <ExtractionResult>[];
    for (final extractor in ScriptsJsonCodec.decodeExtractors(scripts.extractorsJson)) {
      extracted.add(await _extract(reader, extractor, resolver));
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
      isSecret: existing?.isSecret ?? false,
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
      isSecret: existing?.isSecret ?? false,
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
