/// Two realistic documents for the generator tests, small enough for the expected cases to be worked out by hand.

/// OpenAPI 3.0 as YAML: `$ref`, `allOf` with required lists in two members, enums, ranges, lengths, a global bearer
/// scheme, one public operation (`security: []`), a 204 with no body and a text response.
const petShopSpec = r'''
openapi: 3.0.3
info:
  title: Pet Shop
  version: 1.2.0
servers:
  - url: https://api.petshop.test/v1
security:
  - bearerAuth: []
tags:
  - name: pets
  - name: system
paths:
  /pets:
    get:
      tags: [pets]
      summary: List pets
      operationId: listPets
      parameters:
        - name: status
          in: query
          required: true
          schema:
            type: string
            enum: [available, pending, sold]
        - name: limit
          in: query
          schema:
            type: integer
            minimum: 1
            maximum: 100
            default: 20
      responses:
        '200':
          description: A page of pets
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: '#/components/schemas/Pet'
        '400':
          description: Bad request
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Error'
    post:
      tags: [pets]
      summary: Create a pet
      operationId: createPet
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/NewPet'
      responses:
        '201':
          description: Created
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Pet'
        '422':
          description: Validation failed
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Error'
  /pets/{petId}:
    parameters:
      - name: petId
        in: path
        required: true
        schema:
          type: integer
          format: int64
          minimum: 1
    get:
      tags: [pets]
      summary: Get a pet
      responses:
        '200':
          description: The pet
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Pet'
        '404':
          description: Not found
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Error'
    delete:
      tags: [pets]
      summary: Delete a pet
      responses:
        '204':
          description: Deleted
        '404':
          description: Not found
  /health:
    get:
      tags: [system]
      summary: Health check
      security: []
      responses:
        '200':
          description: Alive
          content:
            text/plain:
              schema:
                type: string
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
  schemas:
    Error:
      type: object
      required: [code, message]
      properties:
        code:
          type: integer
        message:
          type: string
    NewPet:
      type: object
      required: [name, species]
      properties:
        name:
          type: string
          minLength: 1
          maxLength: 50
        species:
          type: string
          enum: [dog, cat, bird]
        age:
          type: integer
          minimum: 0
          maximum: 40
        tags:
          type: array
          maxItems: 5
          items:
            type: string
        vaccinated:
          type: boolean
    Pet:
      allOf:
        - $ref: '#/components/schemas/NewPet'
        - type: object
          required: [id]
          properties:
            id:
              type: integer
              format: int64
              readOnly: true
''';

/// Swagger 2.0 as JSON: `host`/`basePath`, a body parameter, an API key header as the global scheme, `default` as the
/// only error response of one operation, a boolean `exclusiveMinimum`, an int32 and a public operation.
const inventorySpec = r'''
{
  "swagger": "2.0",
  "info": {"title": "Inventory", "version": "2.0"},
  "host": "inventory.test",
  "basePath": "/api",
  "schemes": ["https"],
  "consumes": ["application/json"],
  "produces": ["application/json"],
  "securityDefinitions": {"apiKey": {"type": "apiKey", "name": "X-API-Key", "in": "header"}},
  "security": [{"apiKey": []}],
  "paths": {
    "/items": {
      "get": {
        "summary": "List items",
        "parameters": [
          {"name": "page", "in": "query", "type": "integer", "minimum": 1, "default": 1},
          {"name": "sort", "in": "query", "type": "string", "enum": ["name", "price"]}
        ],
        "responses": {
          "200": {"description": "OK", "schema": {"type": "array", "items": {"$ref": "#/definitions/Item"}}},
          "default": {"description": "Unexpected error", "schema": {"$ref": "#/definitions/Problem"}}
        }
      },
      "post": {
        "summary": "Add an item",
        "parameters": [
          {"name": "body", "in": "body", "required": true, "schema": {"$ref": "#/definitions/NewItem"}}
        ],
        "responses": {
          "201": {"description": "Created", "schema": {"$ref": "#/definitions/Item"}},
          "400": {"description": "Invalid", "schema": {"$ref": "#/definitions/Problem"}}
        }
      }
    },
    "/items/{sku}": {
      "get": {
        "summary": "Get an item",
        "security": [],
        "parameters": [
          {"name": "sku", "in": "path", "required": true, "type": "string", "minLength": 3, "maxLength": 12}
        ],
        "responses": {
          "200": {"description": "OK", "schema": {"$ref": "#/definitions/Item"}},
          "404": {"description": "Missing"}
        }
      }
    }
  },
  "definitions": {
    "Problem": {"type": "object", "required": ["title"], "properties": {"title": {"type": "string"}, "status": {"type": "integer"}}},
    "NewItem": {
      "type": "object",
      "required": ["sku", "price"],
      "properties": {
        "sku": {"type": "string", "minLength": 3, "maxLength": 12},
        "price": {"type": "number", "minimum": 0, "exclusiveMinimum": true},
        "stock": {"type": "integer", "format": "int32", "minimum": 0}
      }
    },
    "Item": {
      "allOf": [
        {"$ref": "#/definitions/NewItem"},
        {"type": "object", "required": ["updatedAt"], "properties": {"updatedAt": {"type": "string", "format": "date-time"}}}
      ]
    }
  }
}
''';

