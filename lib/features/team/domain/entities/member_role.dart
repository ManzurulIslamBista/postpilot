enum MemberRole {
  owner,
  editor,
  viewer;

  String get label => name[0].toUpperCase() + name.substring(1);

  static MemberRole fromString(String value) =>
      MemberRole.values.firstWhere((r) => r.name == value, orElse: () => MemberRole.viewer);
}
