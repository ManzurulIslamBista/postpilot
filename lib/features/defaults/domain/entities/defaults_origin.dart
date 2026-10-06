enum DefaultsLevelKind { collection, folder }

/// Where an inherited value was set, for showing "from folder "Auth"" next to it.
final class DefaultsOrigin {
  final DefaultsLevelKind kind;

  /// The collection's or folder's id; null in a workspace file, where ids mean nothing.
  final int? id;
  final String name;

  const DefaultsOrigin(this.kind, this.name, {this.id});

  const DefaultsOrigin.collection(String name, {int? id}) : this(DefaultsLevelKind.collection, name, id: id);
  const DefaultsOrigin.folder(String name, {int? id}) : this(DefaultsLevelKind.folder, name, id: id);

  bool get isFolder => kind == DefaultsLevelKind.folder;

  /// `folder "Auth"` or `collection "Shop"`.
  String get label => name.trim().isEmpty ? kind.name : '${kind.name} "$name"';

  /// `from folder "Auth"`.
  String get fromLabel => 'from $label';

  @override
  bool operator ==(Object other) =>
      other is DefaultsOrigin && other.kind == kind && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(kind, id, name);
}
