import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/documentation/domain/entities/api_docs_model.dart';
import 'package:postpilot/features/documentation/domain/entities/markdown_node.dart';
import 'package:postpilot/features/documentation/domain/services/api_docs_generator.dart';
import 'package:postpilot/features/documentation/domain/services/markdown_parser.dart';

const _small = ApiDocsModel(
  name: 'Shop API',
  description: 'Public **shop** API.',
  tags: ['v2'],
  authSummary: 'Bearer Token',
  variables: [ApiDocsField('baseUrl', 'https://api.example.com')],
  folders: [
    ApiDocsFolder(
      name: 'Users',
      description: 'All about users.',
      requests: [
        ApiDocsRequest(
          name: 'List users',
          method: 'GET',
          url: '{{baseUrl}}/users',
          queryParams: [ApiDocsField('page', '1')],
          headers: [ApiDocsField('Accept', 'application/json')],
          examples: [ApiDocsExample(name: 'OK', statusCode: 200, body: '{"users": []}')],
        ),
      ],
    ),
  ],
  requests: [ApiDocsRequest(name: 'Health', method: 'GET', url: '{{baseUrl}}/health')],
);

const _nested = ApiDocsModel(
  name: 'Nested',
  folders: [
    ApiDocsFolder(
      name: 'Users',
      tags: ['users'],
      folders: [
        ApiDocsFolder(
          name: 'Admin',
          folders: [
            ApiDocsFolder(
              name: 'Deep',
              requests: [ApiDocsRequest(name: 'Purge', method: 'DELETE', url: '/purge')],
            ),
          ],
          requests: [ApiDocsRequest(name: 'Ban user', method: 'POST', url: '/ban')],
        ),
      ],
      requests: [ApiDocsRequest(name: 'List users', method: 'GET', url: '/users', tags: ['read', 'v3'])],
    ),
    ApiDocsFolder(name: 'Empty'),
  ],
  requests: [ApiDocsRequest(name: 'Health', method: 'GET', url: '/health')],
);

List<String> _headings(String markdown) => [
      for (final block in MarkdownParser.parse(markdown))
        if (block is MarkdownHeading) '${'#' * block.level} ${(block.content.single as MarkdownText).text}',
    ];

