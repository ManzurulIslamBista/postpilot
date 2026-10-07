import 'dart:convert';
import '../../../../core/enums/body_type.dart';
import '../../../../core/enums/http_method.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../git_sync/domain/services/secret_names.dart';
import '../../../import_export/domain/services/imported_body_mapper.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_body.dart';
import '../entities/recorded_exchange.dart';
import 'path_normalizer.dart';
import 'recorder_headers.dart';
import 'traffic_masking.dart';

/// Why the body of a recorded request is not in the request made from it.
enum BodyOmitted {
  /// A multipart form: the boundary and the files belong to that one send.
  multipart,

  /// Not text (an image upload, protobuf, a compressed file).
  binary,

  /// Cut at the recorder's size limit, so it would not be the body the app sent.
  tooLarge,
}

/// A recorded call as a PostPilot request, before it is saved: no credential in it, only `{{variables}}` where there was one.
final class RequestDraft {
  /// `GET /users/{userId}`.
  final String name;
  final HttpMethod method;

  /// `{{baseUrl}}/users/{{userId}}?page=2`.
  final String url;
  final List<KeyValueItem> headers;
  final RequestBody body;

  /// The identifiers the path contained and their values in this call.
  final List<PathVariable> pathVariables;

  /// The names of the secret variables the request uses (`token`, `apiKey`); they are created empty.
  final Set<String> secretVariables;
  final BodyOmitted? bodyOmitted;

  const RequestDraft({
    required this.name,
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
    required this.pathVariables,
    required this.secretVariables,
    this.bodyOmitted,
  });
}

/// Turns a [RecordedExchange] into a request: transport headers dropped, credentials replaced by secret variables
/// (`Authorization: Bearer {{token}}`, `X-Api-Key: {{apiKey}}`, `"password": "{{password}}"`), ids in the path made
/// variables. The same code serves "Resend in PostPilot" and "Create collection from recording".
abstract final class RecordedRequestMapper {
  static const _noBodyHeaders = {'content-encoding'};

  /// [baseUrl] is the upstream's base address. With [useBaseUrlVariable] the URL starts with `{{baseUrl}}`, otherwise with the
  /// address itself. With [templatePath] ids in the path become variables.
  static RequestDraft map(
    RecordedExchange e, {
    required String baseUrl,
    bool useBaseUrlVariable = true,
    bool templatePath = true,
  }) {
    final secrets = <String>{};
    final question = e.path.indexOf('?');
    final pathOnly = question == -1 ? e.path : e.path.substring(0, question);
    final query = question == -1 ? null : e.path.substring(question + 1);
    final normalized = templatePath ? PathNormalizer.normalize(pathOnly) : NormalizedPath(pathOnly, const []);
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    var url = '${useBaseUrlVariable ? '{{baseUrl}}' : base}${normalized.template}';
    if (query != null) url = '$url?${_scrubQuery(query, secrets)}';
    url = SecretMasker.maskUrl(url);

    final (body, omitted) = _bodyOf(e, secrets);
    final dropContentType = omitted == BodyOmitted.multipart;
    return RequestDraft(
      name: '${e.method} ${normalized.display}',
      method: HttpMethod.fromString(e.method),
      url: url,
      headers: _headersOf(e, secrets, dropContentType: dropContentType, dropEncoding: !body.type.isNone),
      body: body,
      pathVariables: normalized.variables,
      secretVariables: secrets,
      bodyOmitted: omitted,
    );
  }

  /// `X-Api-Key` -> `apiKey`, `access_token` -> `accessToken`, `Authorization` -> `token`.
  static String variableNameFor(String key) {
    if (key.toLowerCase() == 'authorization') return 'token';
    final words = [
      for (final w in key.split(RegExp(r'[^A-Za-z0-9]+|(?<=[a-z0-9])(?=[A-Z])')))
        if (w.isNotEmpty) w.toLowerCase(),
    ];
    if (words.length > 1 && words.first == 'x') words.removeAt(0);
    if (words.isEmpty) return 'secret';
    if (!RegExp(r'^[a-z]').hasMatch(words.first)) words.insert(0, 'secret');
    return words.first + [for (final w in words.skip(1)) w[0].toUpperCase() + w.substring(1)].join();
  }

  static List<KeyValueItem> _headersOf(
    RecordedExchange e,
    Set<String> secrets, {
    required bool dropContentType,
    required bool dropEncoding,
  }) {
    final merged = <String, List<String>>{};
    final names = <String, String>{};
    final hostHeader = e.requestHeader('host');
    for (final h in e.requestHeaders) {
      final lower = h.name.toLowerCase();
      if (TrafficMasking.transportHeaders.contains(lower) || RecorderHeaders.hopByHop.contains(lower)) continue;
      if (dropContentType && lower == 'content-type') continue;
      if (dropEncoding && _noBodyHeaders.contains(lower)) continue;
      // The recorder's own address in these says nothing about the real server, and it differs on every device.
      if ((lower == 'origin' || lower == 'referer') && _pointsAtRecorder(h.value, hostHeader)) continue;
      (merged[lower] ??= []).add(h.value);
      names.putIfAbsent(lower, () => _titleCase(h.name));
    }
    return [
      for (final entry in merged.entries)
        KeyValueItem(
          key: names[entry.key]!,
          value: _headerValue(names[entry.key]!, entry.key == 'cookie' ? entry.value.join('; ') : entry.value.join(', '), secrets),
        ),
    ];
  }

