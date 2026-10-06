// The production lock for Odoo 18 and older: `/web/dataset/call_kw` and `/jsonrpc` carry the model and the method in
// the JSON body, so the body is what says whether a request reads, writes or removes.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/safety/domain/services/production_detector.dart';

RequestEffect _classify(String url, [String? body, HttpMethod method = HttpMethod.post]) => ProductionDetector.classify(method, url: url, body: body);

String _callKw(String method, {String model = 'res.partner', Object args = const []}) => jsonEncode({
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {'model': model, 'method': method, 'args': args, 'kwargs': <String, Object?>{}},
      'id': 1,
    });

String _execute(String service, String method, List<Object?> args, {String envelope = 'call'}) => jsonEncode({
      'jsonrpc': '2.0',
      'method': envelope,
      'params': {'service': service, 'method': method, 'args': args},
      'id': 1,
    });

const _host = 'https://odoo.test';

void main() {
  group('call_kw with the model and method in the URL (as before)', () {
    test('without a body the URL decides', () {
      expect(_classify('$_host/web/dataset/call_kw/res.partner/search_read'), RequestEffect.read);
      expect(_classify('$_host/web/dataset/call_kw/res.partner/write'), RequestEffect.write);
      expect(_classify('$_host/web/dataset/call_kw/res.partner/unlink'), RequestEffect.destructive);
      expect(_classify('{{odooUrl}}/web/dataset/call_kw/res.partner/{{method}}'), RequestEffect.write);
    });

    test('a body that agrees changes nothing', () {
      expect(_classify('$_host/web/dataset/call_kw/res.partner/search_read', _callKw('search_read')), RequestEffect.read);
      expect(_classify('$_host/web/dataset/call_kw/res.partner/unlink', _callKw('unlink')), RequestEffect.destructive);
    });

    test('a body can make the request stricter than its URL, never more lenient', () {
      // Odoo takes the model and the method from the body: the tail of the URL is only a label.
      expect(_classify('$_host/web/dataset/call_kw/res.partner/search_read', _callKw('unlink')), RequestEffect.destructive);
      expect(_classify('$_host/web/dataset/call_kw/res.partner/search_read', _callKw('write')), RequestEffect.write);
      expect(_classify('$_host/web/dataset/call_kw/res.partner/write', _callKw('search_read')), RequestEffect.write);
      expect(_classify('$_host/web/dataset/call_kw/res.partner/unlink', _callKw('read')), RequestEffect.destructive);
    });

    test('a body that does not parse leaves the URL in charge', () {
      expect(_classify('$_host/web/dataset/call_kw/res.partner/search_read', '{broken'), RequestEffect.read);
      expect(_classify('$_host/web/dataset/call_kw/res.partner/search_read', '[1, 2]'), RequestEffect.read);
    });
  });

  group('call_kw to a bare path', () {
    test('reads, writes and removals are told by the method of the body', () {
      for (final read in ['search_read', 'read', 'search_count', 'fields_get', 'name_search', 'default_get', 'exists', 'read_group', 'web_search_read']) {
        expect(_classify('$_host/web/dataset/call_kw', _callKw(read)), RequestEffect.read, reason: read);
      }
      for (final write in ['create', 'write', 'copy', 'action_archive', 'action_confirm', 'button_validate', 'some_custom_method']) {
        expect(_classify('$_host/web/dataset/call_kw', _callKw(write)), RequestEffect.write, reason: write);
      }
      for (final remove in ['unlink', 'action_unlink_all', 'remove_line', 'purge']) {
        expect(_classify('$_host/web/dataset/call_kw', _callKw(remove)), RequestEffect.destructive, reason: remove);
      }
    });

    test('is a write when nothing says it is a read: no body, no method, a variable for the method, a batch', () {
      expect(_classify('$_host/web/dataset/call_kw'), RequestEffect.write);
      expect(_classify('$_host/web/dataset/call_kw', ''), RequestEffect.write);
      expect(_classify('$_host/web/dataset/call_kw', '{broken'), RequestEffect.write);
      expect(_classify('$_host/web/dataset/call_kw', jsonEncode({'jsonrpc': '2.0', 'method': 'call', 'params': {'model': 'res.partner'}})), RequestEffect.write);
      expect(_classify('$_host/web/dataset/call_kw', '{"params": {"model": "res.partner", "method": "{{method}}", "args": []}}'), RequestEffect.write);
      expect(_classify('$_host/web/dataset/call_kw', '{"params": {"model": "res.partner", "method": {{method}}, "args": []}}'), RequestEffect.write);
      expect(_classify('$_host/web/dataset/call_kw', '[{"params": {"model": "res.partner", "method": "search_read"}}]'), RequestEffect.write);
    });

    test('a {{variable}} where an id goes does not hide the method', () {
      expect(_classify('{{odooUrl}}/web/dataset/call_kw', '{"jsonrpc": "2.0", "method": "call", "params": {"model": "res.partner", "method": "unlink", "args": [[{{recordId}}]], "kwargs": {}}}'), RequestEffect.destructive);
      expect(_classify('{{odooUrl}}/web/dataset/call_kw', '{"jsonrpc": "2.0", "method": "call", "params": {"model": "res.partner", "method": "read", "args": [[{{recordId}}]], "kwargs": {}}}'), RequestEffect.read);
      expect(_classify('{{odooUrl}}/web/dataset/call_kw', '{"params": {"model": "res.partner", "method": "search_read", "args": [[["parent_id", "=", {{xmlid:base.main_partner}}]]]}}'), RequestEffect.read);
    });

    test('the envelope\'s own "method": "call" is not the Odoo method, and params may sit at the top', () {
      expect(_classify('$_host/web/dataset/call_kw', '{"method": "call"}'), RequestEffect.write);
      expect(_classify('$_host/web/dataset/call_kw', '{"model": "res.partner", "method": "unlink", "args": [[1]]}'), RequestEffect.destructive);
      expect(_classify('$_host/web/dataset/call_kw', '{"model": "res.partner", "method": "search_read", "args": []}'), RequestEffect.read);
    });

    test('the method is matched without regard to case', () {
      expect(_classify('$_host/web/dataset/call_kw', _callKw('Search_Read')), RequestEffect.read);
      expect(_classify('$_host/web/dataset/call_kw', _callKw('UNLINK')), RequestEffect.destructive);
    });

    test('GET, HEAD, OPTIONS and DELETE are still decided by their verb', () {
      expect(_classify('$_host/web/dataset/call_kw', _callKw('unlink'), HttpMethod.get), RequestEffect.read);
      expect(_classify('$_host/web/dataset/call_kw', _callKw('search_read'), HttpMethod.delete), RequestEffect.destructive);
    });
  });

  group('the other JSON-RPC endpoints', () {
    test('call_button runs a button: a write unless the body proves a read', () {
      expect(_classify('$_host/web/dataset/call_button', _callKw('action_confirm')), RequestEffect.write);
      expect(_classify('$_host/web/dataset/call_button', _callKw('unlink')), RequestEffect.destructive);
      expect(_classify('$_host/web/dataset/call_button'), RequestEffect.write);
    });

    test('search_read only reads, whatever its body says', () {
      expect(_classify('$_host/web/dataset/search_read', '{"params": {"model": "res.partner", "domain": [], "fields": ["name"]}}'), RequestEffect.read);
      expect(_classify('$_host/web/dataset/search_read'), RequestEffect.read);
    });

    test('/jsonrpc object calls are told by the method inside execute_kw and execute', () {
      expect(_classify('$_host/jsonrpc', _execute('object', 'execute_kw', ['prod', 2, 'pw', 'res.partner', 'search_read', [[]]])), RequestEffect.read);
      expect(_classify('$_host/jsonrpc', _execute('object', 'execute_kw', ['prod', 2, 'pw', 'res.partner', 'create', [{'name': 'A'}]])), RequestEffect.write);
      expect(_classify('$_host/jsonrpc', _execute('object', 'execute_kw', ['prod', 2, 'pw', 'res.partner', 'unlink', [[1]]])), RequestEffect.destructive);
      expect(_classify('$_host/jsonrpc', _execute('object', 'execute', ['prod', 2, 'pw', 'res.partner', 'unlink', [1]])), RequestEffect.destructive);
      expect(_classify('$_host/jsonrpc', _execute('object', 'execute_kw', ['prod', 2])), RequestEffect.write, reason: 'no method to read');
    });

    test('/jsonrpc common and db services', () {
      expect(_classify('$_host/jsonrpc', _execute('common', 'login', ['prod', 'admin', 'pw'])), RequestEffect.read);
      expect(_classify('$_host/jsonrpc', _execute('common', 'version', [])), RequestEffect.read);
      expect(_classify('$_host/jsonrpc', _execute('common', 'something_else', [])), RequestEffect.write);
      expect(_classify('$_host/jsonrpc', _execute('db', 'list', [])), RequestEffect.read);
      expect(_classify('$_host/jsonrpc', _execute('db', 'server_version', [])), RequestEffect.read);
      expect(_classify('$_host/jsonrpc', _execute('db', 'drop', ['admin', 'prod'])), RequestEffect.destructive);
      expect(_classify('$_host/jsonrpc', _execute('db', 'dump', ['admin', 'prod'])), RequestEffect.write);
      expect(_classify('$_host/jsonrpc', _execute('db', 'create_database', [])), RequestEffect.write);
      expect(_classify('$_host/jsonrpc', 'x'), RequestEffect.write);
    });

    test('logging in changes no data', () {
      expect(_classify('$_host/web/session/authenticate', '{"jsonrpc": "2.0", "method": "call", "params": {"db": "d", "login": "l", "password": "p"}}'), RequestEffect.read);
      expect(_classify('{{odooUrl}}/web/session/authenticate'), RequestEffect.read);
      expect(_classify('$_host/web/session/get_session_info', '{}'), RequestEffect.read);
      expect(_classify('$_host/web/database/list', '{}'), RequestEffect.read);
      expect(_classify('$_host/web/session/authenticate_other', '{}'), RequestEffect.write);
    });
  });

  group('what is unchanged', () {
    test('JSON-2 is still told by the URL, and unrelated POSTs are still writes', () {
      expect(_classify('$_host/json/2/res.partner/search_read', _callKw('unlink')), RequestEffect.read, reason: 'JSON-2 has no method in its body');
      expect(_classify('$_host/json/2/res.partner/unlink', '{"ids": [1]}'), RequestEffect.destructive);
      expect(_classify('https://api.example.com/web/dataset/other', _callKw('search_read')), RequestEffect.write);
      expect(_classify('https://api.example.com/users', '{"query": "{ users { id } }"}'), RequestEffect.read, reason: 'a GraphQL query');
    });
  });
}
