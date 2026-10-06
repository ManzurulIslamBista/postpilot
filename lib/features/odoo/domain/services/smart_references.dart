// Pure Dart (no Flutter): the app, the collection runner and the command line all resolve these tokens.
import '../../../../core/utils/variable_resolver.dart';
import '../../../request_builder/domain/services/undefined_variables.dart';

/// What a smart reference asks for.
enum SmartReferenceKind {
  /// `{{xmlid:base.main_company}}`: the id of the record with that XML-ID (an `ir.model.data` entry).
  xmlId,

  /// `{{ref:res.partner:Azure Interior}}`: the id of the record of that model that has exactly that name.
  name,
}

/// A parsed `{{xmlid:...}}` or `{{ref:...}}` token.
final class SmartReference {
  final SmartReferenceKind kind;

  /// `xmlid:base.main_company` or `ref:res.country:BD`: the token without its braces, the key it is resolved under.
  final String key;

  /// For [SmartReferenceKind.xmlId] the module and the name (`base`, `main_company`); empty for a name reference.
  final String module;
  final String xmlName;

  /// For [SmartReferenceKind.name] the model and the name looked for; empty for an XML-ID.
  final String model;
  final String recordName;

  const SmartReference._(this.kind, this.key, {this.module = '', this.xmlName = '', this.model = '', this.recordName = ''});

  String get token => '{{$key}}';

  /// What the person wrote, as a short noun phrase for a message: `XML-ID base.foo`, `res.partner "Azure Interior"`.
  String get describe => kind == SmartReferenceKind.xmlId ? 'XML-ID $module.$xmlName' : '$model "$recordName"';

  /// The token's inner text [key] read as a reference. Null when it is not shaped like one (an XML-ID needs a dot,
  /// a name reference needs a model and a name); [SmartReferences.problemWith] says what is wrong with it.
  static SmartReference? tryParse(String key) {
    if (key.startsWith('xmlid:')) {
      final id = key.substring(6).trim();
      final dot = id.indexOf('.');
      if (dot <= 0 || dot == id.length - 1 || id.contains(RegExp(r'\s'))) return null;
      return SmartReference._(SmartReferenceKind.xmlId, key, module: id.substring(0, dot), xmlName: id.substring(dot + 1));
    }
    if (key.startsWith('ref:')) {
      final rest = key.substring(4);
      final colon = rest.indexOf(':');
      if (colon <= 0) return null;
      final model = rest.substring(0, colon).trim();
      final name = rest.substring(colon + 1).trim();
      if (name.isEmpty || !RegExp(r'^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$').hasMatch(model)) return null;
      return SmartReference._(SmartReferenceKind.name, key, model: model, recordName: name);
    }
    return null;
  }
}

/// A smart reference that could not be turned into an id. [message] says why and is safe to show as it is; a request
/// with such a token is not sent, so the literal `{{xmlid:...}}` can never reach a server.
final class SmartReferenceException implements Exception {
  final String message;
  const SmartReferenceException(this.message);

  @override
  String toString() => message;
}

/// What a lookup needs to know about the request that carries the tokens: where it goes and as whom. The server is
/// the one the request itself is sent to, so a token is looked up in the database the request will change.
final class SmartReferenceContext {
  /// The request's URL with its `{{variables}}` resolved.
  final String url;

  /// The request's headers, resolved: the bearer token and the database of a JSON-2 call.
  final Map<String, String> headers;

  /// A variable of the request's scopes (`odooLogin`, `odooPassword`, `odooDb`...), or null.
  final String? Function(String name) variable;

  const SmartReferenceContext({required this.url, required this.headers, required this.variable});
}

/// Turns smart references into record ids by asking the live server.
abstract interface class SmartReferenceResolver {
  /// The id (as text) of each of [keys] (the `xmlid:...` / `ref:...` text of a token). Throws a
  /// [SmartReferenceException] for the first one that cannot be resolved.
  Future<Map<String, String>> resolve(SmartReferenceContext context, Iterable<String> keys);
}

abstract final class SmartReferences {
  /// A token as written in a request: `{{xmlid:module.name}}` or `{{ref:model:name}}`. The name may hold spaces and
  /// punctuation but no `{` or `}`. The same pattern the variable resolver reads.
  static final tokenPattern = VariableResolver.smartTokenPattern;

  static bool isSmartKey(String name) => name.startsWith('xmlid:') || name.startsWith('ref:');

  static bool hasAny(String text) => text.contains('{{') && tokenPattern.hasMatch(text);

  /// The smart references among the variables a request leaves undefined, in order of first use.
  static List<String> pendingKeys(Iterable<UndefinedVariable> undefined) => [
        for (final v in undefined)
          if (isSmartKey(v.name)) v.name,
      ];

  /// The undefined variables that are ordinary variables.
  static List<UndefinedVariable> ordinary(Iterable<UndefinedVariable> undefined) => [
        for (final v in undefined)
          if (!isSmartKey(v.name)) v,
      ];

  /// What is wrong with a token's wording, or null when it is well formed.
  static String? problemWith(String key) {
    if (SmartReference.tryParse(key) != null) return null;
    if (key.startsWith('xmlid:')) {
      return '{{$key}} is not an XML-ID: write it as module.name, for example {{xmlid:base.main_company}}.';
    }
    return '{{$key}} is not a reference: write it as {{ref:model:name}}, for example {{ref:res.country:BD}}.';
  }

  /// The message a request is refused with when it holds smart references and nothing can look them up.
  static String unavailable(Iterable<String> keys) =>
      'The request uses ${keys.map((k) => '{{$k}}').join(', ')}, which is looked up on the Odoo server when the request is sent, '
      'and no lookup is available here. The request was not sent.';
}
