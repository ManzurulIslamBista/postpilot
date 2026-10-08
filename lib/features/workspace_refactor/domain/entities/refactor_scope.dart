/// The parts of a workspace the find-and-replace tool can look in; each is one toggle in the dialog.
enum RefactorScope {
  names('Names', 'Collection, folder and request names'),
  urls('URLs', 'The URL of every request'),
  queryParams('Query params', 'Keys and values'),
  headers('Headers', 'Keys and values of request headers'),
  bodies('Bodies', 'Raw, form-data, urlencoded and GraphQL bodies'),
  auth('Auth', 'The auth config of every request'),
  scripts('Tests and extractors', 'Assertions and extractors of requests'),
  docs('Docs and notes', 'The descriptions of collections, folders and requests'),
  tags('Tags', 'Collection, folder and request tags'),
  examples('Response examples', 'Names, headers and bodies of saved examples'),
  defaults('Collection and folder defaults', 'Headers, auth and tests every request inherits'),
  variables('Variables', 'Keys and values of environment, global, collection and folder variables');

  const RefactorScope(this.label, this.hint);

  final String label;
  final String hint;

  /// Every scope: what the tool searches until the user narrows it down.
  static final Set<RefactorScope> all = Set.unmodifiable(values);
}
