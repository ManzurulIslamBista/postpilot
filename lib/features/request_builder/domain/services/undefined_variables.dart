import '../../../../core/errors/app_exception.dart';
import '../../../documentation/domain/services/secret_masker.dart';

/// A `{{variable}}` a request uses that no scope defines, with where it sits
/// (`the URL`, `the "X-Token" header`, ...), each place worded to read after "in".
final class UndefinedVariable {
  final String name;
  final List<String> places;

  /// Whether one of [places] is the request body, where `{{text}}` is often
  /// meant literally (a mustache template sent to an email API, say).
  final bool inBody;

  const UndefinedVariable(this.name, this.places, {this.inBody = false});

  String get token => '{{$name}}';
}

/// Turns what `RequestSpecBuilder.undefinedVariables` found into the error a
/// send fails with. Without it the request goes out with the literal `{{name}}`
/// in it: in a URL's host Dart percent-escapes the braces rather than
/// rejecting them, so `{{baseUrl}}/users` with no environment selected is
/// looked up in DNS as `%7b%7bbaseurl%7d%7d` and the user is told the server is
/// unreachable.
abstract final class UndefinedVariables {
  static final _hostPlaceholder = RegExp(r'^\s*[a-zA-Z][\w+.-]*://[^/?#]*\{\{[\w.$-]+\}\}');

  /// The URL is quoted (masked) only when a placeholder sits in its host: then
  /// it is not a URL at all, which is what the user otherwise has to guess.
  static InvalidRequestException exception(List<UndefinedVariable> variables, String resolvedUrl) {
    final one = variables.length == 1;
    final tokens = [for (final v in variables) '${v.token} (used in ${_join(v.places)})'];
    final what = one ? '${tokens.single} is not defined' : 'These variables are not defined: ${tokens.join(', ')}';
    final fix = 'Select an environment, or add ${one ? 'it' : 'them'} to the collection variables or the globals.';
    // A variable whose value is its own token stays literal (see VariableResolver), so it can be sent as text.
    final bodyVariable = variables.where((v) => v.inBody).firstOrNull;
    final literal = bodyVariable == null
        ? ''
        : ' To send ${bodyVariable.token} as plain text instead, define a variable named ${bodyVariable.name} '
            'whose value is ${bodyVariable.token}.';
    final url = _hostPlaceholder.hasMatch(resolvedUrl)
        ? 'Not a valid http(s) URL: "${SecretMasker.maskUrl(resolvedUrl.trim())}". '
        : '';
    return InvalidRequestException('$url$what. $fix$literal');
  }

  static String _join(List<String> places) => switch (places.length) {
        1 => places.single,
        2 => '${places.first} and ${places.last}',
        _ => '${places.sublist(0, places.length - 1).join(', ')} and ${places.last}',
      };
}
