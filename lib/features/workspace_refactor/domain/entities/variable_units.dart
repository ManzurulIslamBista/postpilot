import '../../../collections/domain/entities/collection_variable_entity.dart';
import '../../../environments/domain/entities/environment_entity.dart';
import '../../../environments/domain/entities/global_variable_entity.dart';
import 'field_builders.dart';
import 'refactor_scope.dart';
import 'unit_field.dart';

/// One variable of an environment, of the globals or of a collection: a row of its own, written and deleted alone.
/// What the three share is here; they only differ in the entity they hold.
abstract class VariableRowUnit extends RefactorUnit {
  const VariableRowUnit();

  String get name;
  String get value;
  bool get isSecret;
  bool get enabled;
  VariableHome get home;
  String get containerKey;

  /// `Environment "Dev"`, `Globals`, `Collection "Shop"`.
  String get where;

  VariableRowUnit withName(String name);
  VariableRowUnit withValue(String value);

  @override
  bool get isRow => true;

  @override
  Iterable<UnitField> fields() sync* {
    if (name.isNotEmpty) {
      yield UnitField(
        path: 'key',
        group: 'row',
        scope: RefactorScope.variables,
        label: 'Variable name',
        value: name,
        write: withName,
        defines: name.trim().isEmpty
            ? null
            : VariableDefinition(
                name: name.trim(),
                home: home,
                containerKey: containerKey,
                where: where,
                unitKey: key,
                keyPath: 'key',
                removePath: 'row',
                value: value,
                secret: isSecret,
                enabled: enabled,
              ),
      );
    }
    if (value.isNotEmpty) {
      yield UnitField(
        path: 'value',
        group: 'row',
        scope: RefactorScope.variables,
        label: 'Variable "${shorten(name)}" value',
        value: value,
        secret: isSecret,
        write: withValue,
      );
    }
  }
}

final class EnvironmentVariableUnit extends VariableRowUnit {
  final EnvironmentVariableEntity variable;
  final String environmentName;

  const EnvironmentVariableUnit({required this.variable, required this.environmentName});

  @override
  UnitKind get kind => UnitKind.environmentVariable;
  @override
  int get id => variable.id;
  @override
  List<String> get trail => ['Environments', environmentName];
  @override
  String get name => variable.key;
  @override
  String get value => variable.value;
  @override
  bool get isSecret => variable.isSecret;
  @override
  bool get enabled => variable.enabled;
  @override
  VariableHome get home => VariableHome.environment;
  @override
  String get containerKey => 'environment:${variable.environmentId}';
  @override
  String get where => 'Environment "${shorten(environmentName)}"';

  EnvironmentVariableUnit _copy({String? key, String? value}) => EnvironmentVariableUnit(
    variable: EnvironmentVariableEntity(
      id: variable.id,
      environmentId: variable.environmentId,
      key: key ?? variable.key,
      value: value ?? variable.value,
      isSecret: variable.isSecret,
      enabled: variable.enabled,
    ),
    environmentName: environmentName,
  );

  @override
  EnvironmentVariableUnit withName(String name) => _copy(key: name);
  @override
  EnvironmentVariableUnit withValue(String value) => _copy(value: value);
}

final class GlobalVariableUnit extends VariableRowUnit {
  final GlobalVariableEntity variable;

  const GlobalVariableUnit({required this.variable});

  @override
  UnitKind get kind => UnitKind.globalVariable;
  @override
  int get id => variable.id;
  @override
  List<String> get trail => const ['Globals'];
  @override
  String get name => variable.key;
  @override
  String get value => variable.value;
  @override
  bool get isSecret => variable.isSecret;
  @override
  bool get enabled => variable.enabled;
  @override
  VariableHome get home => VariableHome.global;
  @override
  String get containerKey => 'global';
  @override
  String get where => 'Globals';

  GlobalVariableUnit _copy({String? key, String? value}) => GlobalVariableUnit(
    variable: GlobalVariableEntity(
      id: variable.id,
      key: key ?? variable.key,
      value: value ?? variable.value,
      isSecret: variable.isSecret,
      enabled: variable.enabled,
    ),
  );

  @override
  GlobalVariableUnit withName(String name) => _copy(key: name);
  @override
  GlobalVariableUnit withValue(String value) => _copy(value: value);
}

final class CollectionVariableUnit extends VariableRowUnit {
  final CollectionVariableEntity variable;
  final String collectionName;

  const CollectionVariableUnit({required this.variable, required this.collectionName});

  @override
  UnitKind get kind => UnitKind.collectionVariable;
  @override
  int get id => variable.id;
  @override
  List<String> get trail => [collectionName, 'Collection variables'];
  @override
  String get name => variable.key;
  @override
  String get value => variable.value;

  /// Collection variables have no secret flag.
  @override
  bool get isSecret => false;
  @override
  bool get enabled => variable.enabled;
  @override
  VariableHome get home => VariableHome.collection;
  @override
  String get containerKey => 'collection:${variable.collectionId}';
  @override
  String get where => 'Collection "${shorten(collectionName)}"';

  CollectionVariableUnit _copy({String? key, String? value}) => CollectionVariableUnit(
    variable: CollectionVariableEntity(
      id: variable.id,
      collectionId: variable.collectionId,
      key: key ?? variable.key,
      value: value ?? variable.value,
      enabled: variable.enabled,
    ),
    collectionName: collectionName,
  );

  @override
  CollectionVariableUnit withName(String name) => _copy(key: name);
  @override
  CollectionVariableUnit withValue(String value) => _copy(value: value);
}