void main() {
  group('toMarkdown', () {
    test('writes the whole document in a fixed layout', () {
      expect(ApiDocsGenerator.toMarkdown(_small), '''
# Shop API

**Tags:** `v2`

Public **shop** API.

**Authorization:** Bearer Token

## Variables

| Variable | Value |
| --- | --- |
| `baseUrl` | `https://api.example.com` |

## Users

All about users.

### List users

**GET** `{{baseUrl}}/users`

**Query parameters**

| Key | Value |
| --- | --- |
| `page` | `1` |

**Headers**

| Key | Value |
| --- | --- |
| `Accept` | `application/json` |

**Example: OK (200)**

```json
{"users": []}
```

## Health

**GET** `{{baseUrl}}/health`
''');
    });

    test('an empty collection is just its title', () {
      expect(ApiDocsGenerator.toMarkdown(const ApiDocsModel(name: 'Empty')), '# Empty\n');
    });

    test('nests folders and requests one heading level per folder, folders before requests', () {
      expect(_headings(ApiDocsGenerator.toMarkdown(_nested)), [
        '# Nested',
        '## Users',
        '### Admin',
        '#### Deep',
        '##### Purge',
        '#### Ban user',
        '### List users',
        '## Empty',
        '## Health',
      ]);
    });

    test('never goes deeper than level six', () {
      var folder = const ApiDocsFolder(name: 'Bottom', requests: [ApiDocsRequest(name: 'R', method: 'GET', url: '/')]);
      for (var i = 0; i < 8; i++) {
        folder = ApiDocsFolder(name: 'F$i', folders: [folder]);
      }
      final headings = _headings(ApiDocsGenerator.toMarkdown(ApiDocsModel(name: 'Deep', folders: [folder])));
      expect(headings.every((h) => h.startsWith('#') && h.indexOf(' ') <= 6), isTrue);
      expect(headings.last, '###### R');
    });

    test('lists tags of the collection, folders and requests', () {
      final markdown = ApiDocsGenerator.toMarkdown(_nested);
      expect(markdown, contains('**Tags:** `users`'));
      expect(markdown, contains('**Tags:** `read`, `v3`'));
    });

    test('moves the headings of a description below the heading it sits under', () {
      final markdown = ApiDocsGenerator.toMarkdown(const ApiDocsModel(
        name: 'Api',
        description: '# Overview\ntext',
        folders: [
          ApiDocsFolder(
            name: 'F',
            description: '# Intro',
            requests: [ApiDocsRequest(name: 'R', method: 'GET', url: '/', description: '## Notes\n###### Deepest')],
          ),
        ],
      ));
      expect(_headings(markdown), [
        '# Api',
        '## Overview',
        '## F',
        '### Intro',
        '### R',
        '##### Notes',
        '###### Deepest',
      ]);
    });

    test('closes a code fence a description left open so later sections survive', () {
      final markdown = ApiDocsGenerator.toMarkdown(const ApiDocsModel(
        name: 'Api',
        requests: [
          ApiDocsRequest(name: 'A', method: 'GET', url: '/a', description: 'Run:\n```\ncurl /a'),
          ApiDocsRequest(name: 'B', method: 'GET', url: '/b'),
        ],
      ));
      expect(markdown, contains('```\ncurl /a\n```'));
      expect(_headings(markdown), ['# Api', '## A', '## B']);
    });

    test('escapes markdown in names and keeps values inside code', () {
      final markdown = ApiDocsGenerator.toMarkdown(const ApiDocsModel(
        name: r'a*b_c [x] <y> & z|w',
        requests: [
          ApiDocsRequest(
            name: 'Weird',
            method: 'GET',
            url: 'https://x/a`b|c',
            headers: [ApiDocsField('Accept', '*/*'), ApiDocsField('X-List', 'a|b')],
          ),
        ],
      ));
      expect(markdown, startsWith(r'# a\*b\_c \[x\] \<y\> \& z\|w'));
      expect(markdown, contains('**GET** ``https://x/a`b|c``'));
      expect(markdown, contains(r'| `Accept` | `*/*` |'));
      expect(markdown, contains(r'| `X-List` | `a\|b` |'));
    });

    test('a value with a pipe stays in its cell when the markdown is read back', () {
      final markdown = ApiDocsGenerator.toMarkdown(const ApiDocsModel(
        name: 'Api',
        requests: [
          ApiDocsRequest(name: 'R', method: 'GET', url: '/', headers: [ApiDocsField('X-List', 'a|b')]),
        ],
      ));
      final table = MarkdownParser.parse(markdown).whereType<MarkdownTable>().single;
      expect(table.rows.single, hasLength(2));
      expect((table.rows.single[1].single as MarkdownCode).code, 'a|b');
    });

    test('fences use more backticks than the code contains', () {
      final markdown = ApiDocsGenerator.toMarkdown(const ApiDocsModel(
        name: 'Api',
        requests: [
          ApiDocsRequest(
            name: 'R',
            method: 'GET',
            url: '/',
            examples: [ApiDocsExample(name: 'md', statusCode: 200, body: '```\nnested\n```')],
          ),
        ],
      ));
      expect(markdown, contains('````\n```\nnested\n```\n````'));
      expect(MarkdownParser.parse(markdown).whereType<MarkdownCodeBlock>().single.code, '```\nnested\n```');
    });

    test('renders each body kind', () {
      final markdown = ApiDocsGenerator.toMarkdown(const ApiDocsModel(
        name: 'Api',
        requests: [
          ApiDocsRequest(
            name: 'Raw',
            method: 'POST',
            url: '/raw',
            body: ApiDocsBody(typeLabel: 'JSON', language: 'json', text: '{"a": 1}'),
          ),
          ApiDocsRequest(
            name: 'Form',
            method: 'POST',
            url: '/form',
            body: ApiDocsBody(typeLabel: 'Form Data', fields: [ApiDocsField('name', 'Ann')]),
          ),
          ApiDocsRequest(
            name: 'Graph',
            method: 'POST',
            url: '/graphql',
            body: ApiDocsBody(typeLabel: 'GraphQL', language: 'graphql', text: '{ me { id } }', variablesText: '{"id": 1}'),
          ),
        ],
      ));
      expect(markdown, contains('**Body** (JSON)\n\n```json\n{"a": 1}\n```'));
      expect(markdown, contains('**Body** (Form Data)\n\n| Key | Value |\n| --- | --- |\n| `name` | `Ann` |'));
      expect(markdown, contains('```graphql\n{ me { id } }\n```'));
      expect(markdown, contains('**Variables**\n\n```json\n{"id": 1}\n```'));
    });

    test('shows the authorization summary of a request', () {
      final markdown = ApiDocsGenerator.toMarkdown(const ApiDocsModel(
        name: 'Api',
        requests: [ApiDocsRequest(name: 'R', method: 'GET', url: '/', authSummary: 'API Key')],
      ));
      expect(markdown, contains('**Authorization:** API Key'));
    });

    test('the output reads back as the same structure', () {
      final blocks = MarkdownParser.parse(ApiDocsGenerator.toMarkdown(_small));
      expect(blocks.whereType<MarkdownTable>(), hasLength(3));
      expect(blocks.whereType<MarkdownCodeBlock>().single.language, 'json');
    });
  });

  group('toHtml', () {
    final html = ApiDocsGenerator.toHtml(_nested);

    test('is one self-contained page', () {
      expect(html, startsWith('<!doctype html>'));
      expect(html, contains('<meta charset="utf-8">'));
      expect(html, contains('<meta name="viewport"'));
      expect(html, contains('<title>Nested</title>'));
      expect(html, contains('<style>'));
      for (final external in ['<link', '<script', '@import', ' src=', 'url(']) {
        expect(html, isNot(contains(external)), reason: external);
      }
    });

    test('has a table of contents whose links all point at a section', () {
      expect(html, contains('<nav aria-label="Contents">'));
      final targets = RegExp(r'href="#([^"]+)"').allMatches(html).map((m) => m[1]!).toSet();
      expect(targets, hasLength(8));
      for (final id in targets) {
        expect(html, contains('id="$id"'), reason: id);
      }
      expect(RegExp(r'<a href="#f1">Users</a>\s*<ul>[\s\S]*href="#f2"').hasMatch(html), isTrue);
    });

    test('nests folders and requests under one heading level per folder', () {
      for (final heading in [
        '<h1>Nested</h1>',
        '<h2>Users</h2>',
        '<h3>Admin</h3>',
        '<h4>Deep</h4>',
        '<h5>Purge</h5>',
        '<h4>Ban user</h4>',
        '<h3>List users</h3>',
        '<h2>Empty</h2>',
        '<h2>Health</h2>',
      ]) {
        expect(html, contains(heading), reason: heading);
      }
      expect(html.indexOf('<h2>Users</h2>'), lessThan(html.indexOf('<h3>Admin</h3>')));
      expect(html.indexOf('<h3>Admin</h3>'), lessThan(html.indexOf('<h2>Health</h2>')));
    });

    test('shows a badge per method and a pill per tag', () {
      expect(html, contains('<span class="badge delete">DELETE</span>'));
      expect(html, contains('<span class="badge post">POST</span>'));
      expect(html, contains('<span class="badge get">GET</span>'));
      expect(html, contains('<span class="tag">read</span>'));
      expect(html, contains('<span class="tag">v3</span>'));
      expect(html, contains('<span class="tag">users</span>'));
    });

    test('an unknown method gets a plain badge', () {
      final page = ApiDocsGenerator.toHtml(const ApiDocsModel(
        name: 'Api',
        requests: [ApiDocsRequest(name: 'X', method: 'PROPFIND', url: '/')],
      ));
      expect(page, contains('<span class="badge">PROPFIND</span>'));
    });

    test('escapes <, &, and both kinds of quotes everywhere', () {
      final page = ApiDocsGenerator.toHtml(const ApiDocsModel(
        name: '<script>alert(1)</script>',
        description: 'Use <b>tags</b> & "quotes"',
        tags: ['<x>'],
        variables: [ApiDocsField('a&b', '"q" \'s\'')],
        folders: [
          ApiDocsFolder(
            name: 'F & "G"',
            requests: [
              ApiDocsRequest(
                name: "It's <req>",
                method: 'GET',
                url: 'https://x/?a=1&b="><img src=x onerror=alert(1)>',
                headers: [ApiDocsField('X-"H"', '<v>')],
                body: ApiDocsBody(typeLabel: '<t>', language: 'json', text: '{"a": "<b>&"}'),
                examples: [ApiDocsExample(name: '<e>', statusCode: 200, body: '<p>&</p>')],
              ),
            ],
          ),
        ],
      ));
      expect(page, contains('<title>&lt;script&gt;alert(1)&lt;/script&gt;</title>'));
      expect(page, contains('Use &lt;b&gt;tags&lt;/b&gt; &amp; &quot;quotes&quot;'));
      expect(page, contains('<span class="tag">&lt;x&gt;</span>'));
      expect(page, contains('F &amp; &quot;G&quot;'));
      expect(page, contains('It&#39;s &lt;req&gt;'));
      expect(page, contains('a=1&amp;b=&quot;&gt;&lt;img src=x onerror=alert(1)&gt;'));
      expect(page, contains('X-&quot;H&quot;'));
      expect(page, contains('&lt;v&gt;'));
      expect(page, contains('Body (&lt;t&gt;)'));
      expect(page, contains('{&quot;a&quot;: &quot;&lt;b&gt;&amp;&quot;}'));
      expect(page, contains('&lt;p&gt;&amp;&lt;/p&gt;'));
      expect(page, contains('a&amp;b'));
      for (final raw in ['<script', '<img', '<b>', '<x>', '<req>', '<v>', '<e>', '<p>&']) {
        expect(page, isNot(contains(raw)), reason: raw);
      }
    });

    test('renders descriptions as markdown, below the section heading', () {
      final page = ApiDocsGenerator.toHtml(const ApiDocsModel(
        name: 'Api',
        description: 'Public **shop** API.\n\n# Overview\n\n- one\n- two\n\nSee [docs](https://example.com/a?b=1&c=2).',
      ));
      expect(page, contains('<p>Public <strong>shop</strong> API.</p>'));
      expect(page, contains('<h2>Overview</h2>'));
      expect(page, contains('<ul>\n<li>one</li>\n<li>two</li>\n</ul>'));
      expect(page, contains('<a href="https://example.com/a?b=1&amp;c=2" rel="noopener noreferrer" target="_blank">docs</a>'));
    });

    test('does not turn a javascript: link into a link', () {
      final page = ApiDocsGenerator.toHtml(const ApiDocsModel(
        name: 'Api',
        description: '[click](javascript:alert(1)) and [x](  JaVa\tScript:alert(2))',
      ));
      expect(page.toLowerCase(), isNot(contains('href="javascript')));
      expect(page, contains('click'));
    });

    test('an empty folder is still listed', () {
      expect(html, contains('<h2>Empty</h2>'));
      expect(html, contains('>Empty</a>'));
    });
  });

  group('secrets', () {
    const secrets = [
      'sk_live_abc123',
      'k-123456',
      'sid=abc',
      'zzz-query-secret',
      'hunter2',
      'pw123',
      'tok-999',
      'cs-1',
      'refresh-777',
      'var-secret-value',
    ];

    const model = ApiDocsModel(
      name: 'Secrets',
      authSummary: 'Bearer Token',
      variables: [
        ApiDocsField('baseUrl', 'https://api.example.com'),
        ApiDocsField('secret_key', 'var-secret-value'),
      ],
      requests: [
        ApiDocsRequest(
          name: 'Login',
          method: 'POST',
          url: 'https://user:hunter2@api.example.com/login?api_key=zzz-query-secret&page=2#frag',
          authSummary: 'Bearer Token',
          headers: [
            ApiDocsField('Authorization', 'Bearer sk_live_abc123'),
            ApiDocsField('X-API-Key', 'k-123456'),
            ApiDocsField('Cookie', 'sid=abc'),
            ApiDocsField('Accept', 'application/json'),
          ],
          queryParams: [ApiDocsField('api_key', 'zzz-query-secret'), ApiDocsField('page', '2')],
          body: ApiDocsBody(
            typeLabel: 'JSON',
            language: 'json',
            text: '{"user": "ann", "password": "hunter2", "nested": {"client_secret": "cs-1", "note": "keep"}}',
            fields: [ApiDocsField('password', 'pw123'), ApiDocsField('city', 'Oslo')],
          ),
          examples: [
            ApiDocsExample(
              name: 'OK',
              statusCode: 200,
              body: '{"access_token": "tok-999", "refresh_token":"refresh-777", "id": 1}',
            ),
          ],
        ),
        ApiDocsRequest(
          name: 'Refs',
          method: 'GET',
          url: '/refs?api_key={{apiKey}}',
          headers: [ApiDocsField('Authorization', 'Bearer {{token}}')],
          queryParams: [ApiDocsField('api_key', '{{apiKey}}')],
        ),
      ],
    );

    for (final entry in {'markdown': ApiDocsGenerator.toMarkdown(model), 'html': ApiDocsGenerator.toHtml(model)}.entries) {
      test('${entry.key}: no secret value appears', () {
        for (final secret in secrets) {
          expect(entry.value, isNot(contains(secret)), reason: secret);
        }
      });

      test('${entry.key}: everything that is not secret stays', () {
        for (final kept in [
          'Bearer Token',
          'api.example.com',
          'page=2',
          '#frag',
          'application/json',
          'Oslo',
          'keep',
          'ann',
          'access_token',
          'Bearer {{token}}',
          'api_key={{apiKey}}',
        ]) {
          expect(entry.value, contains(kept), reason: kept);
        }
      });

      test('${entry.key}: a masked value says so and keeps the scheme', () {
        expect(entry.value, contains('Bearer ••••••'));
        expect(entry.value, contains('api_key=••••••'));
        expect(entry.value, contains('user:••••••@'));
      });
    }
  });
}
