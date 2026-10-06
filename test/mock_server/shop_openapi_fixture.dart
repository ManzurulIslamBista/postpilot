// A shop API as an OpenAPI 3 document, built to hold every case the mock server has to handle: a list wrapped in an
// envelope with paging meta, a plain list with a cursor, a resource with an integer id and one with a string id, a
// collection nested under a parent, required query/header/body fields, a shared error schema, `$ref` and `allOf`, an
// `example`, nullable and read-only and write-only properties.
//
// The expectations in the tests are worked out by hand from this document (ids count up from 1, `limit` defaults to 5, ...).
import 'dart:convert';

Map<String, dynamic> _ref(String name) => {r'$ref': '#/components/schemas/$name'};

Map<String, dynamic> _json(Object schema) => {
      'content': {
        'application/json': {'schema': schema},
      },
    };

Map<String, dynamic> _query(String name, Map<String, dynamic> schema, {bool required = false}) =>
    {'name': name, 'in': 'query', 'required': required, 'schema': schema};

Map<String, dynamic> _path(String name, String type) => {
      'name': name,
      'in': 'path',
      'required': true,
      'schema': {'type': type},
    };

final Map<String, dynamic> shopOpenApi = {
  'openapi': '3.0.3',
  'info': {'title': 'Shop', 'version': '1.0.0'},
  'servers': [
    {'url': 'https://api.shop.test/api/v1'},
  ],
  'paths': {
    '/users': {
      'get': {
        'operationId': 'listUsers',
        'summary': 'List users',
        'parameters': [
          _query('page', {'type': 'integer', 'minimum': 1}),
          _query('limit', {'type': 'integer', 'default': 5, 'maximum': 20}),
          _query('status', {'type': 'string', 'enum': ['active', 'blocked']}),
        ],
        'responses': {
          '200': {
            'description': 'ok',
            ..._json({
              'type': 'object',
              'properties': {
                'data': {'type': 'array', 'items': _ref('User')},
                'total': {'type': 'integer'},
                'page': {'type': 'integer'},
                'limit': {'type': 'integer'},
                'totalPages': {'type': 'integer'},
              },
            }),
          },
        },
      },
      'post': {
        'operationId': 'createUser',
        'summary': 'Create a user',
        'requestBody': {'required': true, ..._json(_ref('User'))},
        'responses': {
          '201': {'description': 'created', ..._json(_ref('User'))},
          '400': {'description': 'bad', ..._json(_ref('Error'))},
        },
      },
    },
    '/users/{id}': {
      'parameters': [_path('id', 'integer')],
      'get': {
        'operationId': 'getUser',
        'summary': 'One user',
        'responses': {
          '200': {'description': 'ok', ..._json(_ref('User'))},
          '404': {'description': 'missing', ..._json(_ref('Error'))},
        },
      },
      'put': {
        'operationId': 'replaceUser',
        'requestBody': {'required': true, ..._json(_ref('User'))},
        'responses': {
          '200': {'description': 'ok', ..._json(_ref('User'))},
          '404': {'description': 'missing', ..._json(_ref('Error'))},
        },
      },
      'patch': {
        'operationId': 'updateUser',
        'requestBody': {'required': true, ..._json(_ref('User'))},
        'responses': {
          '200': {'description': 'ok', ..._json(_ref('User'))},
          '404': {'description': 'missing', ..._json(_ref('Error'))},
        },
      },
      'delete': {
        'operationId': 'deleteUser',
        'responses': {
          '204': {'description': 'gone'},
          '404': {'description': 'missing', ..._json(_ref('Error'))},
        },
      },
    },
    '/users/me': {
      'get': {
        'operationId': 'me',
        'responses': {
          '200': {
            'description': 'ok',
            'content': {
              'application/json': {
                'schema': _ref('User'),
                'example': {'id': 99, 'name': 'Me Myself', 'email': 'me@shop.test', 'role': 'admin'},
              },
            },
          },
        },
      },
    },
    '/users/{userId}/orders': {
      'get': {
        'operationId': 'listOrders',
        'parameters': [_path('userId', 'integer')],
        'responses': {
          '200': {'description': 'ok', ..._json({'type': 'array', 'items': _ref('Order')})},
        },
      },
      'post': {
        'operationId': 'createOrder',
        'parameters': [_path('userId', 'integer')],
        'requestBody': {'required': true, ..._json(_ref('Order'))},
        'responses': {
          '201': {'description': 'created', ..._json(_ref('Order'))},
        },
      },
    },
    '/users/{userId}/orders/{orderId}': {
      'get': {
        'operationId': 'getOrder',
        'parameters': [_path('userId', 'integer'), _path('orderId', 'integer')],
        'responses': {
          '200': {'description': 'ok', ..._json(_ref('Order'))},
        },
      },
    },
    '/products': {
      'get': {
        'operationId': 'listProducts',
        'parameters': [
          _query('cursor', {'type': 'string'}),
          _query('limit', {'type': 'integer', 'default': 4}),
          _query('category', {'type': 'string'}),
        ],
        'responses': {
          '200': {'description': 'ok', ..._json({'type': 'array', 'items': _ref('Product')})},
        },
      },
      'post': {
        'operationId': 'createProduct',
        'requestBody': {'required': true, ..._json(_ref('Product'))},
        'responses': {
          '201': {'description': 'created', ..._json(_ref('Product'))},
        },
      },
    },
    '/products/{sku}': {
      'get': {
        'operationId': 'getProduct',
        'parameters': [_path('sku', 'string')],
        'responses': {
          '200': {'description': 'ok', ..._json(_ref('Product'))},
          '404': {'description': 'missing', ..._json(_ref('Error'))},
        },
      },
      'delete': {
        'operationId': 'deleteProduct',
        'parameters': [_path('sku', 'string')],
        'responses': {
          '204': {'description': 'gone'},
        },
      },
    },
    '/search': {
      'get': {
        'operationId': 'search',
        'parameters': [
          _query('q', {'type': 'string', 'minLength': 2}, required: true),
          {'name': 'X-Tenant', 'in': 'header', 'required': true, 'schema': {'type': 'string'}},
          _query('size', {'type': 'integer', 'minimum': 1, 'maximum': 50}),
        ],
        'responses': {
          '200': {
            'description': 'ok',
            ..._json({
              'type': 'object',
              'properties': {
                'hits': {'type': 'array', 'items': _ref('Product')},
              },
            }),
          },
          '400': {'description': 'bad', ..._json(_ref('Error'))},
        },
      },
    },
    '/stats': {
      'get': {
        'operationId': 'stats',
        'responses': {
          '200': {
            'description': 'ok',
            ..._json({
              'type': 'object',
              'properties': {
                'visitors': {'type': 'integer', 'minimum': 100, 'maximum': 200},
                'revenue': {'type': 'number', 'minimum': 10, 'maximum': 20},
                'online': {'type': 'boolean'},
              },
            }),
          },
        },
      },
    },
    '/ping': {
      'get': {
        'operationId': 'ping',
        'responses': {
          '204': {'description': 'pong'},
        },
      },
    },
  },
  'components': {
    'schemas': {
      'Base': {
        'type': 'object',
        'properties': {
          'id': {'type': 'integer', 'readOnly': true},
          'createdAt': {'type': 'string', 'format': 'date-time', 'readOnly': true},
        },
      },
      'User': {
        'allOf': [
          _ref('Base'),
          {
            'type': 'object',
            'required': ['name', 'email'],
            'properties': {
              'name': {'type': 'string', 'minLength': 2},
              'email': {'type': 'string', 'format': 'email'},
              'phone': {'type': 'string'},
              'role': {
                'type': 'string',
                'enum': ['admin', 'member'],
              },
              'age': {'type': 'integer', 'minimum': 18, 'maximum': 80},
              'password': {'type': 'string', 'writeOnly': true},
              'nickname': {'type': 'string', 'nullable': true},
              'tags': {
                'type': 'array',
                'items': {'type': 'string'},
              },
            },
          },
        ],
      },
      'Order': {
        'type': 'object',
        'required': ['total'],
        'properties': {
          'id': {'type': 'integer'},
          'total': {'type': 'number', 'minimum': 5, 'maximum': 500},
          'currency': {'type': 'string', 'default': 'EUR'},
        },
      },
      'Product': {
        'type': 'object',
        'required': ['title'],
        'properties': {
          'sku': {'type': 'string', 'pattern': r'^[A-Z]{3}-\d{4}$'},
          'title': {'type': 'string'},
          'price': {'type': 'number'},
          'category': {
            'type': 'string',
            'enum': ['books', 'games'],
          },
          'tags': {'type': 'array', 'items': {'type': 'string'}, 'minItems': 2, 'maxItems': 2},
        },
      },
      'Error': {
        'type': 'object',
        'required': ['code', 'message'],
        'properties': {
          'code': {'type': 'integer'},
          'message': {'type': 'string'},
          'details': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'field': {'type': 'string'},
                'message': {'type': 'string'},
              },
            },
          },
        },
      },
    },
  },
};

