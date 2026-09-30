import 'code_generator.dart';
import 'csharp_httpclient_generator.dart';
import 'curl_generator.dart';
import 'dart_http_generator.dart';
import 'go_net_http_generator.dart';
import 'httpie_generator.dart';
import 'java_okhttp_generator.dart';
import 'javascript_fetch_generator.dart';
import 'kotlin_okhttp_generator.dart';
import 'node_axios_generator.dart';
import 'php_curl_generator.dart';
import 'powershell_generator.dart';
import 'python_requests_generator.dart';
import 'r_httr_generator.dart';
import 'ruby_net_http_generator.dart';
import 'rust_reqwest_generator.dart';
import 'swift_urlsession_generator.dart';
import 'wget_generator.dart';

/// Menu order: cURL stays first (it is the dialog's default), then the other
/// command-line tools, then languages roughly by how often they call HTTP APIs.
abstract final class CodeGeneratorRegistry {
  static const List<CodeGenerator> all = [
    CurlGenerator(ansiC: true),
    HttpieGenerator(),
    WgetGenerator(),
    JavaScriptFetchGenerator(),
    NodeAxiosGenerator(),
    PythonRequestsGenerator(),
    GoNetHttpGenerator(),
    JavaOkHttpGenerator(),
    KotlinOkHttpGenerator(),
    CSharpHttpClientGenerator(),
    PhpCurlGenerator(),
    RubyNetHttpGenerator(),
    SwiftUrlSessionGenerator(),
    RustReqwestGenerator(),
    DartHttpGenerator(),
    PowerShellGenerator(),
    RHttrGenerator(),
  ];
}
