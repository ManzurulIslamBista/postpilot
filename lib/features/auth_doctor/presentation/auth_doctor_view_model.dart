import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/di/injector.dart';
import '../../../core/usecases/usecase.dart';
import '../../collections/domain/repositories/collection_auth_repository.dart';
import '../../defaults/domain/usecases/resolve_request_defaults_usecase.dart';
import '../../documentation/domain/services/secret_masker.dart';
import '../../environments/domain/repositories/environment_repository.dart';
import '../../request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import '../../request_builder/domain/usecases/list_variables_usecase.dart';
import '../../request_builder/domain/usecases/prepare_request_usecase.dart';
import '../../settings/domain/repositories/request_settings_repository.dart';
import '../../settings/domain/repositories/settings_repository.dart';
import '../domain/entities/auth_doctor_input.dart';
import '../domain/entities/auth_finding.dart';
import '../domain/services/auth_doctor.dart';
import '../domain/usecases/build_auth_doctor_input_usecase.dart';

/// What the dialog and the banner use to turn a rejected response into the doctor's input.
typedef AuthDoctorInputBuilder = UseCase<AuthDoctorInput, AuthDoctorSubject>;

/// The builder the app wires from what it registered, the way the response tools build the request they show; null when the app
/// does not have what it needs (a test harness), in which case the doctor works from the saved request and the response alone.
AuthDoctorInputBuilder? appAuthDoctorInputBuilder() {
  if (!locator.isRegistered<BuildVariableResolverUseCase>() ||
      !locator.isRegistered<CollectionAuthRepository>() ||
      !locator.isRegistered<ListVariablesUseCase>() ||
      !locator.isRegistered<EnvironmentRepository>()) {
    return null;
  }
  return BuildAuthDoctorInputUseCase(
    PrepareRequestUseCase(
      locator<BuildVariableResolverUseCase>(),
      locator<CollectionAuthRepository>(),
      settings: locator.isRegistered<SettingsRepository>() ? locator<SettingsRepository>() : null,
      requestSettings: locator.isRegistered<RequestSettingsRepository>() ? locator<RequestSettingsRepository>() : null,
      defaults: locator.isRegistered<ResolveRequestDefaultsUseCase>() ? locator<ResolveRequestDefaultsUseCase>() : null,
    ),
    locator<ListVariablesUseCase>(),
    locator<EnvironmentRepository>(),
  );
}

enum AuthDoctorStatus { loading, ready, failed }

/// Backs the "Why was I rejected?" dialog: gathers the input once and keeps the findings.
final class AuthDoctorViewModel with ChangeNotifier {
  final AuthDoctorSubject subject;
  final AuthDoctorInputBuilder? _builder;

  AuthDoctorViewModel(this.subject, {this._builder});

  AuthDoctorStatus status = AuthDoctorStatus.loading;
  AuthDoctorInput? input;
  List<AuthFinding> findings = const [];
  String? error;
  bool _disposed = false;

  /// `401 Unauthorized`.
  String get statusLine => '${subject.response.statusCode} ${subject.response.statusMessage}'.trim();

  /// `GET https://api.example.com/v1/orders`: the request as it was sent when known, with anything secret in the address masked.
  String get requestLine {
    final url = input?.url ?? subject.request.url;
    final path = Uri.tryParse(url);
    final shown = path == null || path.host.isEmpty ? url : '${path.scheme}://${path.host}${path.hasPort ? ':${path.port}' : ''}${path.path}';
    return '${subject.request.method.label} ${SecretMasker.maskUrl(shown)}';
  }

  Future<void> load() async {
    status = AuthDoctorStatus.loading;
    error = null;
    notifyListeners();
    try {
      final builder = _builder;
      final built = builder == null ? _fromSavedRequest() : await builder(subject);
      input = built;
      findings = AuthDoctor.diagnose(built);
      status = AuthDoctorStatus.ready;
    } catch (e) {
      error = 'The doctor could not read the request: ${SecretMasker.maskMessage('$e')}';
      status = AuthDoctorStatus.failed;
    }
    if (!_disposed) notifyListeners();
  }

  /// Without the variable stores the request cannot be rebuilt as sent, so the doctor makes no claim about what it carried.
  AuthDoctorInput _fromSavedRequest() => AuthDoctorInput(
        method: subject.request.method.label,
        url: subject.request.url,
        authType: subject.request.auth.type,
        requestKnown: false,
        status: subject.response.statusCode,
        responseHeaders: subject.response.headers,
        responseBody: utf8.decode(subject.response.bodyBytes.take(64 * 1024).toList(), allowMalformed: true),
        now: subject.receivedAt ?? DateTime.now(),
      );

  /// The whole diagnosis as plain text, for a bug report.
  String get report => [
        'Why was I rejected? $statusLine, $requestLine',
        '',
        if (findings.isEmpty) 'Nothing to report.' else for (final f in findings) '${f.toPlainText()}\n',
      ].join('\n').trimRight();

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
