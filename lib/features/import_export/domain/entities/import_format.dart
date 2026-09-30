enum ImportFormat {
  postman('Postman collection'),
  insomnia('Insomnia export'),
  har('HAR recording'),
  openApi('OpenAPI / Swagger document'),
  curl('cURL command'),
  backup('PostPilot backup'),
  unknown('Unrecognised format');

  final String label;
  const ImportFormat(this.label);
}
