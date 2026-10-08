// Pure Dart (no Flutter, no database).
import '../../../../core/enums/auth_type.dart';

/// A `{{variable}}` that feeds a credential of the request, and what the variable scopes say about it. The value
/// itself never travels here: only whether there is one.
final class AuthVariableFact {
  final String name;

  /// The variable exists but holds nothing.
  final bool isEmpty;
  final bool isSecret;

  /// Where the value comes from: `environment`, `folder`, `collection` or `global`.
  final String source;

  /// The name of the environment or folder that holds it.
  final String? scopeName;

  const AuthVariableFact({
    required this.name,
    this.isEmpty = false,
    this.isSecret = false,
    this.source = 'environment',
    this.scopeName,
  });
}

/// An environment that is not the active one, and which of the credential variables it fills in.
final class AuthEnvironmentFacts {
  final String name;

  /// The credential variables this environment holds with a non-empty value.
  final Set<String> filledVariables;

  const AuthEnvironmentFacts(this.name, this.filledVariables);
}

/// One redirect the client followed before the response that is being explained.
final class AuthRedirectHop {
  final String from;
  final String to;
  final int status;

  const AuthRedirectHop({required this.from, required this.to, this.status = 302});
}

/// Everything the doctor looks at for one rejected response: the request as it was sent, the templates it was made
/// from (to see which `{{variable}}` fed a credential), the response, the environment, and the time.
final class AuthDoctorInput {
  final String method;

  /// The URL as sent: variables resolved, query included.
  final String url;

  /// The headers as sent, auth included.
  final Map<String, String> headers;

  /// The auth type in force (an inherited one already resolved).
  final AuthType authType;

  /// The name of the key and where it goes, for API key auth.
  final String apiKeyName;
  final ApiKeyLocation apiKeyLocation;

  /// The URL as written, `{{variables}}` still in it.
  final String? urlTemplate;

  /// The header rows as written (`Authorization` -> `Bearer {{token}}`), after the auth settings were applied.
  final Map<String, String> headerTemplates;

  /// The query rows as written (`api_key` -> `{{apiKey}}`).
  final Map<String, String> queryTemplates;

  /// False when the request could not be rebuilt as it was sent (it was edited since, a variable store failed). The
  /// doctor then makes no claim about what was or was not in it.
  final bool requestKnown;

  final int status;
  final Map<String, String> responseHeaders;

  /// The response body as text.
  final String responseBody;

  /// The active environment; null when none is selected.
  final String? environmentName;

  /// What the variable scopes say about each variable the credentials use. A name that is missing is undefined.
  final Map<String, AuthVariableFact> variables;
  final List<AuthEnvironmentFacts> otherEnvironments;

  /// The redirects followed before this response, when known.
  final List<AuthRedirectHop> redirects;

  /// The moment the response arrived (or the current time when that is not known). The clock is injected so a
  /// diagnosis is reproducible.
  final DateTime now;

  const AuthDoctorInput({
    this.method = 'GET',
    required this.url,
    this.headers = const {},
    this.authType = AuthType.none,
    this.apiKeyName = '',
    this.apiKeyLocation = ApiKeyLocation.header,
    this.urlTemplate,
    this.headerTemplates = const {},
    this.queryTemplates = const {},
    this.requestKnown = true,
    required this.status,
    this.responseHeaders = const {},
    this.responseBody = '',
    this.environmentName,
    this.variables = const {},
    this.otherEnvironments = const [],
    this.redirects = const [],
    required this.now,
  });
}

/// What a run record keeps about requests that were rejected: no headers and no body, only the status, the address
/// without credentials or query, the environment, and how the rest of the run fared on the same host.
final class AuthRunFacts {
  /// 401 or 403.
  final int status;

  /// The address of the first rejected request: scheme, host and path.
  final String url;

  /// The environment the run used; empty when unknown.
  final String environment;

  /// How many requests of the run were rejected with [status].
  final int rejected;

  /// How many requests to the same host passed (any 2xx) in the same run.
  final int passedOnSameHost;

  const AuthRunFacts({
    required this.status,
    required this.url,
    this.environment = '',
    this.rejected = 1,
    this.passedOnSameHost = 0,
  });
}
