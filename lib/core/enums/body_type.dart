enum BodyType {
  none,
  raw,
  formData,
  urlEncoded,
  graphql,

  /// One file sent as the whole body (an S3 `PUT`, `application/octet-stream`). Added after the others: a build that
  /// does not know it reads a stored `binary` as [none] (every store falls back to it for an unknown name).
  binary;

  String get label => switch (this) {
        BodyType.none => 'None',
        BodyType.raw => 'Raw',
        BodyType.formData => 'Form Data',
        BodyType.urlEncoded => 'x-www-form-urlencoded',
        BodyType.graphql => 'GraphQL',
        BodyType.binary => 'Binary',
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
