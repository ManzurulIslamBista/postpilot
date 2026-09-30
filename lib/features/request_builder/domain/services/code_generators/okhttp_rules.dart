/// OkHttp throws on `.method("POST", null)`, so these verbs need at least an
/// empty body.
bool okHttpRequiresBody(String method) =>
    const {'POST', 'PUT', 'PATCH', 'PROPPATCH', 'REPORT'}.contains(method.toUpperCase());
