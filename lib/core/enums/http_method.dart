enum HttpMethod {
  get,
  post,
  put,
  patch,
  delete,
  head,
  options;

  String get label => name.toUpperCase();

  static HttpMethod fromString(String? value) => HttpMethod.values.firstWhere(
        (m) => m.name.toLowerCase() == value?.toLowerCase(),
        orElse: () => HttpMethod.get,
      );
}
