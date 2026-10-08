// An HMAC auth set on a collection or a folder is what a request on "Inherit from parent" is signed with, by the
// same path a send and a code snippet take (PrepareRequestUseCase).
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/defaults/domain/usecases/resolve_request_defaults_usecase.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/curl_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/hmac_presets.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/generate_code_snippet_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/prepare_request_usecase.dart';
import '../support/drift_repos.dart';
import '../support/shop_seed.dart';

// python: hmac.new(b'hunter2', b'{"a":1}', sha256).hexdigest()
const _githubHunter2 = 'sha256=6e73a1a57a6e6edb9dff174d2a53bc61a27cfc639a2964743ed35fd59c8bc82d';
// python: hmac.new(b'folder-secret', b'{"a":1}', sha256).hexdigest()
const _githubFolderSecret = 'sha256=c603f30ef5e89b57d75d968af33f09f5ad46ce22021aab0e03b88fe1537780cf';

const _body = RequestBody(type: BodyType.raw, rawText: '{"a":1}');

void main() {
  late AppDatabase db;
  late DriftRepos repos;
  late int shop;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
    shop = await repos.collectionRepository.createCollection('Shop');
  });
  tearDown(() => db.close());

  BuildVariableResolverUseCase buildResolver() => BuildVariableResolverUseCase(
        repos.collectionVariableRepository,
        repos.environmentRepository,
        repos.globalVariableRepository,
        repos.defaultsRepository,
      );

  PrepareRequestUseCase prepare() =>
      PrepareRequestUseCase(buildResolver(), repos.collectionAuthRepository, defaults: ResolveRequestDefaultsUseCase(repos.defaultsRepository));

  Future<ApiRequestEntity> request(String name, {int? folderId, RequestAuth auth = const RequestAuth(type: AuthType.inherit)}) async {
    final id = await addRequest(
      repos,
      shop,
      name,
      folderId: folderId,
      method: HttpMethod.post,
      url: 'https://shop.test/hooks/in',
      body: _body,
      auth: auth,
    );
    return (await repos.requestRepository.findById(id))!;
  }

  Future<void> setCollectionAuth(RequestAuth auth) => repos.collectionAuthRepository.setAuthJson(shop, auth.toJsonString());

  test('a request on Inherit is signed with the collection\'s HMAC auth', () async {
    await setCollectionAuth(const RequestAuth(type: AuthType.hmac, hmacSecret: 'hunter2'));

    final prepared = await prepare()(await request('Hook'));

    expect(prepared.spec.headers['X-Hub-Signature-256'], _githubHunter2);
    expect(prepared.auth.type, AuthType.hmac);
    expect(prepared.undefinedVariables, isEmpty);
  });

  test('the collection\'s secret may be a collection variable', () async {
    await setCollectionAuth(const RequestAuth(type: AuthType.hmac, hmacSecret: '{{whsec}}'));
    await repos.collectionVariableRepository
        .upsert(CollectionVariableEntity(id: 0, collectionId: shop, key: 'whsec', value: 'hunter2', enabled: true));

    final prepared = await prepare()(await request('Hook'));

    expect(prepared.spec.headers['X-Hub-Signature-256'], _githubHunter2);
  });

  test('the nearest folder that sets an auth wins over the collection', () async {
    final folder = await repos.collectionRepository.createFolder(collectionId: shop, name: 'Hooks');
    await setCollectionAuth(const RequestAuth(type: AuthType.hmac, hmacSecret: 'hunter2'));
    await repos.defaultsRepository.saveFolder(
      folder,
      const LevelDefaults(auth: RequestAuth(type: AuthType.hmac, hmacSecret: 'folder-secret')),
    );

    final inFolder = await prepare()(await request('In folder', folderId: folder));
    final outside = await prepare()(await request('Outside'));

    expect(inFolder.spec.headers['X-Hub-Signature-256'], _githubFolderSecret);
    expect(outside.spec.headers['X-Hub-Signature-256'], _githubHunter2);
  });

  test('a preset on the collection travels with it: Stripe\'s header and the timestamp come to the request', () async {
    await setCollectionAuth(HmacPresets.apply(const RequestAuth(type: AuthType.hmac, hmacSecret: 'hunter2'), HmacPreset.stripe));

    final spec = (await prepare()(await request('Hook'))).spec;

    expect(spec.headers['Stripe-Signature'], matches(RegExp(r'^t=\d{10},v1=[0-9a-f]{64}$')));
    expect(spec.headers.containsKey('X-Hub-Signature-256'), isFalse);
  });

  test('a request with an auth of its own is not signed by the collection\'s', () async {
    await setCollectionAuth(const RequestAuth(type: AuthType.hmac, hmacSecret: 'hunter2'));

    final none = await prepare()(await request('None', auth: const RequestAuth(type: AuthType.none)));
    final bearer = await prepare()(await request('Bearer', auth: const RequestAuth(type: AuthType.bearer, bearerToken: 't')));

    expect(none.spec.headers.containsKey('X-Hub-Signature-256'), isFalse);
    expect(bearer.spec.headers.containsKey('X-Hub-Signature-256'), isFalse);
    expect(bearer.spec.headers['Authorization'], 'Bearer t');
  });

  test('the snippet of an inheriting request has the signature, and the note when it depends on the clock', () async {
    await setCollectionAuth(const RequestAuth(type: AuthType.hmac, hmacSecret: 'hunter2'));
    final snippets = GenerateCodeSnippetUseCase(
      buildResolver(),
      repos.collectionAuthRepository,
      defaults: ResolveRequestDefaultsUseCase(repos.defaultsRepository),
    );
    final hook = await request('Hook');

    final github = await snippets(GenerateCodeSnippetParams(hook, const CurlGenerator()));
    expect(github, contains("--header 'X-Hub-Signature-256: $_githubHunter2'"));
    expect(github, isNot(contains('HMAC signature:')));

    await setCollectionAuth(HmacPresets.apply(const RequestAuth(type: AuthType.hmac, hmacSecret: 'hunter2'), HmacPreset.stripe));
    final stripe = await snippets(GenerateCodeSnippetParams(hook, const CurlGenerator()));
    expect(stripe, contains("--header 'Stripe-Signature: t="));
    expect(stripe, contains('# HMAC signature:'));
  });
}