/// The cases the pet shop document gives, worked out by hand from the rules in `OpenApiTestGenerator`.
const petShopCases = <String>[
  'GET /pets (contract)',
  'GET /pets (missing query status)',
  'GET /pets (wrong type query limit)',
  'GET /pets (query status not in enum)',
  'GET /pets (query limit below minimum)',
  'GET /pets (query limit above maximum)',
  'GET /pets (no credentials)',
  'GET /pets (malformed token)',
  'POST /pets (contract)',
  'POST /pets (missing name)',
  'POST /pets (missing species)',
  'POST /pets (wrong type name)',
  'POST /pets (wrong type species)',
  'POST /pets (wrong type age)',
  'POST /pets (wrong type tags)',
  'POST /pets (wrong type vaccinated)',
  'POST /pets (empty body)',
  'POST /pets (malformed JSON)',
  'POST /pets (name too short)',
  'POST /pets (name too long)',
  'POST /pets (species not in enum)',
  'POST /pets (age below minimum)',
  'POST /pets (age above maximum)',
  'POST /pets (tags too many items)',
  'POST /pets (no credentials)',
  'POST /pets (malformed token)',
  'GET /pets/{petId} (contract)',
  'GET /pets/{petId} (wrong type path petId)',
  'GET /pets/{petId} (path petId below minimum)',
  'GET /pets/{petId} (path petId overflow)',
  'GET /pets/{petId} (no credentials)',
  'GET /pets/{petId} (malformed token)',
  'DELETE /pets/{petId} (contract)',
  'DELETE /pets/{petId} (wrong type path petId)',
  'DELETE /pets/{petId} (path petId below minimum)',
  'DELETE /pets/{petId} (path petId overflow)',
  'DELETE /pets/{petId} (no credentials)',
  'DELETE /pets/{petId} (malformed token)',
  'GET /health (contract)',
];

/// The cases the inventory document gives.
const inventoryCases = <String>[
  'GET /items (contract)',
  'GET /items (wrong type query page)',
  'GET /items (query page below minimum)',
  'GET /items (query page overflow)',
  'GET /items (query sort not in enum)',
  'GET /items (no credentials)',
  'GET /items (malformed token)',
  'POST /items (contract)',
  'POST /items (missing sku)',
  'POST /items (missing price)',
  'POST /items (wrong type sku)',
  'POST /items (wrong type price)',
  'POST /items (wrong type stock)',
  'POST /items (empty body)',
  'POST /items (malformed JSON)',
  'POST /items (sku too short)',
  'POST /items (sku too long)',
  'POST /items (price below minimum)',
  'POST /items (stock below minimum)',
  'POST /items (stock overflow)',
  'POST /items (no credentials)',
  'POST /items (malformed token)',
  'GET /items/{sku} (contract)',
  'GET /items/{sku} (path sku too short)',
  'GET /items/{sku} (path sku too long)',
];