  static bool _pointsAtRecorder(String value, String? hostHeader) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty) return false;
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final hostPort = hostHeader == null ? null : int.tryParse(hostHeader.split(':').last);
    return RecorderHeaders.isRecorderAddress(uri, hostHeader: hostHeader, localPort: hostPort ?? port);
  }

  static String _headerValue(String name, String value, Set<String> secrets) {
    if (!SecretNames.hasLiteralSecret(value)) return value;
    final lower = name.toLowerCase();
    if (lower == 'authorization') {
      final scheme = RegExp(r'^(\w+)\s+\S').firstMatch(value.trim())?.group(1);
      final variable = switch (scheme?.toLowerCase()) {
        null => 'token',
        'bearer' => 'token',
        final s => '${s}Credentials',
      };
      secrets.add(variable);
      return scheme == null ? '{{$variable}}' : '$scheme {{$variable}}';
    }
    if (TrafficMasking.isSecretHeader(name) || SecretNames.knownTokens(value).isNotEmpty) {
      final variable = variableNameFor(name);
      secrets.add(variable);
      return '{{$variable}}';
    }
    return value;
  }

  static String _titleCase(String name) => name
      .split('-')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join('-');

  /// [query] with the value of every secret parameter replaced by a variable named after the parameter.
  static String _scrubQuery(String query, Set<String> secrets) => query.split('&').map((pair) {
        final equals = pair.indexOf('=');
        if (equals <= 0) return pair;
        final rawName = pair.substring(0, equals);
        final rawValue = pair.substring(equals + 1);
        final name = _decode(rawName);
        final value = _decode(rawValue);
        if (value.isEmpty || !SecretNames.hasLiteralSecret(value)) return pair;
        if (SecretNames.isSecretQuery(name) || SecretMasker.isSensitiveName(name) || SecretNames.knownTokens(value).isNotEmpty) {
          final variable = variableNameFor(name);
          secrets.add(variable);
          return '$rawName={{$variable}}';
        }
        return pair;
      }).join('&');

  static (RequestBody, BodyOmitted?) _bodyOf(RecordedExchange e, Set<String> secrets) {
    if (!e.hasRequestBody) return (RequestBody.empty, null);
    final mime = (e.requestContentType ?? '').split(';').first.trim().toLowerCase();
    if (mime.startsWith('multipart/')) return (RequestBody.empty, BodyOmitted.multipart);
    if (e.requestBodyTruncated) return (RequestBody.empty, BodyOmitted.tooLarge);
    final text = e.requestText;
    if (text == null) return (RequestBody.empty, BodyOmitted.binary);
    if (mime.contains('x-www-form-urlencoded')) {
      return (RequestBody(type: BodyType.urlEncoded, urlEncodedFields: _formFields(text, secrets)), null);
    }
    final raw = mime.isEmpty ? ImportedBodyMapper.sniffRawType(text) : ImportedBodyMapper.rawTypeOf(mime);
    return (RequestBody(type: BodyType.raw, rawContentType: raw, rawText: _scrubBody(text, raw == RawContentType.json, secrets)), null);
  }

  static List<KeyValueItem> _formFields(String text, Set<String> secrets) => [
        for (final pair in text.split('&'))
          if (pair.isNotEmpty) _formField(pair, secrets),
      ];

  static KeyValueItem _formField(String pair, Set<String> secrets) {
    final equals = pair.indexOf('=');
    final key = _decode(equals == -1 ? pair : pair.substring(0, equals));
    final value = equals == -1 ? '' : _decode(pair.substring(equals + 1));
    if (value.isNotEmpty && SecretNames.hasLiteralSecret(value) && (SecretNames.looksSecretKey(key) || SecretMasker.isSensitiveName(key))) {
      final variable = variableNameFor(key);
      secrets.add(variable);
      return KeyValueItem(key: key, value: '{{$variable}}');
    }
    return KeyValueItem(key: key, value: SecretMasker.maskValue(key, value));
  }

  /// [text] with the value of secret fields replaced by variables. JSON keeps its shape (and is only rewritten when it held a
  /// secret); anything else is masked by the app's [SecretMasker].
  static String _scrubBody(String text, bool json, Set<String> secrets) {
    if (json) {
      try {
        final found = <String>{};
        final scrubbed = _scrubJson(jsonDecode(text), null, found);
        if (found.isNotEmpty) {
          secrets.addAll(found);
          return SecretMasker.maskBody(const JsonEncoder.withIndent('  ').convert(scrubbed));
        }
      } on FormatException {
        // Not JSON after all: masked as text below.
      }
    }
    return SecretMasker.maskBody(text);
  }

  static Object? _scrubJson(Object? node, String? key, Set<String> found) {
    switch (node) {
      case Map<String, dynamic>():
        return {for (final e in node.entries) e.key: _scrubJson(e.value, e.key, found)};
      case List<dynamic>():
        return [for (final item in node) _scrubJson(item, key, found)];
      case String():
        if (key != null && node.isNotEmpty && SecretNames.hasLiteralSecret(node) && SecretNames.isSecretBodyKey(key, node)) {
          final variable = variableNameFor(key);
          found.add(variable);
          return '{{$variable}}';
        }
        return node;
      case num():
        if (key != null && SecretNames.isNumericSecretKey(key)) {
          final variable = variableNameFor(key);
          found.add(variable);
          return '{{$variable}}';
        }
        return node;
      default:
        return node;
    }
  }

  static String _decode(String text) {
    try {
      return Uri.decodeQueryComponent(text);
    } catch (_) {
      return text;
    }
  }
}

extension on BodyType {
  bool get isNone => this == BodyType.none;
}