final String shopOpenApiJson = jsonEncode(shopOpenApi);

/// The same shop reduced to what Swagger 2 spells differently: `host` and `basePath`, parameters with the type on the
/// parameter itself, a `body` parameter and `definitions`.
final String shopSwagger2Json = jsonEncode({
  'swagger': '2.0',
  'info': {'title': 'Pets', 'version': '1'},
  'host': 'pets.test',
  'basePath': '/v2',
  'schemes': ['https'],
  'paths': {
    '/pets': {
      'get': {
        'operationId': 'listPets',
        'parameters': [
          {'name': 'limit', 'in': 'query', 'type': 'integer', 'default': 3},
        ],
        'responses': {
          '200': {
            'description': 'ok',
            'schema': {'type': 'array', 'items': {r'$ref': '#/definitions/Pet'}},
          },
        },
      },
      'post': {
        'operationId': 'addPet',
        'parameters': [
          {'name': 'body', 'in': 'body', 'required': true, 'schema': {r'$ref': '#/definitions/Pet'}},
        ],
        'responses': {
          '201': {'description': 'created', 'schema': {r'$ref': '#/definitions/Pet'}},
        },
      },
    },
    '/pets/{petId}': {
      'get': {
        'operationId': 'getPet',
        'parameters': [
          {'name': 'petId', 'in': 'path', 'required': true, 'type': 'integer'},
        ],
        'responses': {
          '200': {'description': 'ok', 'schema': {r'$ref': '#/definitions/Pet'}},
        },
      },
    },
  },
  'definitions': {
    'Pet': {
      'type': 'object',
      'required': ['name'],
      'properties': {
        'id': {'type': 'integer'},
        'name': {'type': 'string'},
        'tag': {'type': 'string'},
      },
    },
  },
});
