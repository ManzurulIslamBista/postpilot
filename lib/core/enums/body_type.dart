enum BodyType {
  none,
  raw,
  formData,
  urlEncoded,
  graphql;

  String get label => switch (this) {
        BodyType.none => 'None',
        BodyType.raw => 'Raw',
        BodyType.formData => 'Form Data',
        BodyType.urlEncoded => 'x-www-form-urlencoded',
        BodyType.graphql => 'GraphQL',
      };
}

enum RawContentType {
  json,
  text,
  xml,
  html,
  javascript;

  String get mimeType => switch (this) {
        RawContentType.json => 'application/json',
        RawContentType.text => 'text/plain',
        RawContentType.xml => 'application/xml',
        RawContentType.html => 'text/html',
        RawContentType.javascript => 'application/javascript',
      };
}
