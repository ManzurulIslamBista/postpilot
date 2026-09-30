/// What a description or a tag is attached to. [dbValue] is the `kind` string
/// stored by the docs and tags tables.
enum EntityKind {
  collection('collection'),
  folder('folder'),
  request('request');

  final String dbValue;
  const EntityKind(this.dbValue);
}
