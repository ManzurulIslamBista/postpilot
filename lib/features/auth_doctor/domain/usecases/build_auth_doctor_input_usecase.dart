import 'dart:convert';
import '../../../../core/enums/auth_type.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../environments/domain/entities/environment_entity.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../../request_builder/domain/entities/variable_info.dart';
import '../../../request_builder/domain/usecases/list_variables_usecase.dart';
import '../../../request_builder/domain/usecases/prepare_request_usecase.dart';
import '../entities/auth_doctor_input.dart';
import '../services/auth_context.dart';

/// A rejected response with the request that got it.
final class AuthDoctorSubject {
  final ApiRequestEntity request;
  final ApiResponseEntity response;

  /// When the response arrived, when the app kept that (see `ResponseHistory`); null means now.
  final DateTime? receivedAt;

  const AuthDoctorSubject({required this.request, required this.response, this.receivedAt});
}

/// Gathers what the doctor looks at for one rejected response. The request is built again by the same
/// [PrepareRequestUseCase] a send uses, so the headers are the ones that go on the wire for the request as it is saved
/// now, with the variables as they are now; the doctor reads the templates next to them to see which `{{variable}}`
/// fed which credential. Nothing is sent, and no variable value leaves this class: only whether each one has one.
final class BuildAuthDoctorInputUseCase implements UseCase<AuthDoctorInput, AuthDoctorSubject> {
  /// A body is only read up to here.
  static const _maxBody = 256 * 1024;

  final PrepareRequestUseCase _prepare;
  final ListVariablesUseCase _variables;
  final EnvironmentRepository _environments;
  final DateTime Function() _now;

  BuildAuthDoctorInputUseCase(this._prepare, this._variables, this._environments, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  @override
  Future<AuthDoctorInput> call(AuthDoctorSubject subject) async {
    final request = subject.request;
    final response = subject.response;

    PreparedRequest? prepared;
    try {
      prepared = await _prepare(request);
    } catch (_) {
      // The request was edited into something that cannot be built; the doctor then claims nothing about what was sent.
      prepared = null;
    }
    final auth = prepared?.auth ?? request.auth;
    String resolve(String text) => prepared?.resolver.resolve(text) ?? text;

    final headerTemplates = <String, String>{};
    for (final row in [...?prepared?.inherited?.headerRows, ...request.headers]) {
      if (!row.enabled || row.key.trim().isEmpty) continue;
      headerTemplates[resolve(row.key).trim()] = row.value;
    }
    final queryTemplates = <String, String>{..._queryOf(request.url)};
    for (final row in request.queryParams) {
      if (row.enabled && row.key.trim().isNotEmpty) queryTemplates[resolve(row.key).trim()] = row.value;
    }
    switch (auth.type) {
      case AuthType.bearer:
        headerTemplates['Authorization'] = 'Bearer ${auth.bearerToken}';
      case AuthType.basic:
        headerTemplates['Authorization'] = 'Basic ${auth.basicUsername}:${auth.basicPassword}';
      case AuthType.apiKey:
        final name = resolve(auth.apiKeyName).trim();
        if (name.isNotEmpty) {
          (auth.apiKeyLocation == ApiKeyLocation.header ? headerTemplates : queryTemplates)[name] = auth.apiKeyValue;
        }
      case AuthType.hmac:
        // The signature header is derived from the secret, so the secret's variable is the one that feeds it.
        final name = resolve(auth.hmacHeaderName).trim();
        if (name.isNotEmpty) headerTemplates[name] = '${auth.hmacHeaderTemplate} ${auth.hmacSecret}';
      case AuthType.digest || AuthType.awsSignatureV4 || AuthType.jwtBearer || AuthType.oauth2 || AuthType.none || AuthType.inherit:
        break;
    }

    final names = {
      for (final template in [...headerTemplates.values, ...queryTemplates.values, request.url]) ...AuthText.variablesIn(template),
    };
    final known = await _safe(() => _variables(request.collectionId, folderId: request.folderId), const <String, VariableInfo>{});
    final facts = {
      for (final name in names)
        if (known[name] case final info?)
          name: AuthVariableFact(
            name: name,
            isEmpty: (info.value ?? '').isEmpty,
            isSecret: info.isSecret,
            source: info.source.name,
            scopeName: info.scopeName,
          ),
    };

    final all = await _safe<List<EnvironmentEntity>>(() => _environments.watchAll().first, const []);
    final active = all.where((e) => e.isActive).firstOrNull;
    final others = <AuthEnvironmentFacts>[];
    if (names.isNotEmpty) {
      for (final environment in all) {
        if (environment.id == active?.id) continue;
        final variables = await _safe<List<EnvironmentVariableEntity>>(() => _environments.watchVariables(environment.id).first, const []);
        final filled = {
          for (final v in variables)
            if (v.enabled && v.value.isNotEmpty && names.contains(v.key)) v.key,
        };
        if (filled.isNotEmpty) others.add(AuthEnvironmentFacts(environment.name, filled));
      }
    }

    final bytes = response.bodyBytes.length > _maxBody ? response.bodyBytes.sublist(0, _maxBody) : response.bodyBytes;
    final spec = prepared?.spec;
    return AuthDoctorInput(
      method: request.method.label,
      url: spec?.url ?? request.url,
      headers: spec?.headers ?? const {},
      authType: auth.type,
      apiKeyName: resolve(auth.apiKeyName),
      apiKeyLocation: auth.apiKeyLocation,
      urlTemplate: request.url,
      headerTemplates: headerTemplates,
      queryTemplates: queryTemplates,
      requestKnown: spec != null,
      status: response.statusCode,
      responseHeaders: response.headers,
      responseBody: utf8.decode(bytes, allowMalformed: true),
      environmentName: active?.name,
      variables: facts,
      otherEnvironments: others,
      now: subject.receivedAt ?? _now(),
    );
  }

  /// The doctor is a convenience: a store that cannot be read costs a hint, not the whole diagnosis.
  Future<T> _safe<T>(Future<T> Function() read, T fallback) async {
    try {
      return await read();
    } catch (_) {
      return fallback;
    }
  }

  /// The query rows written into the URL itself, `?token={{token}}`.
  static Map<String, String> _queryOf(String url) {
    final at = url.indexOf('?');
    if (at < 0) return const {};
    final hash = url.indexOf('#', at);
    final query = url.substring(at + 1, hash < 0 ? url.length : hash);
    final rows = <String, String>{};
    for (final pair in query.split('&')) {
      if (pair.isEmpty) continue;
      final equals = pair.indexOf('=');
      final name = equals < 0 ? pair : pair.substring(0, equals);
      if (name.isNotEmpty) rows[name] = equals < 0 ? '' : pair.substring(equals + 1);
    }
    return rows;
  }
}
